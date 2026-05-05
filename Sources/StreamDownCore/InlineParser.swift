// InlineParser.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

// MARK: - Private intermediate types

/// Characterises a delimiter run (*, **, _, ~~, etc.).
private enum DelimKind: Equatable {
    case asterisk, underscore, tilde

    var char: Character {
        switch self {
        case .asterisk:   return "*"
        case .underscore: return "_"
        case .tilde:      return "~"
        }
    }
}

/// A slot in the pre-resolution buffer.
private enum ISlot {
    case resolved(InlineToken)
    case delimOpen(kind: DelimKind, count: Int)
    case delimClose(kind: DelimKind, count: Int)
    case delimBoth(kind: DelimKind, count: Int)
}

/// An open delimiter awaiting a matching closer.
private struct OpenerEntry {
    let slotIndex: Int
    let kind: DelimKind
    var count: Int
}

// MARK: - InlineParser

/// Single-pass inline Markdown parser using a CommonMark-style delimiter stack.
///
/// Internal — not part of the public API.
struct InlineParser {

    // MARK: - Public entry points

    /// Parse inline tokens from fully-received text (stream closed, no partial spans).
    static func parseFinalized(_ text: String) -> [InlineToken] {
        parse(text, allowPartial: false)
    }

    /// Parse inline tokens, emitting partial/open spans at the end when `allowPartial` is true.
    ///
    /// Partial behaviour per construct:
    /// - Unclosed `` ` `` → `.codeSpan` with whatever text was scanned
    /// - Unclosed `**` / `*` / `__` / `_` → `.strong` / `.emphasis` wrapping subsequent tokens
    /// - Unclosed `~~` → `.strikethrough` wrapping subsequent tokens
    /// - Incomplete `[text](htt` → `.text` literal (links only finalise on `)`)
    static func parse(_ text: String, allowPartial: Bool = true) -> [InlineToken] {
        var p = InlineParser(source: Array(text), allowPartial: allowPartial)
        return p.run()
    }

    // MARK: - Mutable scanner state

    private let source: [Character]
    private let allowPartial: Bool
    private var pos: Int = 0
    /// Intermediate buffer — resolved and delimiter slots interleaved.
    private var slots: [ISlot] = []

    private init(source: [Character], allowPartial: Bool) {
        self.source = source
        self.allowPartial = allowPartial
    }

    // MARK: - Top-level scanner

    private mutating func run() -> [InlineToken] {
        while pos < source.count {
            switch source[pos] {
            case "`":  scanCodeSpan()
            case "*":  scanDelimRun(.asterisk)
            case "_":  scanDelimRun(.underscore)
            case "~":  scanTildes()
            case "[":  scanLinkOrImage(isImage: false)
            case "!":
                if peek(1) == "[" { pos += 1; scanLinkOrImage(isImage: true) }
                else { appendLiteral("!"); pos += 1 }
            case "<":  scanAngle()
            case "\n": scanNewline()
            case "\\":  scanBackslash()
            default:   appendLiteral(String(source[pos])); pos += 1
            }
        }
        return resolveDelimiterStack()
    }

    // MARK: - Code spans

    private mutating func scanCodeSpan() {
        let fenceStart = pos
        var fenceLen = 0
        while pos < source.count, source[pos] == "`" { fenceLen += 1; pos += 1 }

        var p = pos
        var found = false
        while p < source.count {
            if source[p] == "`" {
                let closeStart = p
                var closeLen = 0
                while p < source.count, source[p] == "`" { closeLen += 1; p += 1 }
                if closeLen == fenceLen {
                    var content = String(source[pos..<closeStart])
                    content = content.replacingOccurrences(of: "\n", with: " ")
                    if content.count >= 2, content.first == " ", content.last == " " {
                        let stripped = String(content.dropFirst().dropLast())
                        if !stripped.allSatisfy({ $0 == " " }) { content = stripped }
                    }
                    slots.append(.resolved(.codeSpan(CodeSpanToken(code: content))))
                    pos = p
                    found = true
                    break
                }
            } else {
                p += 1
            }
        }

        if !found {
            if allowPartial {
                let tail = pos < source.count ? String(source[pos...]) : ""
                slots.append(.resolved(.codeSpan(CodeSpanToken(code: tail))))
                pos = source.count
            } else {
                appendLiteral(String(source[fenceStart..<pos]))
            }
        }
    }

    // MARK: - Emphasis / strong delimiter runs

