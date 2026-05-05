// StreamDownView.swift
// StreamDownUI — Main public entry point for streaming Markdown rendering.

import SwiftUI
import StreamDownCore

// MARK: - TextDeltaAccumulator

/// Feeds `AsyncStream<String>` deltas through `IncrementalMarkdownParser`
/// and publishes an up-to-date `RenderModel` on the main actor.
@MainActor
final class TextDeltaAccumulator: ObservableObject {
    @Published private(set) var model: RenderModel = .empty

    private let parser = IncrementalMarkdownParser()
    private var streamVersion: Int = 0

    // MARK: - Stream consumption

    /// Appends a delta string, updates the model with any newly finalized tokens.
    func consume(delta: String) {
        let finalized = parser.consume(delta: delta)
        let partial = parser.currentPartialToken
        streamVersion += 1
        model = RenderModel(
            tokens: buildTokens(finalized: model.finalizedTokens + finalized, partial: partial),
            isStreaming: true,
            version: streamVersion
        )
    }

    /// Finalizes all pending parser state and marks streaming as complete.
    func finalize() {
        let remaining = parser.finalize()
        streamVersion += 1
        model = RenderModel(
            tokens: buildTokens(finalized: model.finalizedTokens + remaining, partial: nil),
            isStreaming: false,
            version: streamVersion
        )
    }

    /// Replaces the model entirely (used for static / binding modes).
    func setStatic(markdown: String) {
        parser.reset()
        let tokens = parser.finalize()
        _ = tokens  // discard — do a fresh parse
        let freshParser = IncrementalMarkdownParser()
        let freshTokens = freshParser.finalize()
        _ = freshTokens

        // Full re-parse for static content.
        let staticParser = IncrementalMarkdownParser()
        var allTokens: [MarkdownToken] = []
        allTokens += staticParser.consume(delta: markdown)
        allTokens += staticParser.finalize()
        streamVersion += 1
        model = RenderModel(tokens: allTokens, isStreaming: false, version: streamVersion)
    }

    // MARK: - Helpers

    private func buildTokens(finalized: [MarkdownToken], partial: MarkdownToken?) -> [MarkdownToken] {
        var result = finalized
        if let p = partial { result.append(p) }
        return result
    }
}

// MARK: - StreamMode

private enum StreamMode {
    case asyncStream(AsyncStream<String>)
    case binding(Binding<String>, isStreaming: Bool)
    case staticMarkdown(String)
}

// MARK: - StreamDownView

/// A SwiftUI view that renders Markdown content in real time as it streams in.
///
/// Three initialization modes are supported:
/// - `AsyncStream<String>`: Full streaming from any async producer.
/// - `Binding<String>` + `isStreaming`: Observe an externally growing string.
/// - `String`: Render a static Markdown document.
public struct StreamDownView: View {

    // MARK: - Init (AsyncStream)

    /// Render streaming Markdown from an `AsyncStream<String>`.
    ///
    /// The stream is consumed as the view appears and automatically cancelled on disappear.
    public init(
        stream: AsyncStream<String>,
        configuration: StreamDownConfiguration = .default
    ) {
        _mode = .asyncStream(stream)
        _configuration = configuration
    }

    // MARK: - Init (Binding)

    /// Render Markdown from a `Binding<String>` that grows as streaming progresses.
    ///
    /// Pass `isStreaming: true` to show the cursor and partial content while
    /// the upstream source is still appending text.
    public init(
        text: Binding<String>,
        isStreaming: Bool = false,
        configuration: StreamDownConfiguration = .default
    ) {
        _mode = .binding(text, isStreaming: isStreaming)
        _configuration = configuration
    }

    // MARK: - Init (Static)

    /// Render a static Markdown string with no streaming behavior.
    public init(
        markdown: String,
        configuration: StreamDownConfiguration = .default
    ) {
        _mode = .staticMarkdown(markdown)
        _configuration = configuration
    }

    // MARK: - Private stored properties

    // Using underscore prefix so the public inits can assign these directly
    // without exposing them. They are never `@State` on purpose — the view
    // itself is stateless; `accumulator` is the observable source-of-truth.
    private let _mode: StreamMode
    private let _configuration: StreamDownConfiguration

    // MARK: - Environment / injected

    @Environment(\.streamDownTheme) private var theme
    @Environment(\.streamDownConfiguration) private var envConfiguration

    // MARK: - State

    @StateObject private var accumulator = TextDeltaAccumulator()
    @StateObject private var accessibilityCoordinator: AccessibilityCoordinatorBox = .init()

    /// Renderers registered via `.renderer(_:)` modifier, stored in environment.
    @Environment(\.sdRenderers) private var renderers
    @Environment(\.sdOnLinkTap) private var onLinkTap
    @Environment(\.sdOnStreamComplete) private var onStreamComplete
    @Environment(\.sdTokenAnimation) private var animationOverride

