// BlockViews.swift
// StreamDownUI — SwiftUI views for each block-level MarkdownToken.

import SwiftUI
import StreamDownCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Color helpers

extension ColorDescription {
    var swiftUIColor: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Inline text builder

/// Builds an `AttributedString` from a sequence of `InlineToken`s using the given theme.
func attributedString(
    from tokens: [InlineToken],
    theme: Theme,
    linkColor: Color,
    onLinkTap: ((URL) -> Void)?
) -> AttributedString {
    var result = AttributedString()
    for token in tokens {
        result.append(attributedStringSegment(token, theme: theme, linkColor: linkColor, onLinkTap: onLinkTap))
    }
    return result
}

private func attributedStringSegment(
    _ token: InlineToken,
    theme: Theme,
    linkColor: Color,
    onLinkTap: ((URL) -> Void)?
) -> AttributedString {
    switch token {
    case .text(let s):
        return AttributedString(s)

    case .softBreak:
        return AttributedString(" ")

    case .hardBreak:
        return AttributedString("\n")

    case .codeSpan(let t):
        var attr = AttributedString(t.code)
        attr.font = .system(size: CGFloat(theme.typography.codeSize), design: .monospaced)
        let fg = theme.colors.codeForeground
        attr.foregroundColor = Color(red: fg.r, green: fg.g, blue: fg.b, opacity: fg.a)
        return attr

    case .emphasis(let t):
        var attr = attributedString(from: t.children, theme: theme, linkColor: linkColor, onLinkTap: onLinkTap)
        applyItalic(to: &attr, size: theme.typography.bodySize)
        return attr

    case .strong(let t):
        var attr = attributedString(from: t.children, theme: theme, linkColor: linkColor, onLinkTap: onLinkTap)
        applyBold(to: &attr, size: theme.typography.bodySize)
        return attr

    case .strikethrough(let t):
        var attr = attributedString(from: t.children, theme: theme, linkColor: linkColor, onLinkTap: onLinkTap)
        attr.strikethroughStyle = .single
        return attr

    case .link(let t):
        var attr = attributedString(from: t.children, theme: theme, linkColor: linkColor, onLinkTap: onLinkTap)
        attr.foregroundColor = linkColor
        attr.underlineStyle = .single
        if let url = URL(string: t.href) {
            attr.link = url
        }
        return attr

    case .autolink(let t):
        var attr = AttributedString(t.url)
        attr.foregroundColor = linkColor
        attr.underlineStyle = .single
        let urlString = t.isEmail ? "mailto:\(t.url)" : t.url
        if let url = URL(string: urlString) {
            attr.link = url
        }
        return attr

    case .image(let t):
        // Images render as alt text inline; full image loading is out-of-scope for inline context.
        var attr = AttributedString("[\(t.alt)]")
        attr.foregroundColor = linkColor
        return attr

    case .taskCheckbox(let t):
        return AttributedString(t.isChecked ? "☑ " : "☐ ")

    case .html:
        // Inline HTML stripped from attributed representation.
        return AttributedString()
    }
}

private func applyBold(to attr: inout AttributedString, size: Double) {
    attr.font = .system(size: CGFloat(size), weight: .bold)
}

private func applyItalic(to attr: inout AttributedString, size: Double) {
    attr.font = .system(size: CGFloat(size)).italic()
}

// MARK: - SDInlineTextView

/// Renders a sequence of inline tokens as a single SwiftUI `Text`.
struct SDInlineTextView: View {
    let tokens: [InlineToken]
    let onLinkTap: ((URL) -> Void)?

    @Environment(\.streamDownTheme) private var theme

    var body: some View {
        let linkColor = theme.colors.link.swiftUIColor
        let attr = attributedString(from: tokens, theme: theme, linkColor: linkColor, onLinkTap: onLinkTap)
        Text(attr)
            .environment(\.openURL, OpenURLAction { url in
                if let handler = onLinkTap {
                    handler(url)
                    return .handled
                }
                return .systemAction
            })
    }
}

// MARK: - SDHeadingView

struct SDHeadingView: View {
    let token: HeadingToken