    private mutating func scanDelimRun(_ kind: DelimKind) {
        let start = pos
        let ch = kind.char
        while pos < source.count, source[pos] == ch { pos += 1 }
        let count = pos - start

        let leftFlank  = isLeftFlanking(start: start, end: pos)
        let rightFlank = isRightFlanking(start: start, end: pos)

        let canOpen: Bool
        let canClose: Bool
        if kind == .asterisk {
            canOpen  = leftFlank
            canClose = rightFlank
        } else {
            canOpen  = leftFlank  && (!rightFlank || precedingIsPunct(start))
            canClose = rightFlank && (!leftFlank  || followingIsPunct(pos))
        }

        switch (canOpen, canClose) {
        case (true,  true):  slots.append(.delimBoth(kind: kind, count: count))
        case (true,  false): slots.append(.delimOpen(kind: kind, count: count))
        case (false, true):  slots.append(.delimClose(kind: kind, count: count))
        case (false, false): appendLiteral(String(repeating: ch, count: count))
        }
    }

    // MARK: - Strikethrough ~~

    private mutating func scanTildes() {
        let start = pos
        while pos < source.count, source[pos] == "~" { pos += 1 }
        let count = pos - start
        if count == 2 {
            slots.append(.delimBoth(kind: .tilde, count: 2))
        } else {
            appendLiteral(String(repeating: "~", count: count))
        }
    }

    // MARK: - Links [text](href) and images ![alt](src)

    private mutating func scanLinkOrImage(isImage: Bool) {
        // pos is at `[`
        pos += 1
        guard let (labelText, afterClose) = scanBracketContent(from: pos) else {
            appendLiteral(isImage ? "![" : "[")
            return
        }
        pos = afterClose

        guard pos < source.count, source[pos] == "(" else {
            appendLiteral((isImage ? "![" : "[") + labelText + "]")
            return
        }
        pos += 1  // consume `(`
        skipSpaces()

        let (dest, title, closed) = scanLinkBody()
        guard closed else {
            var raw = (isImage ? "![" : "[") + labelText + "](" + dest
            if let t = title { raw += " \"\(t)\"" }
            appendLiteral(raw)
            return
        }

        if isImage {
            slots.append(.resolved(.image(ImageToken(src: dest, alt: labelText, title: title))))
        } else {
            let children = InlineParser.parse(labelText, allowPartial: false)
            slots.append(.resolved(.link(LinkToken(href: dest, title: title, children: children))))
        }
    }

    /// Scans `content]` starting at `from`, returns (content, posAfterBracket) or nil.
    private func scanBracketContent(from start: Int) -> (String, Int)? {
        var p = start
        var depth = 1
        while p < source.count, depth > 0 {
            switch source[p] {
            case "[":  depth += 1; p += 1
            case "]":  depth -= 1; p += 1
            case "\\":
                p += 1
                if p < source.count { p += 1 }
            default:   p += 1
            }
        }
        guard depth == 0 else { return nil }
        return (String(source[start..<(p - 1)]), p)
    }

    /// Scans link/image body after the opening `(`.  Returns (dest, title, didClose).
    private mutating func scanLinkBody() -> (String, String?, Bool) {
        var dest = ""
        if pos < source.count, source[pos] == "<" {
            pos += 1
            while pos < source.count, source[pos] != ">" {
                if source[pos] == "\\" { pos += 1 }
                if pos < source.count { dest.append(source[pos]); pos += 1 }
            }
            if pos < source.count { pos += 1 }
        } else {
            var depth = 0
            while pos < source.count {
                let c = source[pos]
                if c == "("      { depth += 1; dest.append(c); pos += 1 }
                else if c == ")" {
                    if depth == 0 { break }
                    depth -= 1; dest.append(c); pos += 1
                } else if c == " " || c == "\t" || c == "\n" { break }
                else if c == "\\" { pos += 1; if pos < source.count { dest.append(source[pos]); pos += 1 } }
                else { dest.append(c); pos += 1 }
            }
        }

        skipSpaces()

        var title: String? = nil
        if pos < source.count {
            let q = source[pos]
            let closeQ: Character? = q == "\"" ? "\"" : q == "'" ? "'" : q == "(" ? ")" : nil
            if let cq = closeQ {
                pos += 1
                var t = ""
                while pos < source.count, source[pos] != cq {
                    if source[pos] == "\\" { pos += 1 }
                    if pos < source.count { t.append(source[pos]); pos += 1 }
                }
                if pos < source.count { pos += 1 }
                title = t
            }
        }

        skipSpaces()
        let closed = pos < source.count && source[pos] == ")"
        if closed { pos += 1 }
        return (dest, title, closed)
    }

    // MARK: - Angle brackets: autolinks and raw HTML

    private mutating func scanAngle() {
        let start = pos
        pos += 1
        if let tok = tryAutolink() {
            slots.append(.resolved(.autolink(tok)))
            return
        }
        if let end = tryHTMLTag(from: start) {
            slots.append(.resolved(.html(String(source[start..<end]))))
            pos = end
            return
        }
        appendLiteral("<")
    }

