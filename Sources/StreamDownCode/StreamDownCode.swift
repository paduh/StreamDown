// StreamDownCode.swift
// StreamDownCode — Syntax-highlighting renderer for fenced code blocks.

import SwiftUI
import UIKit
import StreamDownCore
import StreamDownUI
import StreamDownUIKit

// MARK: - Syntax token kinds

private enum SyntaxKind {
    case keyword
    case string
    case comment
    case number
    case plain
}

// MARK: - Syntax token span

private struct SyntaxSpan {
    let text: String
    let kind: SyntaxKind
}

// MARK: - Language detection

private enum CodeLanguage {
    case swift
    case python
    case other

    init(language: String?) {
        switch language?.lowercased() {
        case "swift":          self = .swift
        case "python", "py":   self = .python
        default:               self = .other
        }
    }
}

// MARK: - CJK Normalizer (simplified for re-use from StreamDownCJK)

// MARK: - SyntaxHighlighter

/// Tokenizes source code into colored spans using simple pattern matching.
///
/// The highlighter works line-by-line and applies, in order:
///   1. Full-line comment detection (`//`, `#`)
///   2. String literal scanning (single-quoted and double-quoted)
///   3. Number literal scanning
///   4. Keyword matching against word boundaries
///   5. Everything else falls through as `.plain`
struct SyntaxHighlighter {

    // MARK: - Language keyword tables

    private static let swiftKeywords: Set<String> = [
        "func", "class", "struct", "enum", "let", "var", "if", "else",
        "guard", "return", "import", "public", "private", "internal",
        "override", "final", "protocol", "extension", "self", "Self",
        "init", "deinit", "where", "for", "in", "while", "switch",
        "case", "break", "continue", "throw", "throws", "try", "catch",
        "async", "await", "actor", "nonisolated", "static", "mutating",
        "lazy", "weak", "unowned", "typealias", "associatedtype",
        "subscript", "get", "set", "didSet", "willSet", "open",
        "fileprivate", "true", "false", "nil", "as", "is", "any", "some",
    ]

    private static let pythonKeywords: Set<String> = [
        "def", "class", "import", "from", "if", "else", "elif",
        "return", "for", "while", "in", "not", "and", "or",
        "True", "False", "None", "pass", "break", "continue",
        "try", "except", "finally", "raise", "with", "as",
        "yield", "lambda", "del", "global", "nonlocal", "assert",
        "async", "await",
    ]

    // MARK: - Entry point

    /// Tokenize the given source code for the specified language.
    static func tokenize(code: String, language: CodeLanguage) -> [[SyntaxSpan]] {
        let keywords: Set<String>
        let lineCommentPrefix: String?

        switch language {
        case .swift:
            keywords = swiftKeywords
            lineCommentPrefix = "//"
        case .python:
            keywords = pythonKeywords
            lineCommentPrefix = "#"
        case .other:
            // No highlighting — everything is plain.
            return code.components(separatedBy: "\n").map { line in
                [SyntaxSpan(text: line, kind: .plain)]
            }
        }

        return code.components(separatedBy: "\n").map { line in
            tokenizeLine(line, keywords: keywords, lineCommentPrefix: lineCommentPrefix)
        }
    }

    // MARK: - Line tokenizer

