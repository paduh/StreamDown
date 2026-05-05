// RenderModel.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

/// Immutable snapshot of everything the UI layer needs to render a single frame.
///
/// `RenderModel` is value-typed and `Sendable`; the UI can safely capture it
/// across actor boundaries.  The `version` counter allows renderers to skip
/// redundant layout passes with a cheap integer comparison.
public struct RenderModel: Sendable, Equatable {

    // MARK: Properties

    /// The ordered sequence of tokens that make up this render frame.
    ///
    /// The sequence may end with:
    /// - A `.partial(_)` token if a block is still being received.
    /// - A `.cursor` token if the cursor is currently visible.
    /// - Neither, once streaming is complete and the cursor is hidden.
    public let tokens: [MarkdownToken]

    /// `true` while new content is still being appended from an upstream source.
    public let isStreaming: Bool

    /// Monotonically increasing counter. Incremented on every `appending` call.
    /// Renderers may use this to gate expensive layout work.
    public let version: Int

    // MARK: Init

    public init(tokens: [MarkdownToken], isStreaming: Bool, version: Int) {
        self.tokens     = tokens
        self.isStreaming = isStreaming
        self.version    = version
    }

    // MARK: Empty / initial state

    public static let empty = RenderModel(tokens: [], isStreaming: false, version: 0)

    // MARK: Derived properties

    /// All tokens excluding any trailing `.partial` or `.cursor` sentinels.
    public var finalizedTokens: [MarkdownToken] {
        tokens.filter {
            if case .partial = $0 { return false }
            if case .cursor  = $0 { return false }
            return true
        }
    }

    /// The current partial token, if present.
    public var partialToken: MarkdownToken? {
        tokens.last.flatMap {
            if case .partial = $0 { return $0 }
            return nil
        } ?? {
            guard tokens.count >= 2 else { return nil }
            let candidate = tokens[tokens.count - 2]
            if case .partial = candidate { return candidate }
            return nil
        }()
    }

    // MARK: Mutation helpers

    /// Returns a new `RenderModel` that replaces the streaming tail with updated content.
    ///
    /// - Parameters:
    ///   - finalized: Fully parsed tokens to accumulate into the model. These are
    ///     appended after stripping any previous partial/cursor tail.
    ///   - partial: The current in-progress token, or `nil` if none.
    ///   - cursorVisible: Whether to append a `.cursor` sentinel this frame.
    /// - Returns: A new model with an incremented `version`.
    public func appending(
        finalized: [MarkdownToken],
        partial: MarkdownToken?,
        cursorVisible: Bool
    ) -> RenderModel {
        // 1. Strip the previous partial + cursor tail from the current token list.
        var base = stripStreamingTail(from: tokens)

        // 2. Append newly finalised tokens.
        base.append(contentsOf: finalized)

        // 3. Append the partial token if present.
        if let partial {
            base.append(partial)
        }

        // 4. Append the cursor sentinel if requested.
        if cursorVisible {
            base.append(.cursor)
        }

        return RenderModel(
            tokens:      base,
            isStreaming:  isStreaming || partial != nil || cursorVisible,
            version:     version + 1
        )
    }

    /// Returns a new model that marks streaming as finished and removes
    /// any trailing `.partial` or `.cursor` sentinels.
    public func finalized() -> RenderModel {
        let clean = stripStreamingTail(from: tokens)
        return RenderModel(tokens: clean, isStreaming: false, version: version + 1)
    }

    /// Returns a new model with `isStreaming` set to the given value,
    /// keeping all other properties unchanged (version is still incremented).
    public func withStreaming(_ streaming: Bool) -> RenderModel {
        RenderModel(tokens: tokens, isStreaming: streaming, version: version + 1)
    }

    // MARK: Private helpers

    /// Removes any trailing `.cursor` and then any trailing `.partial` token.
    private func stripStreamingTail(from list: [MarkdownToken]) -> [MarkdownToken] {
        var result = list

        // Drop trailing cursor.
        if result.last == .cursor {
            result.removeLast()
        }

        // Drop trailing partial (may have been exposed after cursor removal).
        if let last = result.last, case .partial = last {
            result.removeLast()
        }

        return result
    }
}