    private mutating func tryAutolink() -> AutolinkToken? {
        var p = pos
        var chars: [Character] = []
        while p < source.count, source[p] != ">" {
            let c = source[p]
            if c == " " || c == "\n" || c == "<" { return nil }
            chars.append(c)
            p += 1
        }
        guard p < source.count else { return nil }
        let s = String(chars)

        let atCount = chars.filter { $0 == "@" }.count
        if atCount == 1, let atIdx = s.firstIndex(of: "@") {
            let local  = String(s[s.startIndex..<atIdx])
            let domain = String(s[s.index(after: atIdx)...])
            if !local.isEmpty, domain.contains(".") {
                pos = p + 1
                return AutolinkToken(url: s, isEmail: true)
            }
        }
        if s.contains("://") || s.hasPrefix("mailto:") {
            pos = p + 1
            return AutolinkToken(url: s, isEmail: false)
        }
        return nil
    }

    private func tryHTMLTag(from start: Int) -> Int? {
        var p = start + 1
        while p < source.count {
            if source[p] == "\n" { return nil }
            if source[p] == ">" { return p + 1 }
            p += 1
        }
        return nil
    }

    // MARK: - Newlines

    private mutating func scanNewline() {
        if trailingSpaceCount() >= 2 {
            trimTrailingSpaces(n: 2)
            slots.append(.resolved(.hardBreak))
        } else {
            slots.append(.resolved(.softBreak))
        }
        pos += 1
    }

    private func trailingSpaceCount() -> Int {
        var count = 0
        var i = slots.count - 1
        while i >= 0 {
            if case .resolved(.text(let t)) = slots[i] {
                for c in t.reversed() {
                    if c == " " { count += 1 } else { return count }
                }
            } else { break }
            i -= 1
        }
        return count
    }

    private mutating func trimTrailingSpaces(n: Int) {
        var remaining = n
        while remaining > 0, !slots.isEmpty {
            guard case .resolved(.text(let t)) = slots.last else { break }
            var arr = Array(t)
            while remaining > 0, arr.last == " " { arr.removeLast(); remaining -= 1 }
            if arr.isEmpty { slots.removeLast() }
            else { slots[slots.count - 1] = .resolved(.text(String(arr))) }
        }
    }

    // MARK: - Backslash escapes

    private mutating func scanBackslash() {
        pos += 1
        guard pos < source.count else { appendLiteral("\\"); return }
        let c = source[pos]
        if c == "\n" {
            slots.append(.resolved(.hardBreak)); pos += 1
        } else if isASCIIPunct(c) {
            appendLiteral(String(c)); pos += 1
        } else {
            appendLiteral("\\")
        }
    }

    // MARK: - Slot / literal helpers

    private mutating func appendLiteral(_ s: String) {
        if case .resolved(.text(let existing)) = slots.last {
            slots[slots.count - 1] = .resolved(.text(existing + s))
        } else {
            slots.append(.resolved(.text(s)))
        }
    }

    private mutating func skipSpaces() {
        while pos < source.count, source[pos] == " " || source[pos] == "\t" { pos += 1 }
    }

    private func peek(_ offset: Int) -> Character? {
        let i = pos + offset
        return i < source.count ? source[i] : nil
    }

    // MARK: - Flanking helpers (CommonMark §6.2)

    private func isLeftFlanking(start: Int, end: Int) -> Bool {
        guard end < source.count else { return false }
        let after = source[end]
        if after.isWhitespace { return false }
        let before: Character? = start > 0 ? source[start - 1] : nil
        if isPunct(after) { return before == nil || before!.isWhitespace || isPunct(before!) }
        return true
    }

    private func isRightFlanking(start: Int, end: Int) -> Bool {
        guard start > 0 else { return false }
        let before = source[start - 1]
        if before.isWhitespace { return false }
        let after: Character? = end < source.count ? source[end] : nil
        if isPunct(before) { return after == nil || after!.isWhitespace || isPunct(after!) }
        return true
    }

    private func precedingIsPunct(_ pos: Int) -> Bool {
        pos > 0 && isPunct(source[pos - 1])
    }

    private func followingIsPunct(_ pos: Int) -> Bool {
        pos < source.count && isPunct(source[pos])
    }

    private func isPunct(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (v >= 0x21 && v <= 0x2F) ||
               (v >= 0x3A && v <= 0x40) ||
               (v >= 0x5B && v <= 0x60) ||
               (v >= 0x7B && v <= 0x7E)
    }

    private func isASCIIPunct(_ c: Character) -> Bool { isPunct(c) }

    // MARK: - Delimiter resolution (CommonMark §6.3)

