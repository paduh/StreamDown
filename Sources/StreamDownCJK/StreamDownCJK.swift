// StreamDownCJK.swift
// StreamDownCJK — CJK text normalization for inline text tokens.
//
// This renderer does NOT produce UI views — it transforms `.inlineToken(.text(String))`
// tokens by normalizing CJK punctuation and inserting thin spaces at CJK/Latin boundaries.

import StreamDownCore

// MARK: - Unicode range helpers

private extension Unicode.Scalar {

    /// CJK Unified Ideographs (U+4E00–U+9FFF) — core Han characters.
    var isCJKUnifiedIdeograph: Bool {
        (0x4E00...0x9FFF).contains(value)
    }

    /// CJK Unified Ideographs Extension A (U+3400–U+4DBF).
    var isCJKExtensionA: Bool {
        (0x3400...0x4DBF).contains(value)
    }

    /// CJK Unified Ideographs Extension B (U+20000–U+2A6DF).
    var isCJKExtensionB: Bool {
        (0x20000...0x2A6DF).contains(value)
    }

    /// CJK Compatibility Ideographs (U+F900–U+FAFF).
    var isCJKCompatibility: Bool {
        (0xF900...0xFAFF).contains(value)
    }

    /// Japanese Hiragana (U+3040–U+309F).
    var isHiragana: Bool {
        (0x3040...0x309F).contains(value)
    }

    /// Japanese Katakana (U+30A0–U+30FF).
    var isKatakana: Bool {
        (0x30A0...0x30FF).contains(value)
    }

    /// Korean Hangul Syllables (U+AC00–U+D7A3).
    var isHangulSyllable: Bool {
        (0xAC00...0xD7A3).contains(value)
    }

    /// Korean Hangul Jamo (U+1100–U+11FF).
    var isHangulJamo: Bool {
        (0x1100...0x11FF).contains(value)
    }

    /// Ideographic punctuation block (U+3000–U+303F).
    var isIdeographicPunctuation: Bool {
        (0x3000...0x303F).contains(value)
    }

    /// Halfwidth/fullwidth forms (U+FF00–U+FFEF).
    var isFullwidthForm: Bool {
        (0xFF00...0xFFEF).contains(value)
    }

    /// Returns `true` if this scalar belongs to any CJK script.
    var isCJK: Bool {
        isCJKUnifiedIdeograph
            || isCJKExtensionA
            || isCJKExtensionB
            || isCJKCompatibility
            || isHiragana
            || isKatakana
            || isHangulSyllable
            || isHangulJamo
            || isIdeographicPunctuation
            || isFullwidthForm
    }

    /// Returns `true` for Basic Latin letters, digits, and selected punctuation
    /// that are commonly mixed with CJK text.
    var isBasicLatin: Bool {
        (0x0020...0x007E).contains(value)
    }
}

// MARK: - Punctuation mapping

/// Maps ideographic / fullwidth punctuation to their preferred normalized form.
///
/// The table follows common Chinese typography conventions:
/// - Fullwidth commas → ASCII comma + ideographic space separator (handled contextually).
/// - Ideographic period → fullwidth period retained (standard in Chinese).
/// - Fullwidth colon, semicolon → normalized narrower variants.
private let punctuationMap: [Unicode.Scalar: String] = [
    // Ideographic comma → full-width comma (keep, standard Chinese)
    Unicode.Scalar(0x3001)!: "\u{FF0C}",  // 、→ ，

    // Ideographic period → fullwidth period (already standard)
    Unicode.Scalar(0x3002)!: "\u{3002}",  // 。→ 。 (no change, already correct)

    // Fullwidth exclamation → standard (normalize to narrow in mixed context)
    Unicode.Scalar(0xFF01)!: "!",

    // Fullwidth question mark → standard
    Unicode.Scalar(0xFF1F)!: "?",

    // Fullwidth left parenthesis → standard
    Unicode.Scalar(0xFF08)!: "(",

    // Fullwidth right parenthesis → standard
    Unicode.Scalar(0xFF09)!: ")",

    // Fullwidth colon → standard colon
    Unicode.Scalar(0xFF1A)!: ":",

    // Fullwidth semicolon → standard semicolon
    Unicode.Scalar(0xFF1B)!: ";",

    // Ideographic space → regular space (U+3000 → U+0020)
    Unicode.Scalar(0x3000)!: " ",
]

// MARK: - CJKNormalizer

/// Performs CJK-aware text normalization.
///
/// Transformations applied (in order):
///   1. Map ideographic punctuation to preferred normalized forms.
///   2. Insert a Unicode thin space (U+202F NARROW NO-BREAK SPACE) at every
///      boundary between a CJK character and a Basic Latin character (excluding
///      spaces, which are already separators).
public struct CJKNormalizer {

    public init() {}

    /// Normalize the given string, returning the transformed result.
    public func normalize(_ input: String) -> String {
        // Phase 1: punctuation mapping.
        let afterPunctuation = mapPunctuation(input)

        // Phase 2: boundary spacing.
        return insertBoundarySpaces(afterPunctuation)
    }