    @Environment(\.streamDownTheme) private var theme

    var body: some View {
        let size = theme.typography.headingSize(level: token.level)
        let linkColor = theme.colors.link.swiftUIColor
        let attr = attributedString(from: token.children, theme: theme, linkColor: linkColor, onLinkTap: nil)

        Text(attr)
            .font(.system(size: CGFloat(size), weight: headingWeight(level: token.level)))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(accessibilityHeadingLevel(token.level))
    }

    private func headingWeight(level: Int) -> Font.Weight {
        switch level {
        case 1: return .bold
        case 2: return .semibold
        default: return .medium
        }
    }

    private func accessibilityHeadingLevel(_ level: Int) -> AccessibilityHeadingLevel {
        switch level {
        case 1: return .h1
        case 2: return .h2
        case 3: return .h3
        case 4: return .h4
        case 5: return .h5
        default: return .h6
        }
    }
}

// MARK: - SDParagraphView

struct SDParagraphView: View {
    let token: ParagraphToken
    let onLinkTap: ((URL) -> Void)?

    @Environment(\.streamDownTheme) private var theme

    var body: some View {
        SDInlineTextView(tokens: token.children, onLinkTap: onLinkTap)
            .font(.system(size: CGFloat(theme.typography.bodySize)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - SDCodeBlockView

struct SDCodeBlockView: View {
    let token: CodeBlockToken
    let isPartial: Bool
    let configuration: StreamDownConfiguration

    @Environment(\.streamDownTheme) private var theme
    @State private var didCopy = false

    var body: some View {
        let codeTheme = theme.codeBlock
        let colors = theme.colors
        let spacing = theme.spacing
        let codeActions = configuration.codeActions

        VStack(alignment: .leading, spacing: 0) {
            // Toolbar row
            HStack(spacing: 8) {
                if codeActions.showLanguageLabel, let lang = token.language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(
                            red: codeTheme.toolbarForeground.r,
                            green: codeTheme.toolbarForeground.g,
                            blue: codeTheme.toolbarForeground.b
                        ))
                }

                Spacer()

                if codeActions.showDownload && !isPartial {
                    let filename = token.meta ?? (token.language.map { "\($0).txt" } ?? "code.txt")
                    ShareLink(
                        item: token.code,
                        subject: Text(filename),
                        message: Text("")
                    ) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(
                                red: codeTheme.toolbarForeground.r,
                                green: codeTheme.toolbarForeground.g,
                                blue: codeTheme.toolbarForeground.b
                            ))
                    }
                    .accessibilityLabel("Download code")
                }

                if codeActions.showCopy {
                    Button {
                        copyCode()
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(
                                red: codeTheme.toolbarForeground.r,
                                green: codeTheme.toolbarForeground.g,
                                blue: codeTheme.toolbarForeground.b
                            ))
                    }
                    .accessibilityLabel(didCopy ? "Copied" : "Copy code")
                }
            }
            .padding(.horizontal, CGFloat(spacing.codePadding))
            .padding(.vertical, 8)
            .background(Color(
                red: codeTheme.toolbarBackground.r,
                green: codeTheme.toolbarBackground.g,
                blue: codeTheme.toolbarBackground.b
            ))

            Divider()
                .background(Color(red: colors.border.r, green: colors.border.g, blue: colors.border.b))

            // Code body with optional line numbers
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    let showLineNumbers = codeActions.showLineNumbers && !isPartial
                    if showLineNumbers {
                        lineNumberColumn(codeTheme: codeTheme, spacing: spacing)
                    }

                    Text(token.code.isEmpty ? " " : token.code)
                        .font(.system(size: CGFloat(theme.typography.codeSize), design: .monospaced))
                        .foregroundStyle(Color(
                            red: colors.codeForeground.r,
                            green: colors.codeForeground.g,
                            blue: colors.codeForeground.b
                        ))
                        .textSelection(.enabled)
                        .padding(CGFloat(spacing.codePadding))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .background(Color(
                red: colors.codeBackground.r,
                green: colors.codeBackground.g,
                blue: colors.codeBackground.b
            ))
        }
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(codeTheme.cornerRadius)))
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(codeTheme.cornerRadius))
                .stroke(
                    Color(red: colors.border.r, green: colors.border.g, blue: colors.border.b),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private func lineNumberColumn(codeTheme: CodeBlockTheme, spacing: SpacingTheme) -> some View {
        let lines = token.code.components(separatedBy: "\n")
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(lines.indices, id: \.self) { idx in
                Text("\(idx + 1)")
                    .font(.system(size: CGFloat(theme.typography.codeSize), design: .monospaced))
                    .foregroundStyle(Color(
                        red: codeTheme.lineNumberForeground.r,
                        green: codeTheme.lineNumberForeground.g,
                        blue: codeTheme.lineNumberForeground.b
                    ))
                    .lineLimit(1)
            }
        }
        .padding(CGFloat(spacing.codePadding))
        .padding(.trailing, 4)

        Divider()
            .background(Color(
                red: theme.colors.border.r,
                green: theme.colors.border.g,
                blue: theme.colors.border.b
            ))
    }

    private func copyCode() {
#if canImport(UIKit)
        UIPasteboard.general.string = token.code
#elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(token.code, forType: .string)
#endif
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            didCopy = false
        }
    }
}