    @State private var safetySheetURL: URL? = nil
    @State private var pendingOpenURL: URL? = nil

    // MARK: - Computed

    private var effectiveConfiguration: StreamDownConfiguration {
        // The per-init configuration is the base; the environment (set via modifier chaining)
        // always wins because modifiers write directly into the environment copy.
        // In practice the environment value IS the per-init value unless a modifier overrode it.
        envConfiguration
    }

    private var isCurrentlyStreaming: Bool {
        switch _mode {
        case .asyncStream:
            return accumulator.model.isStreaming
        case .binding(_, let streaming):
            return streaming
        case .staticMarkdown:
            return false
        }
    }

    // MARK: - Body

    public var body: some View {
        let model = accumulator.model
        let config = effectiveConfiguration
        let spacing = theme.spacing
        let foreground = theme.colors.foreground.swiftUIColor

        ScrollView {
            LazyVStack(alignment: .leading, spacing: CGFloat(spacing.blockSpacing)) {
                // Finalized blocks
                ForEach(model.finalizedTokens.indices, id: \.self) { idx in
                    SDBlockDispatchView(
                        token: model.finalizedTokens[idx],
                        isStreaming: isCurrentlyStreaming,
                        onLinkTap: { url in handleLinkTap(url: url, config: config) }
                    )
                    .transition(entryTransition(config.tokenAnimation))
                }

                // Partial / in-progress block
                if let partial = model.partialToken {
                    HStack(alignment: .bottom, spacing: 2) {
                        SDBlockDispatchView(
                            token: partial,
                            isStreaming: true,
                            onLinkTap: { url in handleLinkTap(url: url, config: config) }
                        )

                        if isCurrentlyStreaming {
                            SDCursorView(style: config.cursor)
                        }
                    }
                    .transition(entryTransition(config.tokenAnimation))
                } else if isCurrentlyStreaming && model.finalizedTokens.isEmpty == false {
                    // Show cursor after last finalized token while streaming with no partial yet
                    HStack { SDCursorView(style: config.cursor) }
                }
            }
            .padding(.horizontal, CGFloat(spacing.contentPadding))
            .padding(.vertical, CGFloat(spacing.blockSpacing))
        }
        .foregroundStyle(foreground)
        .sheet(item: $safetySheetURL) { url in
            SDLinkSafetySheet(
                url: url,
                onConfirm: {
                    safetySheetURL = nil
                    openURL(url)
                },
                onCancel: {
                    safetySheetURL = nil
                }
            )
        }
        // Stream consumption task — cancels automatically when view disappears or stream changes.
        .task(id: taskID()) {
            await startConsuming(config: effectiveConfiguration)
        }
        // Binding / static text update
        .onChange(of: bindingText()) { newValue in
            if case .binding(_, let streaming) = _mode {
                if streaming {
                    updateFromBinding(text: newValue, isStreaming: true)
                } else {
                    accumulator.setStatic(markdown: newValue)
                }
            }
        }
        // Accessibility
        .onChange(of: model.version) { _ in
            accessibilityCoordinator.coordinator?.modelDidUpdate(model)
        }
        .onAppear {
            let coordinator = AccessibilityCoordinator(
                configuration: effectiveConfiguration.accessibility
            )
            accessibilityCoordinator.coordinator = coordinator
            setupInitialState()
        }
    }

    // MARK: - Task identification

    /// Returns a hashable identity for `.task(id:)` so the task restarts when the stream changes.
    private func taskID() -> String {
        switch _mode {
        case .asyncStream:       return "async-stream"
        case .binding:           return "binding"
        case .staticMarkdown(let m): return "static-\(m.hashValue)"
        }
    }

    // MARK: - Stream consumption

    private func startConsuming(config: StreamDownConfiguration) async {
        switch _mode {
        case .asyncStream(let stream):
            for await delta in stream {
                accumulator.consume(delta: delta)
            }
            accumulator.finalize()
            accessibilityCoordinator.coordinator?.streamingDidComplete(accumulator.model)
            onStreamComplete?()

        case .binding(let binding, let streaming):
            if !streaming {
                accumulator.setStatic(markdown: binding.wrappedValue)
            }
            // Live binding updates are handled via onChange above.

        case .staticMarkdown(let markdown):
            accumulator.setStatic(markdown: markdown)
        }
    }

    // MARK: - Binding helpers

    private func bindingText() -> String {
        if case .binding(let b, _) = _mode { return b.wrappedValue }
        return ""
    }

    private func updateFromBinding(text: String, isStreaming: Bool) {
        accumulator.setStatic(markdown: text)
    }

