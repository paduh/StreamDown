// UIKitRenderer.swift
// StreamDownUIKit — UIKit-specific renderer protocol

import UIKit
import StreamDownCore

/// A `StreamDownRenderer` that can produce a UIKit view for a given token.
///
/// When the pipeline reaches a renderer that conforms to `UIKitRenderer`,
/// `StreamDownUIView` calls `makeView(for:context:)` and inserts the returned
/// `UIView` into its vertical `UIStackView`.
///
/// Return `nil` to decline rendering and let the next renderer in the pipeline
/// handle the token.
public protocol UIKitRenderer: StreamDownRenderer {
    /// Produce a UIKit view for the given token, or return `nil` to pass through.
    ///
    /// - Parameters:
    ///   - token: The `MarkdownToken` to render.
    ///   - context: The active `RenderContext` (theme, depth, partial state).
    /// - Returns: A configured `UIView` ready to insert into the layout hierarchy, or `nil`.
    @MainActor
    func makeView(for token: MarkdownToken, context: RenderContext) -> UIView?
}