// MARK: - SDBlockquoteView

struct SDBlockquoteView: View {
    let token: BlockquoteToken
    let isStreaming: Bool
    let onLinkTap: ((URL) -> Void)?

    @Environment(\.streamDownTheme) private var theme
    @Environment(\.streamDownConfiguration) private var configuration

    var body: some View {
        let colors = theme.colors
        let spacing = theme.spacing
        let borderColor = Color(
            red: colors.blockquoteBorder.r,
            green: colors.blockquoteBorder.g,
            blue: colors.blockquoteBorder.b
        )
        let bgColor = Color(
            red: colors.blockquoteBackground.r,
            green: colors.blockquoteBackground.g,
            blue: colors.blockquoteBackground.b
        )

        HStack(spacing: 0) {
            Rectangle()
                .fill(borderColor)
                .frame(width: CGFloat(spacing.blockquoteBorderWidth))

            VStack(alignment: .leading, spacing: CGFloat(spacing.blockSpacing)) {
                ForEach(token.children.indices, id: \.self) { idx in
                    blockView(for: token.children[idx])
                }
            }
            .padding(CGFloat(spacing.blockquotePadding))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bgColor)
        .clipShape(
            RoundedRectangle(cornerRadius: CGFloat(theme.blockquote.cornerRadius))
        )
    }

    @ViewBuilder
    private func blockView(for token: MarkdownToken) -> some View {
        SDBlockDispatchView(
            token: token,
            isStreaming: isStreaming,
            onLinkTap: onLinkTap
        )
    }
}

// MARK: - SDListView

struct SDListView: View {
    let token: ListToken
    let isStreaming: Bool
    let onLinkTap: ((URL) -> Void)?
    var nestingLevel: Int = 0

    @Environment(\.streamDownTheme) private var theme

    var body: some View {
        let spacing = theme.spacing
        VStack(alignment: .leading, spacing: CGFloat(spacing.listItemSpacing)) {
            ForEach(token.items.indices, id: \.self) { idx in
                listItemView(token.items[idx], index: idx)
            }
        }
    }