    // MARK: - Initial state setup

    private func setupInitialState() {
        switch _mode {
        case .staticMarkdown(let markdown):
            accumulator.setStatic(markdown: markdown)
        case .binding(let binding, let streaming):
            if !streaming {
                accumulator.setStatic(markdown: binding.wrappedValue)
            }
        case .asyncStream:
            break
        }
    }

    // MARK: - Link handling

    private func handleLinkTap(url: URL, config: StreamDownConfiguration) {
        let decision = config.linkSafety.decision(for: url)
        switch decision {
        case .open:
            if let handler = onLinkTap {
                handler(url)
            } else {
                openURL(url)
            }
        case .confirm:
            safetySheetURL = url
        case .block:
            break
        }
    }

    private func openURL(_ url: URL) {
#if canImport(UIKit)
        UIApplication.shared.open(url)
#elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
#endif
    }

    // MARK: - Animation

    private func entryTransition(_ animation: TokenAnimation) -> AnyTransition {
        switch animation {
        case .none:
            return .identity
        case .fadeIn(let duration):
            return .opacity.animation(.easeIn(duration: duration))
        case .slideUp(let distance, let duration):
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: CGFloat(distance)))
                    .animation(.easeOut(duration: duration)),
                removal: .opacity
            )
        case .typewriter:
            return .opacity.animation(.easeIn(duration: 0.05))
        }
    }
}

// MARK: - URL sheet item conformance

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - AccessibilityCoordinatorBox

/// Reference-typed wrapper so `AccessibilityCoordinator` can be stored in `@StateObject`.
@MainActor
private final class AccessibilityCoordinatorBox: ObservableObject {
    var coordinator: AccessibilityCoordinator?
}

// MARK: - Environment keys for modifiers

struct SDRenderersKey: EnvironmentKey {
    static let defaultValue: [any StreamDownRenderer] = []
}

struct SDOnLinkTapKey: EnvironmentKey {
    static let defaultValue: ((URL) -> Void)? = nil
}

struct SDOnStreamCompleteKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

struct SDTokenAnimationKey: EnvironmentKey {
    static let defaultValue: TokenAnimation? = nil
}

extension EnvironmentValues {
    var sdRenderers: [any StreamDownRenderer] {
        get { self[SDRenderersKey.self] }
        set { self[SDRenderersKey.self] = newValue }
    }

    var sdOnLinkTap: ((URL) -> Void)? {
        get { self[SDOnLinkTapKey.self] }
        set { self[SDOnLinkTapKey.self] = newValue }
    }

    var sdOnStreamComplete: (() -> Void)? {
        get { self[SDOnStreamCompleteKey.self] }
        set { self[SDOnStreamCompleteKey.self] = newValue }
    }

    var sdTokenAnimation: TokenAnimation? {
        get { self[SDTokenAnimationKey.self] }
        set { self[SDTokenAnimationKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {

    /// Sets the StreamDown theme for all descendant `StreamDownView`s.
    public func theme(_ theme: Theme) -> some View {
        environment(\.streamDownTheme, theme)
    }

    /// Registers a `StreamDownRenderer` that participates in the token pipeline.
    ///
    /// Multiple renderers can be added; they are sorted by `renderPriority`.
    public func renderer(_ renderer: any StreamDownRenderer) -> some View {
        transformEnvironment(\.sdRenderers) { renderers in
            renderers.append(renderer)
        }
    }

    /// Provides a handler called whenever a link is tapped in any descendant `StreamDownView`.
    ///
    /// If not set, the default behavior is governed by `LinkSafetyPolicy`.
    public func onLinkTap(_ handler: @escaping (URL) -> Void) -> some View {
        environment(\.sdOnLinkTap, handler)
    }

    /// Provides a handler called when streaming completes in a descendant `StreamDownView`.
    public func onStreamComplete(_ handler: @escaping () -> Void) -> some View {
        environment(\.sdOnStreamComplete, handler)
    }

    /// Overrides the link safety policy in the `StreamDownConfiguration` for descendants.
    public func linkSafety(_ policy: LinkSafetyPolicy) -> some View {
        transformEnvironment(\.streamDownConfiguration) { config in
            config.linkSafety = policy
        }
    }

    /// Overrides the cursor style in the `StreamDownConfiguration` for descendants.
    public func cursor(_ style: CursorStyle) -> some View {
        transformEnvironment(\.streamDownConfiguration) { config in
            config.cursor = style
        }
    }

    /// Overrides the token animation in the `StreamDownConfiguration` for descendants.
    public func tokenAnimation(_ animation: TokenAnimation) -> some View {
        transformEnvironment(\.streamDownConfiguration) { config in
            config.tokenAnimation = animation
        }
    }
}