    /// Resolves all slots into a flat `[InlineToken]` sequence using a bucket-per-slot model.
    ///
    /// Two parallel arrays are maintained:
    ///   `buckets[i]` — the resolved tokens that this slot emits.
    ///   `openerStack` — open delimiter entries not yet matched.
    ///
    /// When a closer is processed, it scans the opener stack from the top and, if a
    /// matching opener is found, collects all bucket contents between them as the span's
    /// children, wraps them, and writes the result into the opener's bucket.
    private func resolveDelimiterStack() -> [InlineToken] {
        var buckets: [[InlineToken]] = Array(repeating: [], count: slots.count)
        var openerStack: [OpenerEntry] = []

        for (i, slot) in slots.enumerated() {
            switch slot {
            case .resolved(let t):
                buckets[i] = [t]

            case .delimOpen(let kind, let count):
                openerStack.append(OpenerEntry(slotIndex: i, kind: kind, count: count))

            case .delimClose(let kind, let count):
                matchClose(kind: kind, count: count, closeSlot: i,
                           openerStack: &openerStack, buckets: &buckets)

            case .delimBoth(let kind, let count):
                let hasOpener = openerStack.contains { $0.kind == kind }
                if hasOpener {
                    matchClose(kind: kind, count: count, closeSlot: i,
                               openerStack: &openerStack, buckets: &buckets)
                    if buckets[i].isEmpty {
                        // Matching failed (e.g. rule-of-three); treat as opener
                        openerStack.append(OpenerEntry(slotIndex: i, kind: kind, count: count))
                    }
                } else {
                    openerStack.append(OpenerEntry(slotIndex: i, kind: kind, count: count))
                }
            }
        }

        // Flush unmatched openers
        for entry in openerStack where buckets[entry.slotIndex].isEmpty {
            let si = entry.slotIndex
            let literalStr = String(repeating: entry.kind.char, count: entry.count)
            if allowPartial && entry.count > 0 {
                var inner: [InlineToken] = []
                for j in (si + 1)..<buckets.count {
                    inner.append(contentsOf: buckets[j])
                    buckets[j] = []
                }
                if !inner.isEmpty {
                    buckets[si] = [wrapSpan(kind: entry.kind, count: entry.count, children: inner)]
                } else {
                    buckets[si] = [.text(literalStr)]
                }
            } else {
                buckets[si] = [.text(literalStr)]
            }
        }

        return buckets.flatMap { $0 }
    }

    /// Attempts to close a delimiter run of `kind`/`count` at `closeSlot`.
    ///
    /// Searches the opener stack from the top for a compatible opener.  When found,
    /// gathers inner tokens, wraps them, and updates both `buckets` and `openerStack`.
    private func matchClose(
        kind: DelimKind,
        count: Int,
        closeSlot: Int,
        openerStack: inout [OpenerEntry],
        buckets: inout [[InlineToken]]
    ) {
        // Find innermost compatible opener
        var openerIdx: Int? = nil
        for si in stride(from: openerStack.count - 1, through: 0, by: -1) {
            let e = openerStack[si]
            guard e.kind == kind else { continue }
            if kind == .tilde {
                if e.count == 2 && count == 2 { openerIdx = si; break }
                continue
            }
            // CommonMark rule-of-three: if sum divisible by 3, both cannot be multiples of 3
            let sum = e.count + count
            if sum % 3 == 0 && e.count % 3 == 0 { continue }
            openerIdx = si
            break
        }

        guard let oi = openerIdx else {
            buckets[closeSlot] = [.text(String(repeating: kind.char, count: count))]
            return
        }

        let opener = openerStack[oi]
        let use: Int
        if kind == .tilde { use = 2 }
        else { use = min(opener.count, count) >= 2 ? 2 : 1 }

        // Collect inner tokens
        var inner: [InlineToken] = []
        for j in (opener.slotIndex + 1)..<closeSlot {
            inner.append(contentsOf: buckets[j])
            buckets[j] = []
        }

        let wrapped = wrapSpan(kind: kind, count: use, children: inner)
        let openerLeftover = opener.count - use
        let closerLeftover = count - use

        buckets[opener.slotIndex] = openerLeftover > 0
            ? [.text(String(repeating: kind.char, count: openerLeftover)), wrapped]
            : [wrapped]

        buckets[closeSlot] = closerLeftover > 0
            ? [.text(String(repeating: kind.char, count: closerLeftover))]
            : []

        if openerLeftover > 0 {
            openerStack[oi].count = openerLeftover
        } else {
            openerStack.remove(at: oi)
        }
    }

    private func wrapSpan(kind: DelimKind, count: Int, children: [InlineToken]) -> InlineToken {
        switch kind {
        case .tilde:
            return .strikethrough(StrikethroughToken(children: children))
        case .asterisk, .underscore:
            return count >= 2
                ? .strong(StrongToken(children: children))
                : .emphasis(EmphasisToken(children: children))
        }
    }
}