    @ViewBuilder
    private func listItemView(_ item: ListItemToken, index: Int) -> some View {
        let spacing = theme.spacing

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Bullet / number / checkbox
            markerView(for: item, index: index)

            // Item content
            VStack(alignment: .leading, spacing: CGFloat(spacing.listItemSpacing)) {
                ForEach(item.children.indices, id: \.self) { cidx in
                    SDBlockDispatchView(
                        token: item.children[cidx],
                        isStreaming: isStreaming,
                        onLinkTap: onLinkTap
                    )
                }
            }
        }
        .padding(.leading, nestingLevel > 0 ? CGFloat(spacing.listIndentation) : 0)
    }

    @ViewBuilder
    private func markerView(for item: ListItemToken, index: Int) -> some View {
        let bodySize = CGFloat(theme.typography.bodySize)

        switch token.kind {
        case .ordered(let start):
            Text("\(start + index).")
                .font(.system(size: bodySize))
                .foregroundStyle(Color(
                    red: theme.colors.secondaryForeground.r,
                    green: theme.colors.secondaryForeground.g,
                    blue: theme.colors.secondaryForeground.b
                ))
                .frame(minWidth: 24, alignment: .trailing)
                .monospacedDigit()

        case .unordered:
            bulletGlyph(level: nestingLevel)
                .font(.system(size: bodySize))
                .foregroundStyle(Color(
                    red: theme.colors.secondaryForeground.r,
                    green: theme.colors.secondaryForeground.g,
                    blue: theme.colors.secondaryForeground.b
                ))
                .frame(width: 16)

        case .task:
            if let checkbox = item.checkbox {
                Image(systemName: checkbox.isChecked ? "checkmark.square" : "square")
                    .font(.system(size: bodySize))
                    .foregroundStyle(
                        checkbox.isChecked
                            ? theme.colors.accent.swiftUIColor
                            : theme.colors.secondaryForeground.swiftUIColor
                    )
                    .accessibilityLabel(checkbox.isChecked ? "Completed" : "Incomplete")
            } else {
                Image(systemName: "square")
                    .font(.system(size: bodySize))
                    .frame(width: 16)
            }
        }
    }

    private func bulletGlyph(level: Int) -> Text {
        switch level % 3 {
        case 0: return Text("•")
        case 1: return Text("◦")
        default: return Text("▪")
        }
    }
}

// MARK: - SDTableView

struct SDTableView: View {
    let token: TableToken

    @Environment(\.streamDownTheme) private var theme

    var body: some View {
        let spacing = theme.spacing
        let colors = theme.colors
        let headerBg = Color(
            red: colors.tableHeaderBackground.r,
            green: colors.tableHeaderBackground.g,
            blue: colors.tableHeaderBackground.b
        )
        let altBg = Color(
            red: colors.tableAlternateRowBackground.r,
            green: colors.tableAlternateRowBackground.g,
            blue: colors.tableAlternateRowBackground.b
        )
        let borderColor = Color(
            red: colors.border.r,
            green: colors.border.g,
            blue: colors.border.b
        )

        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    ForEach(token.headers.cells.indices, id: \.self) { cidx in
                        let cell = token.headers.cells[cidx]
                        let alignment = tableAlignment(cell.alignment)
                        SDInlineTextView(tokens: cell.children, onLinkTap: nil)
                            .font(.system(size: CGFloat(theme.typography.bodySize), weight: .bold))
                            .frame(maxWidth: .infinity, alignment: alignment)
                            .padding(.vertical, CGFloat(spacing.tableCellVerticalPadding))
                            .padding(.horizontal, CGFloat(spacing.tableCellHorizontalPadding))
                            .background(headerBg)
                            .border(borderColor, width: 0.5)
                    }
                }

