// SwiftUIRenderer.swift
// StreamDownUI — SwiftUI-specific renderer protocol

import SwiftUI
import StreamDownCore

/// A `StreamDownRenderer` that can produce a SwiftUI view for a given token.
///
/// When the pipeline reaches a renderer that conforms to `SwiftUIRenderer`,
/// the host view asks `makeView(for:context:)` to obtain a `AnyView` that is
/// inserted directly into the block-level `LazyVStack`.
///
/// Return `nil` to decline rendering and let the next renderer in the pipeline
/// handle the token.
public protocol SwiftUIRenderer: StreamDownRenderer {
    /// Produce a SwiftUI view for the given token, or return `nil` to pass through.
    ///
    /// - Parameters:
    ///   - token: The `MarkdownToken` to render.
    ///   - context: The active `RenderContext` (theme, depth, partial state).
    /// - Returns: An `AnyView` wrapping the concrete view, or `nil`.
    @MainActor
    func makeView(for token: MarkdownToken, context: RenderContext) -> AnyView?
}