    // MARK: - Phase 1: punctuation mapping

    private func mapPunctuation(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.unicodeScalars.count)

        for scalar in input.unicodeScalars {
            if let replacement = punctuationMap[scalar] {
                result.append(contentsOf: replacement)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }

    // MARK: - Phase 2: boundary thin-space insertion

    /// Thin space character inserted at CJK ↔ Latin boundaries.
    ///
    /// We use U+202F NARROW NO-BREAK SPACE rather than a regular space so
    /// that the boundary marker does not cause line-break opportunities at
    /// unexpected positions and remains visually subtle.
    private static let thinSpace: Unicode.Scalar = Unicode.Scalar(0x202F)! // NARROW NO-BREAK SPACE

    private func insertBoundarySpaces(_ input: String) -> String {
        let scalars = Array(input.unicodeScalars)
        guard scalars.count > 1 else { return input }

        var result = String.UnicodeScalarView()
        result.reserveCapacity(scalars.count + scalars.count / 4)

        for idx in scalars.indices {
            let current = scalars[idx]
            result.append(current)

            // Look ahead to the next scalar to detect a boundary transition.
            let nextIdx = idx + 1
            guard nextIdx < scalars.count else { break }
            let next = scalars[nextIdx]

            // Skip if either side is already a space character.
            if current.value == 0x0020 || current.value == 0x00A0
                || next.value == 0x0020 || next.value == 0x00A0 {
                continue
            }

            let currentIsCJK   = current.isCJK
            let nextIsCJK      = next.isCJK
            let currentIsLatin = current.isBasicLatin && !current.isCJK
            let nextIsLatin    = next.isBasicLatin && !next.isCJK

            // Insert thin space at: [CJK][Latin] or [Latin][CJK] boundaries.
            let needsSpace = (currentIsCJK && nextIsLatin) || (currentIsLatin && nextIsCJK)
            if needsSpace {
                result.append(Self.thinSpace)
            }
        }

        return String(result)
    }
}

// MARK: - StreamDownCJK

/// A `StreamDownRenderer` that normalizes CJK text in inline `.text(String)` tokens.
///
/// This renderer **only** transforms tokens — it does not produce any views.
/// It replaces ideographic punctuation with preferred normalized forms and
/// inserts thin spaces at CJK ↔ Latin character boundaries to improve
/// mixed-script typesetting.
///
/// Usage:
/// ```swift
/// StreamDownView(stream: myStream)
///     .renderer(StreamDownCJK())
/// ```
public final class StreamDownCJK: StreamDownRenderer, @unchecked Sendable {

    // MARK: - Identity

    public let rendererIdentifier = "com.streamdown.cjk"
    public var renderPriority: Int = 5

    // MARK: - Internal state

    private let normalizer = CJKNormalizer()

    // MARK: - Init

    public init() {}

    // MARK: - StreamDownRenderer

    public func rendererWillActivate(context: RendererContext) {}

    /// We handle `.inlineToken(.text)` and `.paragraph` (which contain inline children).
    public func canHandle(token: MarkdownToken) -> Bool {
        switch token {
        case .inlineToken(.text): return true
        case .paragraph:          return true
        case .partial:            return true
        default:                  return false
        }
    }

    /// We only transform; the pipeline should continue to the next renderer.
    public func willRender(token: MarkdownToken, context: RenderContext) -> RendererDecision {
        .passthrough
    }

    /// Recursively normalize all `.text` inline tokens.
    public func transformToken(_ token: MarkdownToken) -> MarkdownToken {
        switch token {
        case .inlineToken(.text(let s)):
            return .inlineToken(.text(normalizer.normalize(s)))

        case .paragraph(let p):
            let normalized = p.children.map { transformInline($0) }
            return .paragraph(ParagraphToken(children: normalized))

        case .partial(let p):
            let normalizedChildren = p.resolvedChildren.map { transformToken($0) }
            return .partial(PartialToken(
                kind: p.kind,
                rawText: normalizer.normalize(p.rawText),
                resolvedChildren: normalizedChildren
            ))

        default:
            return token
        }
    }

    // MARK: - Inline token recursion

    private func transformInline(_ inline: InlineToken) -> InlineToken {
        switch inline {
        case .text(let s):
            return .text(normalizer.normalize(s))

        case .emphasis(let e):
            return .emphasis(EmphasisToken(children: e.children.map { transformInline($0) }))

        case .strong(let s):
            return .strong(StrongToken(children: s.children.map { transformInline($0) }))

        case .strikethrough(let s):
            return .strikethrough(StrikethroughToken(children: s.children.map { transformInline($0) }))

        case .link(let l):
            return .link(LinkToken(
                href: l.href,
                title: l.title,
                children: l.children.map { transformInline($0) }
            ))

        // Leaf nodes — no transformation needed.
        case .softBreak, .hardBreak, .codeSpan, .image, .autolink, .taskCheckbox, .html:
            return inline
        }
    }
}
