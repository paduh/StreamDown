// StreamDownUIView.swift
// StreamDownUIKit — UIKit rendering layer for StreamDown

import UIKit
import StreamDownCore

// MARK: - TextDeltaAccumulator

/// Accumulates streaming text deltas and drives the `IncrementalMarkdownParser`.
///
/// Each call to `append(_:)` feeds the delta to the parser and returns a fresh
/// `RenderModel` snapshot that can be applied directly to the UI.
private final class TextDeltaAccumulator {

    private let parser = IncrementalMarkdownParser()
    private var model  = RenderModel.empty
    private var fullText = ""

    /// Feed a new delta of raw text.
    /// - Returns: An updated `RenderModel` containing the new finalized tokens
    ///   plus the current partial block (if any).
    func append(_ delta: String) -> RenderModel {
        fullText += delta
        let finalized = parser.consume(delta: delta)
        let partial   = parser.currentPartialToken
        model = model.appending(
            finalized:     finalized,
            partial:       partial,
            cursorVisible: true
        )
        return model
    }

    /// Flush remaining buffered content and mark the stream as complete.
    /// - Returns: The finalized `RenderModel` with `isStreaming = false`.
    func finalize() -> (model: RenderModel, fullText: String) {
        let remaining = parser.finalize()
        model = model.appending(
            finalized:     remaining,
            partial:       nil,
            cursorVisible: false
        ).finalized()
        return (model, fullText)
    }

    /// Reset parser and model to their initial state.
    func reset() {
        parser.reset()
        model    = .empty
        fullText = ""
    }

    /// The accumulated raw text (all deltas concatenated).
    var accumulatedText: String { fullText }
}

// MARK: - StreamDownUIView

/// A `UIView` subclass that renders streaming Markdown content using UIKit primitives.
///
/// - The view is **not** a `UIHostingController` wrapper; it uses `UITextView` and
///   `UIStackView` directly for the best layout integration.
/// - Place `StreamDownUIView` inside a `UIScrollView` and set `parentScrollView`
///   to enable auto-scroll-to-bottom during streaming.
/// - Use `beginStreaming(_:)` for `AsyncStream`-based streaming, or call
///   `apply(delta:)` / `finalizeStreaming()` manually for push-based integration.
@MainActor
public final class StreamDownUIView: UIView {

    // MARK: - Public API

    /// The active visual theme. Triggers a full re-render on change.
    public var theme: Theme {
        didSet { applyTheme() }
    }

    /// Renderer configuration (cursor style, link safety, etc.).
    public var configuration: StreamDownConfiguration

    /// Optional pluggable renderer pipeline. Renderers are applied in priority order
    /// before the default block-view factory.
    public var renderers: [any StreamDownRenderer] = []

    /// Delegate for height, link, copy, and finish events.
    public weak var delegate: StreamDownUIViewDelegate?

    /// When `true` (the default) the view instructs `parentScrollView` to scroll
    /// to the bottom as new content arrives — unless the user has scrolled up.
    public var autoScrollsToBottom: Bool = true

    /// The scroll view that owns this view's content. Set this to receive
    /// automatic scroll-to-bottom behaviour during streaming.
    public weak var parentScrollView: UIScrollView? {
        didSet { observeParentScroll() }
    }

    // MARK: - Private subviews

    private let stackView = UIStackView()

    // MARK: - Private state

    private var accumulator        = TextDeltaAccumulator()
    private var currentVersion     = -1
    private var renderedBlockCount = 0
    private var partialBlockView:  UIView?
    private var cursorView:        SDUKCursorView?
    private var streamTask:        Task<Void, Never>?
    private var scrollObservation: NSKeyValueObservation?
    private var userHasScrolledUp  = false

    // MARK: - Init