                // Data rows
                ForEach(token.rows.indices, id: \.self) { ridx in
                    GridRow {
                        ForEach(token.rows[ridx].cells.indices, id: \.self) { cidx in
                            let cell = token.rows[ridx].cells[cidx]
                            let alignment = tableAlignment(cell.alignment)
                            SDInlineTextView(tokens: cell.children, onLinkTap: nil)
                                .font(.system(size: CGFloat(theme.typography.bodySize)))
                                .frame(maxWidth: .infinity, alignment: alignment)
                                .padding(.vertical, CGFloat(spacing.tableCellVerticalPadding))
                                .padding(.horizontal, CGFloat(spacing.tableCellHorizontalPadding))
                                .background(ridx % 2 == 1 ? altBg : Color.clear)
                                .border(borderColor, width: 0.5)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func tableAlignment(_ alignment: ColumnAlignment) -> Alignment {
        switch alignment {
        case .left:   return .leading
        case .right:  return .trailing
        case .center: return .center
        case .none:   return .leading
        }
    }
}

// MARK: - SDThematicBreakView

struct SDThematicBreakView: View {
    @Environment(\.streamDownTheme) private var theme

    var body: some View {
        let borderColor = Color(
            red: theme.colors.border.r,
            green: theme.colors.border.g,
            blue: theme.colors.border.b
        )
        Divider()
            .background(borderColor)
            .padding(.vertical, 4)
    }
}

// MARK: - SDPartialView

/// Renders a `PartialToken` showing its tentative resolved children at reduced opacity.
struct SDPartialView: View {
    let token: PartialToken
    let onLinkTap: ((URL) -> Void)?

    @Environment(\.streamDownTheme) private var theme
    @Environment(\.streamDownConfiguration) private var configuration

    var body: some View {
        if !token.resolvedChildren.isEmpty {
            VStack(alignment: .leading, spacing: CGFloat(theme.spacing.blockSpacing)) {
                ForEach(token.resolvedChildren.indices, id: \.self) { idx in
                    SDBlockDispatchView(
                        token: token.resolvedChildren[idx],
                        isStreaming: true,
                        onLinkTap: onLinkTap
                    )
                }
            }
            .opacity(0.7)
        } else {
            // Fall back to raw text for unknown partial kinds
            let foreground = Color(
                red: theme.colors.foreground.r,
                green: theme.colors.foreground.g,
                blue: theme.colors.foreground.b
            )
            Text(token.rawText)
                .font(.system(size: CGFloat(theme.typography.bodySize)))
                .foregroundStyle(foreground)
                .opacity(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - SDBlockDispatchView

/// Routes a `MarkdownToken` to the appropriate specialized block view.
/// Used internally for nested rendering (blockquotes, list items).
struct SDBlockDispatchView: View {
    let token: MarkdownToken
    let isStreaming: Bool
    let onLinkTap: ((URL) -> Void)?

    @Environment(\.streamDownTheme) private var theme
    @Environment(\.streamDownConfiguration) private var configuration

    var body: some View {
        switch token {
        case .heading(let t):
            SDHeadingView(token: t)

        case .paragraph(let t):
            SDParagraphView(token: t, onLinkTap: onLinkTap)

        case .codeBlock(let t):
            SDCodeBlockView(token: t, isPartial: false, configuration: configuration)

        case .blockquote(let t):
            SDBlockquoteView(token: t, isStreaming: isStreaming, onLinkTap: onLinkTap)

        case .list(let t):
            SDListView(token: t, isStreaming: isStreaming, onLinkTap: onLinkTap)

        case .table(let t):
            SDTableView(token: t)

        case .thematicBreak:
            SDThematicBreakView()

        case .htmlBlock(let html):
            // HTML blocks are rendered as monospaced raw text.
            Text(html)
                .font(.system(size: CGFloat(theme.typography.codeSize), design: .monospaced))
                .foregroundStyle(Color(
                    red: theme.colors.secondaryForeground.r,
                    green: theme.colors.secondaryForeground.g,
                    blue: theme.colors.secondaryForeground.b
                ))
                .fixedSize(horizontal: false, vertical: true)

        case .inlineToken(let inline):
            SDInlineTextView(tokens: [inline], onLinkTap: onLinkTap)
                .font(.system(size: CGFloat(theme.typography.bodySize)))

        case .partial(let t):
            SDPartialView(token: t, onLinkTap: onLinkTap)

        case .cursor:
            EmptyView()
        }
    }
}