    private static func tokenizeLine(
        _ line: String,
        keywords: Set<String>,
        lineCommentPrefix: String?
    ) -> [SyntaxSpan] {
        var spans: [SyntaxSpan] = []
        let chars = Array(line)
        var i = 0

        // Full-line comment shortcut
        if let prefix = lineCommentPrefix {
            let trimStart = line.trimmingCharacters(in: .init(charactersIn: " \t"))
            if trimStart.hasPrefix(prefix) {
                return [SyntaxSpan(text: line, kind: .comment)]
            }
        }

        var pending = ""

        // Flush the accumulated plain/keyword text into spans.
        func flushPending() {
            guard !pending.isEmpty else { return }
            // Split into word tokens and classify each.
            var words: [SyntaxSpan] = []
            var wordStart = pending.startIndex
            var inWord = false

            func flushWord(_ range: Range<String.Index>) {
                let word = String(pending[range])
                if keywords.contains(word) {
                    words.append(SyntaxSpan(text: word, kind: .keyword))
                } else {
                    words.append(SyntaxSpan(text: word, kind: .plain))
                }
            }

            for idx in pending.indices {
                let c = pending[idx]
                let isWordChar = c.isLetter || c.isNumber || c == "_"
                if isWordChar && !inWord {
                    wordStart = idx
                    inWord = true
                } else if !isWordChar && inWord {
                    flushWord(wordStart..<idx)
                    words.append(SyntaxSpan(text: String(c), kind: .plain))
                    inWord = false
                } else if !isWordChar {
                    words.append(SyntaxSpan(text: String(c), kind: .plain))
                }
            }
            if inWord {
                flushWord(wordStart..<pending.endIndex)
            }

            spans.append(contentsOf: words)
            pending = ""
        }

        while i < chars.count {
            let c = chars[i]

            // Inline comment: // or #
            if let prefix = lineCommentPrefix {
                let prefixChars = Array(prefix)
                if i + prefixChars.count <= chars.count {
                    let slice = Array(chars[i..<(i + prefixChars.count)])
                    if slice == prefixChars {
                        flushPending()
                        let rest = String(chars[i...])
                        spans.append(SyntaxSpan(text: rest, kind: .comment))
                        return spans
                    }
                }
            }

            // String literal (single or double quoted)
            if c == "\"" || c == "'" {
                flushPending()
                let quote = c
                var str = String(c)
                i += 1
                while i < chars.count {
                    let sc = chars[i]
                    str.append(sc)
                    if sc == "\\" && i + 1 < chars.count {
                        i += 1
                        str.append(chars[i])
                    } else if sc == quote {
                        break
                    }
                    i += 1
                }
                spans.append(SyntaxSpan(text: str, kind: .string))
                i += 1
                continue
            }

            // Number literal
            if c.isNumber && (pending.isEmpty || !pending.last!.isLetter) {
                flushPending()
                var num = String(c)
                i += 1
                while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "_" {
                    num.append(chars[i])
                    i += 1
                }
                spans.append(SyntaxSpan(text: num, kind: .number))
                continue
            }

            // Accumulate plain text for keyword scanning
            pending.append(c)
            i += 1
        }

        flushPending()
        return spans
    }
}

// MARK: - Theme color helpers

private struct SyntaxColors {
    let keyword: ColorDescription
    let string: ColorDescription
    let comment: ColorDescription
    let number: ColorDescription
    let plain: ColorDescription

