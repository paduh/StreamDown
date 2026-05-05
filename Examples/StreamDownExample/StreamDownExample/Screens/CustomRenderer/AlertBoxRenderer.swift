// AlertBoxRenderer.swift
// Custom renderer that turns blockquotes prefixed with ⚠️ / ℹ️ / ✅
// into styled callout boxes.

import SwiftUI
import StreamDownCore
import StreamDownUI

// MARK: - AlertBoxRenderer

/// Demonstrates the `SwiftUIRenderer` protocol.
///
/// Any blockquote whose first inline token starts with one of the supported
/// emoji prefixes is intercepted and rendered as a styled alert box.
/// All other blockquotes pass through to the default renderer.
public final class AlertBoxRenderer: SwiftUIRenderer, @unchecked Sendable {

    public let rendererIdentifier = "com.example.alertbox"
    public var renderPriority: Int = 10

    public init() {}

    // MARK: - StreamDownRenderer

    public func rendererWillActivate(context: RendererContext) {}

    public func canHandle(token: MarkdownToken) -> Bool {
        alertKind(for: token) != nil
    }

    public func willRender(
        token: MarkdownToken,
        context: RenderContext
    ) -> RendererDecision {
        alertKind(for: token) != nil ? .handled : .passthrough
    }

    public func transformToken(_ token: MarkdownToken) -> MarkdownToken { token }

    // MARK: - SwiftUIRenderer

    @MainActor
    public func makeView(
        for token: MarkdownToken,
        context: RenderContext
    ) -> AnyView? {
        guard case .blockquote(let bq) = token,
              let kind = alertKind(for: token) else { return nil }
        return AnyView(AlertBoxView(kind: kind, blockquote: bq))
    }

    // MARK: - Helpers

    /// Returns the `AlertKind` for a token if it is an alert blockquote,
    /// or `nil` if it should be handled by the default renderer.
    private func alertKind(for token: MarkdownToken) -> AlertKind? {
        guard case .blockquote(let bq) = token,
              let firstChild = bq.children.first,
              case .paragraph(let para) = firstChild,
              let firstInline = para.children.first,
              case .text(let text) = firstInline
        else { return nil }

        if text.hasPrefix("⚠️") { return .warning }
        if text.hasPrefix("ℹ️") { return .info }
        if text.hasPrefix("✅") { return .success }
        return nil
    }
}

// MARK: - AlertKind

extension AlertBoxRenderer {
    enum AlertKind {
        case warning, info, success

        var systemImage: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .info:    return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .warning: return .orange
            case .info:    return .blue
            case .success: return .green
            }
        }

        /// Emoji prefix characters to strip from the leading text.
        var prefix: String {
            switch self {
            case .warning: return "⚠️"
            case .info:    return "ℹ️"
            case .success: return "✅"
            }
        }
    }
}

// MARK: - AlertBoxView

private struct AlertBoxView: View {

    let kind: AlertBoxRenderer.AlertKind
    let blockquote: BlockquoteToken

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.accentColor)
                .padding(.top, 1)

            contentText
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(kind.accentColor.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .frame(width: 3)
                .foregroundStyle(kind.accentColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Text extraction

    @ViewBuilder
    private var contentText: some View {
        if let text = extractText() {
            Text(.init(text))   // Renders basic **bold** via AttributedString markdown
        } else {
            EmptyView()
        }
    }

    /// Extracts the plain text from the first paragraph, stripping the emoji prefix.
    private func extractText() -> String? {
        guard let firstChild = blockquote.children.first,
              case .paragraph(let para) = firstChild
        else { return nil }

        var result = ""
        for inline in para.children {
            switch inline {
            case .text(let s):
                result += s
            case .strong(let s):
                let inner = s.children.compactMap {
                    if case .text(let t) = $0 { return t } else { return nil }
                }.joined()
                result += "**\(inner)**"
            case .emphasis(let e):
                let inner = e.children.compactMap {
                    if case .text(let t) = $0 { return t } else { return nil }
                }.joined()
                result += "*\(inner)*"
            case .codeSpan(let cs):
                result += "`\(cs.code)`"
            default:
                break
            }
        }

        // Strip the leading emoji prefix and any trailing variation selector or space
        for emojiPrefix in [kind.prefix + " ", kind.prefix] {
            if result.hasPrefix(emojiPrefix) {
                return String(result.dropFirst(emojiPrefix.count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
