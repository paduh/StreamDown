// StreamDownRenderer.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

// MARK: - Supporting types

/// Immutable context passed once when a renderer is activated.
public struct RendererContext: Sendable {
    public let theme: Theme
    public let configuration: StreamDownConfiguration

    public init(theme: Theme, configuration: StreamDownConfiguration) {
        self.theme         = theme
        self.configuration = configuration
    }
}

/// Per-token context provided to `willRender`.
public struct RenderContext: Sendable {
    /// The token being evaluated.
    public let token: MarkdownToken

    /// Nesting depth (0 = top level, 1 = inside a blockquote or list, …).
    public let depth: Int

    /// `true` when the token is a `.partial` in-progress sentinel.
    public let isPartial: Bool

    /// The active theme at the time of rendering.
    public let theme: Theme

    public init(token: MarkdownToken, depth: Int, isPartial: Bool, theme: Theme) {
        self.token     = token
        self.depth     = depth
        self.isPartial = isPartial
        self.theme     = theme
    }
}

// MARK: - RendererDecision

/// The outcome of `willRender(token:context:)`.
public enum RendererDecision: Sendable {
    /// This renderer fully handled the token; pipeline stops here.
    case handled

    /// This renderer does not handle the token; pass it to the next renderer.
    case passthrough

    /// Replace the token with the associated value and continue the pipeline
    /// with the replacement (allows token transformation mid-pipeline).
    case replace(MarkdownToken)
}

// MARK: - StreamDownRenderer protocol

/// A pluggable rendering unit that participates in the StreamDown rendering pipeline.
///
/// Renderers are composed in priority order (ascending `renderPriority`).
/// For each token the pipeline asks each renderer in turn:
///
/// 1. `canHandle(token:)` — fast filter; skip if `false`.
/// 2. `willRender(token:context:)` — decide how to proceed.
/// 3. `transformToken(_:)` — optionally mutate the token before it reaches the UI.
///
/// Conforming types must be classes (`AnyObject`) because they may hold
/// platform-specific resources (caches, attributed-string builders, etc.).
/// They must also be `Sendable` so they can be passed across actor boundaries.
public protocol StreamDownRenderer: AnyObject, Sendable {

    // MARK: Identity

    /// A stable string that uniquely identifies this renderer within a pipeline.
    /// Reverse-DNS style recommended, e.g. `"ai.streamdown.syntax-highlight"`.
    var rendererIdentifier: String { get }

    /// Lower values run earlier in the pipeline.
    /// The default implementation returns `0`.
    var renderPriority: Int { get }

    // MARK: Lifecycle

    /// Called once before the renderer processes any tokens.
    /// Use this to perform one-time setup (load resources, warm caches, etc.).
    func rendererWillActivate(context: RendererContext)

    // MARK: Pipeline

    /// Returns `true` if this renderer is interested in `token`.
    ///
    /// This is a fast path — implementations should avoid heavy work here.
    func canHandle(token: MarkdownToken) -> Bool

    /// Called for every token that passed `canHandle`.
    ///
    /// - Returns: A `RendererDecision` indicating what should happen next.
    func willRender(token: MarkdownToken, context: RenderContext) -> RendererDecision

    /// Gives the renderer an opportunity to mutate the token before the UI layer
    /// receives it.  Called only when `willRender` returned `.handled`.
    ///
    /// The default implementation returns the token unchanged.
    func transformToken(_ token: MarkdownToken) -> MarkdownToken
}

// MARK: - Default implementations

public extension StreamDownRenderer {

    var renderPriority: Int { 0 }

    func rendererWillActivate(context: RendererContext) {
        // No-op by default — override to perform setup.
    }

    func canHandle(token: MarkdownToken) -> Bool {
        // By default a renderer declares interest in all tokens.
        // Override to narrow the scope.
        return true
    }

    func willRender(token: MarkdownToken, context: RenderContext) -> RendererDecision {
        // Default: pass the token through to the next renderer.
        return .passthrough
    }

    func transformToken(_ token: MarkdownToken) -> MarkdownToken {
        // Default: no transformation.
        return token
    }
}

// MARK: - RendererPipeline

/// A lightweight, ordered collection of renderers that processes tokens sequentially.
///
/// This type is part of the core model layer; it does not perform any drawing.
public struct RendererPipeline: Sendable {

    private let renderers: [any StreamDownRenderer]

    /// Initialises the pipeline, sorting renderers by ascending `renderPriority`.
    public init(renderers: [any StreamDownRenderer]) {
        self.renderers = renderers.sorted { $0.renderPriority < $1.renderPriority }
    }

    /// Activates all renderers with the given context.
    public func activate(context: RendererContext) {
        renderers.forEach { $0.rendererWillActivate(context: context) }
    }

    /// Runs `token` through the pipeline and returns the (possibly transformed) token
    /// together with the decision made by the handling renderer.
    ///
    /// If no renderer handles the token, `.passthrough` is returned with the original token.
    @discardableResult
    public func process(
        token: MarkdownToken,
        context: RenderContext
    ) -> (token: MarkdownToken, decision: RendererDecision) {
        var current = token
        for renderer in renderers {
            guard renderer.canHandle(token: current) else { continue }
            let decision = renderer.willRender(token: current, context: context)
            switch decision {
            case .handled:
                let transformed = renderer.transformToken(current)
                return (transformed, .handled)
            case .passthrough:
                continue
            case .replace(let replacement):
                current = replacement
                // Continue pipeline with the replacement token.
            }
        }
        return (current, .passthrough)
    }
}