    static func colors(for themeName: SyntaxThemeName, baseColor: ColorDescription) -> SyntaxColors {
        switch themeName {
        case .githubDark:
            return SyntaxColors(
                keyword: ColorDescription(hex: "#79C0FF")!,   // blue
                string:  ColorDescription(hex: "#A5C261")!,   // orange-ish green (github dark strings)
                comment: ColorDescription(hex: "#8B949E")!,   // gray
                number:  ColorDescription(hex: "#79C0FF")!,   // green — using accent blue
                plain:   ColorDescription(hex: "#E6EDF3")!    // default foreground
            )
        case .githubLight:
            return SyntaxColors(
                keyword: ColorDescription(hex: "#CF222E")!,
                string:  ColorDescription(hex: "#0A3069")!,
                comment: ColorDescription(hex: "#6E7781")!,
                number:  ColorDescription(hex: "#0550AE")!,
                plain:   ColorDescription(hex: "#24292F")!
            )
        case .dracula:
            return SyntaxColors(
                keyword: ColorDescription(hex: "#FF79C6")!,
                string:  ColorDescription(hex: "#F1FA8C")!,
                comment: ColorDescription(hex: "#6272A4")!,
                number:  ColorDescription(hex: "#BD93F9")!,
                plain:   ColorDescription(hex: "#F8F8F2")!
            )
        case .monokai:
            return SyntaxColors(
                keyword: ColorDescription(hex: "#F92672")!,
                string:  ColorDescription(hex: "#E6DB74")!,
                comment: ColorDescription(hex: "#75715E")!,
                number:  ColorDescription(hex: "#AE81FF")!,
                plain:   ColorDescription(hex: "#F8F8F2")!
            )
        case .nord:
            return SyntaxColors(
                keyword: ColorDescription(hex: "#81A1C1")!,
                string:  ColorDescription(hex: "#A3BE8C")!,
                comment: ColorDescription(hex: "#4C566A")!,
                number:  ColorDescription(hex: "#B48EAD")!,
                plain:   ColorDescription(hex: "#ECEFF4")!
            )
        case .oneDark:
            return SyntaxColors(
                keyword: ColorDescription(hex: "#C678DD")!,
                string:  ColorDescription(hex: "#98C379")!,
                comment: ColorDescription(hex: "#5C6370")!,
                number:  ColorDescription(hex: "#D19A66")!,
                plain:   ColorDescription(hex: "#ABB2BF")!
            )
        case .solarizedDark:
            return SyntaxColors(
                keyword: ColorDescription(hex: "#859900")!,
                string:  ColorDescription(hex: "#2AA198")!,
                comment: ColorDescription(hex: "#586E75")!,
                number:  ColorDescription(hex: "#D33682")!,
                plain:   ColorDescription(hex: "#839496")!
            )
        case .solarizedLight:
            return SyntaxColors(
                keyword: ColorDescription(hex: "#859900")!,
                string:  ColorDescription(hex: "#2AA198")!,
                comment: ColorDescription(hex: "#93A1A1")!,
                number:  ColorDescription(hex: "#D33682")!,
                plain:   ColorDescription(hex: "#657B83")!
            )
        }
    }

    func color(for kind: SyntaxKind) -> ColorDescription {
        switch kind {
        case .keyword: return keyword
        case .string:  return string
        case .comment: return comment
        case .number:  return number
        case .plain:   return plain
        }
    }
}

// MARK: - Platform color conversion

private extension ColorDescription {
    var swiftUIColor: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

// MARK: - AttributedString builders

private func makeAttributedString(
    lines: [[SyntaxSpan]],
    colors: SyntaxColors,
    fontSize: CGFloat
) -> AttributedString {
    var result = AttributedString()
    for (lineIdx, line) in lines.enumerated() {
        for span in line {
            var part = AttributedString(span.text)
            part.foregroundColor = colors.color(for: span.kind).swiftUIColor
            part.font = .system(size: fontSize, design: .monospaced)
            result.append(part)
        }
        if lineIdx < lines.count - 1 {
            var nl = AttributedString("\n")
            nl.font = .system(size: fontSize, design: .monospaced)
            result.append(nl)
        }
    }
    return result
}

private func makeNSAttributedString(
    lines: [[SyntaxSpan]],
    colors: SyntaxColors,
    fontSize: CGFloat
) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineHeightMultiple = 1.4

    for (lineIdx, line) in lines.enumerated() {
        for span in line {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: colors.color(for: span.kind).uiColor,
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .paragraphStyle: paragraphStyle,
            ]
            result.append(NSAttributedString(string: span.text, attributes: attrs))
        }
        if lineIdx < lines.count - 1 {
            result.append(NSAttributedString(string: "\n", attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            ]))
        }
    }
    return result
}

// MARK: - StreamDownCode