    public init(
        theme: Theme = .default,
        configuration: StreamDownConfiguration = .default
    ) {
        self.theme         = theme
        self.configuration = configuration
        super.init(frame: .zero)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.theme         = .default
        self.configuration = .default
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false

        // Stack view
        stackView.axis                                  = .vertical
        stackView.spacing                               = CGFloat(theme.spacing.blockSpacing)
        stackView.alignment                             = .fill
        stackView.distribution                          = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Propagate current width to all block views so they can measure correctly.
        let w = bounds.width
        guard w > 0 else { return }
        for sub in stackView.arrangedSubviews {
            applyPreferredWidth(w, to: sub)
        }
    }

    public override var intrinsicContentSize: CGSize {
        let fitting = stackView.systemLayoutSizeFitting(
            CGSize(width: bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width,
                   height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: fitting.height)
    }

    // MARK: - Theme

    private func applyTheme() {
        stackView.spacing = CGFloat(theme.spacing.blockSpacing)
        // A full re-render is the simplest correct strategy for a theme change.
        let text = accumulator.accumulatedText
        guard !text.isEmpty else { return }
        reset()
        render(markdown: text)
    }

    // MARK: - Public streaming API

    /// Begin consuming an `AsyncStream<String>`, applying each delta as it arrives
    /// and finalizing when the stream ends.
    ///
    /// Cancels any in-flight stream task before starting a new one.
    public func beginStreaming(_ stream: AsyncStream<String>) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await delta in stream {
                if Task.isCancelled { break }
                await MainActor.run { self.apply(delta: delta) }
            }
            if !Task.isCancelled {
                await MainActor.run { self.finalizeStreaming() }
            }
        }
    }

    /// Append a raw text delta to the accumulator and update the rendered view.
    public func apply(delta: String) {
        let model = accumulator.append(delta)
        applyRenderModel(model)
    }

    /// Flush any remaining buffered content and mark rendering as complete.
    public func finalizeStreaming() {
        let (model, fullText) = accumulator.finalize()
        applyRenderModel(model)
        // Remove cursor
        cursorView?.removeFromSuperview()
        cursorView = nil
        delegate?.streamDownView(self, didFinishStreaming: fullText)
    }

    /// Reset all state and remove all rendered views.
    public func reset() {
        streamTask?.cancel()
        streamTask = nil
        accumulator.reset()
        currentVersion     = -1
        renderedBlockCount = 0
        partialBlockView   = nil
        cursorView         = nil
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        invalidateIntrinsicContentSize()
    }

    /// Render a complete Markdown string synchronously (non-streaming).
    public func render(markdown: String) {
        reset()
        apply(delta: markdown)
        finalizeStreaming()
    }

    // MARK: - Render model application

    private func applyRenderModel(_ model: RenderModel) {
        guard model.version > currentVersion else { return }
        currentVersion = model.version

        let finalizedTokens = model.finalizedTokens

        // 1. Append newly finalized block views.
        if finalizedTokens.count > renderedBlockCount {
            let newTokens = finalizedTokens[renderedBlockCount...]
            for token in newTokens {
                let blockView = makeBlockView(for: token)
                applyPreferredWidth(bounds.width, to: blockView)
                // Animate new blocks in if configured
                applyAppearAnimation(to: blockView)
                stackView.addArrangedSubview(blockView)
            }
            renderedBlockCount = finalizedTokens.count
        }

        // 2. Replace the partial view at the bottom of the stack.
        partialBlockView?.removeFromSuperview()
        partialBlockView = nil

        if let partial = model.partialToken {
            let partialView = makePartialBlockView(for: partial)
            applyPreferredWidth(bounds.width, to: partialView)
            stackView.addArrangedSubview(partialView)
            partialBlockView = partialView
        }

        // 3. Attach cursor to trailing edge of the last text view if streaming.
        updateCursorPosition()

        // 4. Notify layout system.
        invalidateIntrinsicContentSize()

        // 5. Notify delegate.
        let height = intrinsicContentSize.height
        if height > 0 {
            delegate?.streamDownView(self, didUpdateContentHeight: height)
        }

        // 6. Auto-scroll.
        scrollToBottomIfNeeded()
    }

    // MARK: - Cursor management

    private func updateCursorPosition() {
        // Hide cursor for `.none` style or when nothing has been streamed yet.
        if case .none = configuration.cursor {
            cursorView?.removeFromSuperview()
            cursorView = nil
            return
        }
        guard !accumulator.accumulatedText.isEmpty else { return }

        // Lazily create the cursor view.
        let cursor: SDUKCursorView
        if let existing = cursorView {
            cursor = existing
        } else {
            cursor = SDUKCursorView()
            cursor.configure(style: configuration.cursor, theme: theme)
            cursorView = cursor
        }

        // Append the cursor view to the last block in the stack — it lives as a
        // simple subview (no Auto Layout constraints) so there is no constraint
        // churn on each update.  Position it via `frame` in a layout pass.
        let anchorView = partialBlockView ?? stackView.arrangedSubviews.last
        guard let anchorView else { return }

        if cursor.superview !== anchorView {
            cursor.removeFromSuperview()
            anchorView.addSubview(cursor)
        }

        // Position the cursor at the trailing edge of the text.
        let cursorSize = cursor.intrinsicContentSize
        if let textView = findDeepestTextView(in: anchorView) {
            let xOffset = endOfTextXOffset(in: textView)
            let yOffset = max(0, anchorView.bounds.height - cursorSize.height)
            cursor.frame = CGRect(
                x: xOffset,
                y: yOffset,
                width: cursorSize.width,
                height: cursorSize.height
            )
        }
    }

    /// Breadth-first search for the first `UITextView` inside a view hierarchy.
    private func findDeepestTextView(in view: UIView) -> UITextView? {
        if let tv = view as? UITextView { return tv }
        var queue: [UIView] = view.subviews
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let tv = next as? UITextView { return tv }
            queue.append(contentsOf: next.subviews)
        }
        return nil
    }

    /// Return the x-coordinate of the end of the last line of text, relative to
    /// the text view's own coordinate system.
    private func endOfTextXOffset(in textView: UITextView) -> CGFloat {
        guard let text = textView.text, !text.isEmpty else { return 0 }
        let layoutManager = textView.layoutManager
        let containerOrigin = textView.textContainerInset
        let glyphRange = layoutManager.glyphRange(for: textView.textContainer)
        var lastLineUsedRect = CGRect.zero
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, used, _, _, _ in
            lastLineUsedRect = used
        }
        return containerOrigin.left + lastLineUsedRect.maxX
    }

    // MARK: - Animation

    private func applyAppearAnimation(to view: UIView) {
        switch configuration.tokenAnimation {
        case .none:
            break
        case .fadeIn(let duration):
            view.alpha = 0
            UIView.animate(withDuration: duration) { view.alpha = 1 }
        case .slideUp(let distance, let duration):
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: CGFloat(distance))
            UIView.animate(withDuration: duration,
                           delay: 0,
                           options: [.curveEaseOut]) {
                view.alpha = 1
                view.transform = .identity
            }
        case .typewriter:
            // Typewriter animation is a token-level effect; at the block level
            // we use a simple fade-in as an approximation.
            view.alpha = 0
            UIView.animate(withDuration: 0.1) { view.alpha = 1 }
        }
    }

    // MARK: - Block view factory

    /// Create a fully rendered `UIView` for a finalized `MarkdownToken`.
    func makeBlockView(for token: MarkdownToken) -> UIView {
        switch token {

        case .heading(let h):
            return SDUKHeadingView(token: h, theme: theme,
                                    traitCollection: traitCollection)

        case .paragraph(let p):
            let v = SDUKParagraphView(tokens: p.children, theme: theme,
                                       traitCollection: traitCollection)
            v.textView.delegate = self
            return v

        case .codeBlock(let cb):
            return SDUKCodeBlockView(
                token: cb, theme: theme, traitCollection: traitCollection,
                isPartial: false,
                onCopy: { [weak self] code, language in
                    guard let self else { return }
                    self.delegate?.streamDownView(self, didCopyCode: code, language: language)
                }
            )

        case .blockquote(let bq):
            return SDUKBlockquoteView(token: bq, theme: theme,
                                       traitCollection: traitCollection)

        case .list(let l):
            return SDUKListView(token: l, theme: theme, traitCollection: traitCollection)

        case .table(let t):
            return SDUKTableView(token: t, theme: theme, traitCollection: traitCollection)

        case .thematicBreak:
            return SDUKThematicBreakView(theme: theme, traitCollection: traitCollection)

        case .htmlBlock(let raw):
            // Render HTML blocks as plain text paragraphs (WKWebView out of scope).
            let stripped = raw.replacingOccurrences(
                of: "<[^>]+>", with: "", options: .regularExpression)
            let p = ParagraphToken(children: [.text(stripped)])
            return SDUKParagraphView(tokens: p.children, theme: theme,
                                      traitCollection: traitCollection)

        case .inlineToken(let inline):
            return SDUKParagraphView(tokens: [inline], theme: theme,
                                      traitCollection: traitCollection)

        case .partial, .cursor:
            // Should not reach here via the finalized path; return empty placeholder.
            let placeholder = UIView()
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            return placeholder
        }
    }

    /// Create a `SDUKPartialView` wrapping the appropriate block view for a partial token.
    private func makePartialBlockView(for token: MarkdownToken) -> UIView {
        guard case .partial(let partialToken) = token else {
            return makeBlockView(for: token)
        }

        // Use the first resolved child token if available; otherwise fall back
        // to a paragraph rendering of the raw text.
        let innerToken: MarkdownToken
        if let first = partialToken.resolvedChildren.first {
            innerToken = first
        } else {
            innerToken = .paragraph(ParagraphToken(
                children: [.text(partialToken.rawText)]
            ))
        }

        let inner = makeBlockView(for: innerToken)

        // For code blocks in partial state, set the isPartial flag.
        if let codeView = inner as? SDUKCodeBlockView {
            codeView.isPartial = true
        }

        return SDUKPartialView(wrapping: inner)
    }

    // MARK: - Scroll coordination

    private func observeParentScroll() {
        scrollObservation = parentScrollView?.observe(
            \.contentOffset,
             options: [.new]
        ) { [weak self] sv, _ in
            let distanceFromBottom = sv.contentSize.height
                - sv.contentOffset.y
                - sv.bounds.height
            self?.userHasScrolledUp = distanceFromBottom > 50
        }
    }

    private func scrollToBottomIfNeeded() {
        guard autoScrollsToBottom,
              !userHasScrolledUp,
              let sv = parentScrollView else { return }
        let y = max(
            0,
            sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom
        )
        sv.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }
}

// MARK: - UITextViewDelegate (link handling)

extension StreamDownUIView: UITextViewDelegate {

    public func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        // Ask the link safety policy
        let decision = configuration.linkSafety.decision(for: URL)
        switch decision {
        case .block:
            return false
        case .confirm:
            // Delegate decides; default to not opening automatically
            let shouldOpen = delegate?.streamDownView(self, willOpenLink: URL) ?? true
            if shouldOpen {
                delegate?.streamDownView(self, didTapLink: URL)
            }
            return shouldOpen
        case .open:
            let shouldOpen = delegate?.streamDownView(self, willOpenLink: URL) ?? true
            if shouldOpen {
                delegate?.streamDownView(self, didTapLink: URL)
            }
            return shouldOpen
        }
    }
}

// Note: applyPreferredWidth(_:to:) is defined in UIKitBlockViews.swift as an
// internal free function and is therefore visible throughout this module.