/// A pluggable renderer that applies syntax highlighting to finalized fenced code blocks.
///
/// `StreamDownCode` conforms to both `SwiftUIRenderer` and `UIKitRenderer` so it can be
/// used in either environment.  While the block is still streaming (partial), it returns
/// `nil` and lets the default plain-monospace renderer handle the in-progress view.
/// Once the closing fence arrives the full source is tokenized and returned as a
/// colored `AttributedString` / `NSAttributedString`.
///
/// Usage:
/// ```swift
/// StreamDownView(stream: myStream)
///     .renderer(StreamDownCode(theme: .githubDark))
/// ```
public final class StreamDownCode: SwiftUIRenderer, UIKitRenderer, @unchecked Sendable {

    // MARK: - Identity

    public let rendererIdentifier = "com.streamdown.code"
    public var renderPriority: Int = 10

    // MARK: - Configuration

    private let syntaxTheme: SyntaxThemeName
    private var activatedContext: RendererContext?

    // MARK: - Init

    public init(theme: SyntaxThemeName = .githubDark) {
        self.syntaxTheme = theme
    }

    // MARK: - StreamDownRenderer

    public func rendererWillActivate(context: RendererContext) {
        activatedContext = context
    }

    public func canHandle(token: MarkdownToken) -> Bool {
        guard case .codeBlock = token else { return false }
        return true
    }

    public func willRender(token: MarkdownToken, context: RenderContext) -> RendererDecision {
        // Decline partial tokens — the built-in renderer handles streaming code blocks.
        if context.isPartial { return .passthrough }
        guard case .codeBlock = token else { return .passthrough }
        return .handled
    }

    public func transformToken(_ token: MarkdownToken) -> MarkdownToken {
        return token
    }

    // MARK: - SwiftUIRenderer

    @MainActor
    public func makeView(for token: MarkdownToken, context: RenderContext) -> AnyView? {
        guard !context.isPartial,
              case .codeBlock(let cb) = token else { return nil }

        let theme = context.theme
        let lang = CodeLanguage(language: cb.language)
        let lines = SyntaxHighlighter.tokenize(code: cb.code, language: lang)
        let palette = SyntaxColors.colors(
            for: syntaxTheme,
            baseColor: theme.colors.codeForeground
        )
        let fontSize = CGFloat(theme.typography.codeSize)
        let attrStr = makeAttributedString(lines: lines, colors: palette, fontSize: fontSize)
        let bgColor = theme.colors.codeBackground.swiftUIColor
        let radius = CGFloat(theme.codeBlock.cornerRadius)
        let padding = CGFloat(theme.spacing.codePadding)

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                Text(attrStr)
                    .textSelection(.enabled)
                    .padding(padding)
            }
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        )
    }

    // MARK: - UIKitRenderer

    @MainActor
    public func makeView(for token: MarkdownToken, context: RenderContext) -> UIView? {
        guard !context.isPartial,
              case .codeBlock(let cb) = token else { return nil }

        let theme = context.theme
        let lang = CodeLanguage(language: cb.language)
        let lines = SyntaxHighlighter.tokenize(code: cb.code, language: lang)
        let palette = SyntaxColors.colors(
            for: syntaxTheme,
            baseColor: theme.colors.codeForeground
        )
        let fontSize = CGFloat(theme.typography.codeSize)
        let attrStr = makeNSAttributedString(lines: lines, colors: palette, fontSize: fontSize)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = theme.colors.codeBackground.uiColor
        container.layer.cornerRadius = CGFloat(theme.codeBlock.cornerRadius)
        container.layer.masksToBounds = true

        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.showsHorizontalScrollIndicator = true
        textView.showsVerticalScrollIndicator = false
        textView.backgroundColor = .clear
        textView.attributedText = attrStr
        textView.textContainerInset = UIEdgeInsets(
            top: CGFloat(theme.spacing.codePadding),
            left: CGFloat(theme.spacing.codePadding),
            bottom: CGFloat(theme.spacing.codePadding),
            right: CGFloat(theme.spacing.codePadding)
        )

        container.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: container.topAnchor),
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        return container
    }
}
