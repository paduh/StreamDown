// IncrementalMarkdownParser.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

// MARK: - Internal helpers

/// Converts plain text to a URL-slug suitable for heading anchors.
///
///     slugify("Hello World!")  →  "hello-world"
private func slugify(_ text: String) -> String {
    var result = ""
    var lastWasDash = false
    for c in text.lowercased() {
        if c.isLetter || c.isNumber {
            result.append(c)
            lastWasDash = false
        } else {
            if !lastWasDash && !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
    }
    // Trim trailing dash
    while result.hasSuffix("-") { result.removeLast() }
    return result
}

/// Extract plain text from inline tokens (used for anchor generation).
private func inlineTokensPlainText(_ tokens: [InlineToken]) -> String {
    tokens.compactMap { token -> String? in
        switch token {
        case .text(let s):                       return s
        case .codeSpan(let cs):                  return cs.code
        case .emphasis(let e):                   return inlineTokensPlainText(e.children)
        case .strong(let s):                     return inlineTokensPlainText(s.children)
        case .strikethrough(let s):              return inlineTokensPlainText(s.children)
        case .link(let l):                       return inlineTokensPlainText(l.children)
        case .softBreak, .hardBreak:             return " "
        default:                                 return nil
        }
    }.joined()
}

/// Parse a table separator row like `| :--- | ---: | :---: | --- |`
/// Returns alignments or nil if the row is not a valid separator.
private func parseTableSeparatorRow(_ line: String) -> [ColumnAlignment]? {
    let stripped = line.trimmingCharacters(in: .init(charactersIn: " \t"))
    guard stripped.hasPrefix("|") || stripped.contains("|") else { return nil }
    let cells = splitTableRow(stripped)
    guard !cells.isEmpty else { return nil }
    var alignments: [ColumnAlignment] = []
    for cell in cells {
        let trimmed = cell.trimmingCharacters(in: .init(charactersIn: " \t"))
        let hasLeft  = trimmed.hasPrefix(":")
        let hasRight = trimmed.hasSuffix(":")
        let dashes   = trimmed.trimmingCharacters(in: .init(charactersIn: ":"))
        guard dashes.allSatisfy({ $0 == "-" }), !dashes.isEmpty else { return nil }
        switch (hasLeft, hasRight) {
        case (true,  true):  alignments.append(.center)
        case (true,  false): alignments.append(.left)
        case (false, true):  alignments.append(.right)
        case (false, false): alignments.append(.none)
        }
    }
    return alignments.isEmpty ? nil : alignments
}

/// Split a pipe-separated table row into cell strings.
/// Handles leading/trailing pipes and escaped pipes.
private func splitTableRow(_ line: String) -> [String] {
    var cells: [String] = []
    var current = ""
    let chars = Array(line)
    var i = 0
    // Skip leading pipe
    if i < chars.count, chars[i] == "|" { i += 1 }
    while i < chars.count {
        if chars[i] == "\\" && i + 1 < chars.count && chars[i + 1] == "|" {
            current.append("|"); i += 2
        } else if chars[i] == "|" {
            cells.append(current)
            current = ""
            i += 1
        } else {
            current.append(chars[i])
            i += 1
        }
    }
    // If there's content after last pipe, add it (no trailing pipe case)
    if !current.trimmingCharacters(in: .init(charactersIn: " \t")).isEmpty {
        cells.append(current)
    }
    return cells
}

/// Build a `TableRowToken` from raw pipe-separated text.
private func parseTableRow(
    _ line: String,
    alignments: [ColumnAlignment],
    isHeader: Bool
) -> TableRowToken {
    let raw = line.trimmingCharacters(in: .init(charactersIn: " \t"))
    let cellStrings = splitTableRow(raw)
    var cells: [TableCellToken] = []
    for (idx, cellStr) in cellStrings.enumerated() {
        let alignment = idx < alignments.count ? alignments[idx] : .none
        let trimmed = cellStr.trimmingCharacters(in: .init(charactersIn: " \t"))
        let children = InlineParser.parseFinalized(trimmed)
        cells.append(TableCellToken(children: children, alignment: alignment, isHeader: isHeader))
    }
    // Pad or trim to match alignment count
    while cells.count < alignments.count {
        let alignment = cells.count < alignments.count ? alignments[cells.count] : .none
        cells.append(TableCellToken(children: [], alignment: alignment, isHeader: isHeader))
    }
    if cells.count > alignments.count && !alignments.isEmpty {
        cells = Array(cells.prefix(alignments.count))
    }
    return TableRowToken(cells: cells, isHeader: isHeader)
}

/// Detect and return the ATX heading level (1–6) and the content substring,
/// or nil if the line is not an ATX heading.
private func detectATXHeading(_ line: String) -> (level: Int, content: String)? {
    let chars = Array(line)
    var i = 0
    // Up to 3 leading spaces allowed
    var spaces = 0
    while i < chars.count, chars[i] == " ", spaces < 3 { spaces += 1; i += 1 }
    guard i < chars.count, chars[i] == "#" else { return nil }
    var level = 0
    while i < chars.count, chars[i] == "#", level < 6 { level += 1; i += 1 }
    guard level >= 1 else { return nil }
    // Must be followed by space, tab, or end of line
    if i < chars.count, chars[i] != " ", chars[i] != "\t" { return nil }
    // Strip leading whitespace from content
    while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
    var content = String(chars[i...])
    // Strip optional trailing `#` sequence (must be preceded by space or be entire content)
    let contentChars = Array(content)
    var j = contentChars.count - 1
    while j >= 0, contentChars[j] == "#" { j -= 1 }
    if j < contentChars.count - 1 {
        // There are trailing hashes
        if j < 0 {
            content = ""
        } else if contentChars[j] == " " || contentChars[j] == "\t" {
            content = String(contentChars[...j]).trimmingCharacters(in: .init(charactersIn: " \t"))
        }
        // else: trailing hashes not preceded by space → keep as-is
    }
    return (level, content)
}

/// Returns the bullet marker character if line starts a bullet list item.
private func detectBulletListMarker(_ line: String) -> (marker: Character, restAfterMarker: String)? {
    let chars = Array(line)
    var i = 0
    var spaces = 0
    while i < chars.count, chars[i] == " ", spaces < 3 { spaces += 1; i += 1 }
    guard i < chars.count, chars[i] == "-" || chars[i] == "*" || chars[i] == "+" else { return nil }
    let marker = chars[i]; i += 1
    guard i < chars.count, chars[i] == " " || chars[i] == "\t" else { return nil }
    let rest = String(chars[i...]).trimmingCharacters(in: .init(charactersIn: " \t"))
    return (marker, rest)
}

/// Returns (number, rest) if line starts an ordered list item.
private func detectOrderedListMarker(_ line: String) -> (start: Int, rest: String)? {
    let chars = Array(line)
    var i = 0
    var spaces = 0
    while i < chars.count, chars[i] == " ", spaces < 3 { spaces += 1; i += 1 }
    guard i < chars.count, chars[i].isNumber else { return nil }
    var numStr = ""
    while i < chars.count, chars[i].isNumber, numStr.count <= 9 { numStr.append(chars[i]); i += 1 }
    guard i < chars.count, chars[i] == "." || chars[i] == ")" else { return nil }
    i += 1 // consume `.` or `)`
    guard i < chars.count, chars[i] == " " || chars[i] == "\t" else { return nil }
    let rest = String(chars[i...]).trimmingCharacters(in: .init(charactersIn: " \t"))
    return (Int(numStr) ?? 1, rest)
}

/// Returns the task checkbox state if the line begins a task-list item (`- [ ] ` / `- [x] `).
/// Returns (checked, restAfterCheckbox) or nil.
private func detectTaskListItem(_ line: String) -> (checked: Bool, rest: String)? {
    let lower = line.lowercased()
    if lower.hasPrefix("[ ] ") { return (false, String(line.dropFirst(4))) }
    if lower.hasPrefix("[x] ") { return (true,  String(line.dropFirst(4))) }
    return nil
}

/// Returns true if the line is a thematic break (3+ *, -, or _ separated only by spaces).
private func isThematicBreak(_ line: String) -> Bool {
    let stripped = line.trimmingCharacters(in: .init(charactersIn: " \t"))
    guard stripped.count >= 3 else { return false }
    let first = stripped.first!
    guard first == "-" || first == "*" || first == "_" else { return false }
    let chars = stripped.filter { $0 != " " && $0 != "\t" }
    return chars.count >= 3 && chars.allSatisfy { $0 == first }
}

/// Returns true if the line starts an HTML block (simplified detection).
private func isHTMLBlockStart(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .init(charactersIn: " \t"))
    return trimmed.hasPrefix("<") && !trimmed.hasPrefix("<a") && !trimmed.hasPrefix("<span")
        && (trimmed.hasPrefix("<!--") || trimmed.hasPrefix("<?") || trimmed.hasPrefix("<!") ||
            trimmed.lowercased().hasPrefix("<div") || trimmed.lowercased().hasPrefix("<p") ||
            trimmed.lowercased().hasPrefix("<blockquote") || trimmed.lowercased().hasPrefix("<pre") ||
            trimmed.lowercased().hasPrefix("<table") || trimmed.lowercased().hasPrefix("<ul") ||
            trimmed.lowercased().hasPrefix("<ol") || trimmed.lowercased().hasPrefix("<li") ||
            trimmed.lowercased().hasPrefix("<h1") || trimmed.lowercased().hasPrefix("<h2") ||
            trimmed.lowercased().hasPrefix("<h3") || trimmed.lowercased().hasPrefix("<h4") ||
            trimmed.lowercased().hasPrefix("<h5") || trimmed.lowercased().hasPrefix("<h6") ||
            trimmed.lowercased().hasPrefix("<hr") || trimmed.lowercased().hasPrefix("<br") ||
            trimmed.lowercased().hasPrefix("<script") || trimmed.lowercased().hasPrefix("<style"))
}

// MARK: - BlockParserState

private enum BlockParserState {
    case idle
    case inParagraph(buffer: String)
    case inATXHeading(level: Int, buffer: String)
    case inFencedCode(fence: String, language: String?, meta: String?, buffer: String)
    case inIndentedCode(buffer: String)
    case inBlockquote(buffer: String, nested: IncrementalMarkdownParser)
    case inOrderedList(
        startNum: Int,
        items: [ListItemToken],
        currentBuffer: String,
        currentNested: IncrementalMarkdownParser
    )
    case inBulletList(
        marker: Character,
        items: [ListItemToken],
        currentBuffer: String,
        currentNested: IncrementalMarkdownParser
    )
    case inTaskList(
        items: [ListItemToken],
        currentBuffer: String,
        currentNested: IncrementalMarkdownParser
    )
    case inTable(
        headerLine: String,
        alignments: [ColumnAlignment],
        rows: [TableRowToken],
        pendingHeaderLine: String?
    )
    case inHTMLBlock(buffer: String)
}

// MARK: - IncrementalMarkdownParser

/// A streaming, line-oriented block-level Markdown parser.
///
/// Feed text deltas via `consume(delta:)`.  Finalized tokens are returned
/// immediately; the current in-progress block is available via `currentPartialToken`.
/// Call `finalize()` when the upstream stream closes.
public final class IncrementalMarkdownParser: @unchecked Sendable {

    // MARK: - State

    private var state: BlockParserState = .idle
    /// Accumulates characters that have not yet been terminated by a newline.
    private var lineBuffer: String = ""
    /// All tokens that have been fully finalized (not yet consumed by the caller).
    private var finalized: [MarkdownToken] = []

    // MARK: - Init / Reset

    public init() {}

    /// Resets the parser to its initial state, discarding all accumulated content.
    public func reset() {
        state = .idle
        lineBuffer = ""
        finalized = []
    }

    // MARK: - Public API

    /// Feed a delta of text (any length, including partial lines).
    /// Returns all tokens that became fully finalized during this delta.
    public func consume(delta: String) -> [MarkdownToken] {
        finalized.removeAll()

        for ch in delta {
            if ch == "\n" {
                processLine(lineBuffer)
                lineBuffer = ""
            } else {
                lineBuffer.append(ch)
            }
        }

        let result = finalized
        finalized = []
        return result
    }

    /// Best-effort rendering of the currently open block.  `nil` when the parser is idle.
    public var currentPartialToken: MarkdownToken? {
        // If there are unflushed characters in lineBuffer, include them in the partial.
        switch state {
        case .idle:
            // Check lineBuffer for partial block
            if lineBuffer.isEmpty { return nil }
            // Speculative: what block type would this become?
            return speculativePartial(for: lineBuffer)

        case .inParagraph(let buf):
            let full = buf + lineBuffer
            let children = InlineParser.parse(full, allowPartial: true)
            return .partial(PartialToken(kind: .paragraph, rawText: full,
                                         resolvedChildren: [.paragraph(ParagraphToken(children: children))]))

        case .inATXHeading(let level, let buf):
            let full = buf + lineBuffer
            let children = InlineParser.parse(full, allowPartial: true)
            let anchor = slugify(inlineTokensPlainText(children))
            return .partial(PartialToken(kind: .heading, rawText: full,
                                         resolvedChildren: [.heading(HeadingToken(level: level, children: children, anchor: anchor))]))

        case .inFencedCode(_, let lang, let meta, let buf):
            let body = buf + lineBuffer
            return .partial(PartialToken(kind: .codeBlock, rawText: body,
                                         resolvedChildren: [.codeBlock(CodeBlockToken(language: lang, code: body, meta: meta))]))

        case .inIndentedCode(let buf):
            let body = buf + lineBuffer
            return .partial(PartialToken(kind: .codeBlock, rawText: body,
                                         resolvedChildren: [.codeBlock(CodeBlockToken(language: nil, code: body, meta: nil))]))

        case .inBlockquote(let buf, let nested):
            let combined = buf + (lineBuffer.isEmpty ? "" : "\n" + lineBuffer)
            _ = nested.consume(delta: lineBuffer)
            let partialChild = nested.currentPartialToken
            var children: [MarkdownToken] = nested.finalized
            if let p = partialChild { children.append(p) }
            return .partial(PartialToken(kind: .blockquote, rawText: combined,
                                         resolvedChildren: [.blockquote(BlockquoteToken(children: children))]))

        case .inOrderedList(let startNum, let items, let curBuf, let nested):
            let fullBuf = curBuf + lineBuffer
            let partialItems = buildPartialListItems(
                existing: items, currentBuffer: fullBuf, nested: nested)
            return .partial(PartialToken(kind: .list, rawText: fullBuf,
                                         resolvedChildren: [.list(ListToken(kind: .ordered(start: startNum), items: partialItems))]))

        case .inBulletList(_, let items, let curBuf, let nested):
            let fullBuf = curBuf + lineBuffer
            let partialItems = buildPartialListItems(
                existing: items, currentBuffer: fullBuf, nested: nested)
            return .partial(PartialToken(kind: .list, rawText: fullBuf,
                                         resolvedChildren: [.list(ListToken(kind: .unordered, items: partialItems))]))

        case .inTaskList(let items, let curBuf, let nested):
            let fullBuf = curBuf + lineBuffer
            let partialItems = buildPartialTaskListItems(
                existing: items, currentBuffer: fullBuf, nested: nested)
            return .partial(PartialToken(kind: .list, rawText: fullBuf,
                                         resolvedChildren: [.list(ListToken(kind: .task, items: partialItems))]))

        case .inTable(let headerLine, let alignments, let rows, _):
            if alignments.isEmpty {
                // Haven't seen separator yet
                return .partial(PartialToken(kind: .table, rawText: headerLine + "\n" + lineBuffer))
            }
            let header = parseTableRow(headerLine, alignments: alignments, isHeader: true)
            let token = TableToken(headers: header, rows: rows, alignments: alignments)
            return .partial(PartialToken(kind: .table, rawText: lineBuffer,
                                         resolvedChildren: [.table(token)]))

        case .inHTMLBlock(let buf):
            let combined = buf + lineBuffer
            return .partial(PartialToken(kind: .unknown, rawText: combined,
                                         resolvedChildren: [.htmlBlock(combined)]))
        }
    }

    /// Flush all buffered state, returning finalized tokens for all remaining content.
    public func finalize() -> [MarkdownToken] {
        // Process any remaining content in the line buffer as a final line
        if !lineBuffer.isEmpty {
            processLine(lineBuffer)
            lineBuffer = ""
        }
        // Flush the current block state
        let extra = flushCurrentState()
        let result = finalized + extra
        finalized = []
        state = .idle
        return result
    }

    // MARK: - Line dispatch

    /// Called whenever a complete line (terminated by `\n`) is available.
    private func processLine(_ line: String) {
        switch state {
        case .idle:
            dispatchNewLine(line)

        case .inParagraph(let buf):
            continueParagraph(buf: buf, newLine: line)

        case .inATXHeading:
            // ATX headings are always single-line; finalise on newline
            flushATXHeading()
            dispatchNewLine(line)

        case .inFencedCode(let fence, let lang, let meta, let buf):
            continueFencedCode(fence: fence, lang: lang, meta: meta, buf: buf, newLine: line)

        case .inIndentedCode(let buf):
            continueIndentedCode(buf: buf, newLine: line)

        case .inBlockquote(let buf, let nested):
            continueBlockquote(buf: buf, nested: nested, newLine: line)

        case .inOrderedList(let startNum, let items, let curBuf, let nested):
            continueOrderedList(startNum: startNum, items: items,
                                curBuf: curBuf, nested: nested, newLine: line)

        case .inBulletList(let marker, let items, let curBuf, let nested):
            continueBulletList(marker: marker, items: items,
                               curBuf: curBuf, nested: nested, newLine: line)

        case .inTaskList(let items, let curBuf, let nested):
            continueTaskList(items: items, curBuf: curBuf, nested: nested, newLine: line)

        case .inTable(let headerLine, let alignments, let rows, let pendingHeader):
            continueTable(headerLine: headerLine, alignments: alignments,
                          rows: rows, pendingHeader: pendingHeader, newLine: line)

        case .inHTMLBlock(let buf):
            continueHTMLBlock(buf: buf, newLine: line)
        }
    }

    // MARK: - New block dispatch

    private func dispatchNewLine(_ line: String) {
        // Blank line
        if line.trimmingCharacters(in: .init(charactersIn: " \t")).isEmpty {
            emit(.inlineToken(.text("")))  // represents a blank line boundary; no-op for rendering
            return
        }

        let trimmed = line.trimmingCharacters(in: .init(charactersIn: " \t"))

        // Thematic break
        if isThematicBreak(line) {
            emit(.thematicBreak)
            return
        }

        // ATX heading
        if let (level, content) = detectATXHeading(line) {
            if content.isEmpty {
                // Finalise immediately (empty heading)
                let children: [InlineToken] = []
                emit(.heading(HeadingToken(level: level, children: children, anchor: "")))
            } else {
                state = .inATXHeading(level: level, buffer: content)
            }
            return
        }

        // Blockquote
        if trimmed.hasPrefix("> ") || trimmed == ">" {
            let content = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
            let nested = IncrementalMarkdownParser()
            state = .inBlockquote(buffer: content, nested: nested)
            _ = nested.consume(delta: content + "\n")
            return
        }

        // Fenced code block
        if let (fence, lang, meta) = detectFencedCodeFence(line) {
            state = .inFencedCode(fence: fence, language: lang.isEmpty ? nil : lang,
                                  meta: meta.isEmpty ? nil : meta, buffer: "")
            return
        }

        // Indented code block (4 spaces or 1 tab)
        if line.hasPrefix("    ") || line.hasPrefix("\t") {
            let stripped = line.hasPrefix("\t") ? String(line.dropFirst()) : String(line.dropFirst(4))
            state = .inIndentedCode(buffer: stripped)
            return
        }

        // Task list
        if let (_, bRest) = detectBulletListMarker(line),
           let (checked, itemContent) = detectTaskListItem(bRest) {
            let nested = IncrementalMarkdownParser()
            _ = nested.consume(delta: itemContent + "\n")
            state = .inTaskList(
                items: [],
                currentBuffer: "[\(checked ? "x" : " ")] " + itemContent,
                currentNested: nested
            )
            return
        }

        // Bullet list
        if let (marker, rest) = detectBulletListMarker(line) {
            let nested = IncrementalMarkdownParser()
            _ = nested.consume(delta: rest + "\n")
            state = .inBulletList(marker: marker, items: [], currentBuffer: rest, currentNested: nested)
            return
        }

        // Ordered list
        if let (start, rest) = detectOrderedListMarker(line) {
            let nested = IncrementalMarkdownParser()
            _ = nested.consume(delta: rest + "\n")
            state = .inOrderedList(startNum: start, items: [], currentBuffer: rest, currentNested: nested)
            return
        }

        // Table (starts with `|` or contains `|`)
        if trimmed.hasPrefix("|") || trimmed.contains("|") {
            state = .inTable(headerLine: line, alignments: [], rows: [], pendingHeaderLine: nil)
            return
        }

        // HTML block
        if isHTMLBlockStart(line) {
            state = .inHTMLBlock(buffer: line)
            return
        }

        // Paragraph
        state = .inParagraph(buffer: line)
    }

    // MARK: - Fenced code detection

    private func detectFencedCodeFence(_ line: String) -> (fence: String, lang: String, meta: String)? {
        let chars = Array(line)
        var i = 0
        // Skip up to 3 leading spaces
        while i < chars.count, chars[i] == " ", i < 3 { i += 1 }
        guard i < chars.count, chars[i] == "`" || chars[i] == "~" else { return nil }
        let fenceChar = chars[i]
        var fenceLen = 0
        while i < chars.count, chars[i] == fenceChar { fenceLen += 1; i += 1 }
        guard fenceLen >= 3 else { return nil }
        let fence = String(repeating: fenceChar, count: fenceLen)
        let infoString = String(chars[i...]).trimmingCharacters(in: .init(charactersIn: " \t"))
        // Backtick fences: info string must not contain backtick
        if fenceChar == "`", infoString.contains("`") { return nil }
        let infoParts = infoString.split(separator: " ", maxSplits: 1)
        let lang = infoParts.first.map(String.init) ?? ""
        let meta = infoParts.count > 1 ? String(infoParts[1]) : ""
        return (fence, lang, meta)
    }

    // MARK: - Paragraph continuation

    private func continueParagraph(buf: String, newLine: String) {
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))

        // Blank line ends paragraph
        if trimmed.isEmpty {
            let children = InlineParser.parseFinalized(buf)
            emit(.paragraph(ParagraphToken(children: children)))
            state = .idle
            return
        }

        // Setext underline (= or -) converts paragraph to heading
        if trimmed.allSatisfy({ $0 == "=" }), trimmed.count >= 1 {
            let children = InlineParser.parseFinalized(buf)
            let anchor = slugify(inlineTokensPlainText(children))
            emit(.heading(HeadingToken(level: 1, children: children, anchor: anchor)))
            state = .idle
            return
        }
        if trimmed.allSatisfy({ $0 == "-" }), trimmed.count >= 1 {
            // Could also be thematic break — disambiguate: setext wins if buf is non-empty
            let children = InlineParser.parseFinalized(buf)
            let anchor = slugify(inlineTokensPlainText(children))
            emit(.heading(HeadingToken(level: 2, children: children, anchor: anchor)))
            state = .idle
            return
        }

        // Thematic break or ATX heading or list item interrupts paragraph
        if isThematicBreak(newLine) {
            let children = InlineParser.parseFinalized(buf)
            emit(.paragraph(ParagraphToken(children: children)))
            state = .idle
            emit(.thematicBreak)
            return
        }
        if detectATXHeading(newLine) != nil {
            let children = InlineParser.parseFinalized(buf)
            emit(.paragraph(ParagraphToken(children: children)))
            state = .idle
            dispatchNewLine(newLine)
            return
        }
        if let (_, _, _) = detectFencedCodeFence(newLine) {
            let children = InlineParser.parseFinalized(buf)
            emit(.paragraph(ParagraphToken(children: children)))
            state = .idle
            dispatchNewLine(newLine)
            return
        }

        // Otherwise: continue paragraph (soft-wrap)
        state = .inParagraph(buffer: buf + "\n" + newLine)
    }

    // MARK: - ATX heading flush

    private func flushATXHeading() {
        if case .inATXHeading(let level, let buf) = state {
            let children = InlineParser.parseFinalized(buf)
            let plain = inlineTokensPlainText(children)
            let anchor = slugify(plain)
            emit(.heading(HeadingToken(level: level, children: children, anchor: anchor)))
            state = .idle
        }
    }

    // MARK: - Fenced code continuation

    private func continueFencedCode(
        fence: String, lang: String?, meta: String?, buf: String, newLine: String
    ) {
        // Closing fence: same or longer fence of same character, optional trailing spaces
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))
        let fenceChar = fence.first!
        if trimmed.allSatisfy({ $0 == fenceChar }), trimmed.count >= fence.count {
            emit(.codeBlock(CodeBlockToken(language: lang, code: buf, meta: meta)))
            state = .idle
            return
        }
        // Continuation line: strip up to 3 leading spaces (indent stripping)
        var line = newLine
        var stripped = 0
        while stripped < 3, line.hasPrefix(" ") { line = String(line.dropFirst()); stripped += 1 }
        state = .inFencedCode(fence: fence, language: lang, meta: meta,
                              buffer: buf.isEmpty ? line : buf + "\n" + line)
    }

    // MARK: - Indented code continuation

    private func continueIndentedCode(buf: String, newLine: String) {
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))
        if trimmed.isEmpty {
            // Blank line: may continue or may end — buffer a blank line
            state = .inIndentedCode(buffer: buf + "\n")
            return
        }
        if newLine.hasPrefix("    ") || newLine.hasPrefix("\t") {
            let stripped = newLine.hasPrefix("\t") ? String(newLine.dropFirst()) : String(newLine.dropFirst(4))
            state = .inIndentedCode(buffer: buf + "\n" + stripped)
            return
        }
        // No longer indented — flush
        let code = buf.trimmingCharacters(in: .init(charactersIn: "\n"))
        emit(.codeBlock(CodeBlockToken(language: nil, code: code, meta: nil)))
        state = .idle
        dispatchNewLine(newLine)
    }

    // MARK: - Blockquote continuation

    private func continueBlockquote(
        buf: String, nested: IncrementalMarkdownParser, newLine: String
    ) {
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))
        if trimmed.isEmpty {
            // Blank line ends the blockquote
            let children = nested.finalize()
            emit(.blockquote(BlockquoteToken(children: children)))
            state = .idle
            return
        }
        if trimmed.hasPrefix("> ") || trimmed == ">" {
            let content = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
            let newBuf = buf + "\n" + content
            _ = nested.consume(delta: content + "\n")
            state = .inBlockquote(buffer: newBuf, nested: nested)
        } else {
            // Lazy continuation — blockquote may continue with non-`>` lines
            let newBuf = buf + "\n" + trimmed
            _ = nested.consume(delta: trimmed + "\n")
            state = .inBlockquote(buffer: newBuf, nested: nested)
        }
    }

    // MARK: - Ordered list continuation

    private func continueOrderedList(
        startNum: Int,
        items: [ListItemToken],
        curBuf: String,
        nested: IncrementalMarkdownParser,
        newLine: String
    ) {
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))

        // Blank line may end the list or continue (lazy)
        if trimmed.isEmpty {
            // Flush current item, end list
            let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
            let allItems = items + [currentItem]
            emit(.list(ListToken(kind: .ordered(start: startNum), items: allItems)))
            state = .idle
            return
        }

        // New ordered list item
        if let (_, rest) = detectOrderedListMarker(newLine) {
            let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
            let newNested = IncrementalMarkdownParser()
            _ = newNested.consume(delta: rest + "\n")
            state = .inOrderedList(
                startNum: startNum,
                items: items + [currentItem],
                currentBuffer: rest,
                currentNested: newNested
            )
            return
        }

        // Continuation of current item (indented or continuation line)
        if newLine.hasPrefix("   ") || newLine.hasPrefix("\t") {
            let stripped = newLine.hasPrefix("\t") ? String(newLine.dropFirst()) : String(newLine.dropFirst(3))
            _ = nested.consume(delta: stripped + "\n")
            state = .inOrderedList(startNum: startNum, items: items,
                                   currentBuffer: curBuf + "\n" + stripped, currentNested: nested)
            return
        }

        // Otherwise: end list, dispatch the new line
        let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
        let allItems = items + [currentItem]
        emit(.list(ListToken(kind: .ordered(start: startNum), items: allItems)))
        state = .idle
        dispatchNewLine(newLine)
    }

    // MARK: - Bullet list continuation

    private func continueBulletList(
        marker: Character,
        items: [ListItemToken],
        curBuf: String,
        nested: IncrementalMarkdownParser,
        newLine: String
    ) {
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))

        if trimmed.isEmpty {
            let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
            emit(.list(ListToken(kind: .unordered, items: items + [currentItem])))
            state = .idle
            return
        }

        // New bullet item with same or different marker
        if let (newMarker, rest) = detectBulletListMarker(newLine) {
            // Task item in a bullet list — hand off to task-list dispatch
            if let (_, _) = detectTaskListItem(rest) {
                let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
                emit(.list(ListToken(kind: .unordered, items: items + [currentItem])))
                state = .idle
                dispatchNewLine(newLine)
                return
            }
            if newMarker == marker {
                let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
                let newNested = IncrementalMarkdownParser()
                _ = newNested.consume(delta: rest + "\n")
                state = .inBulletList(
                    marker: marker,
                    items: items + [currentItem],
                    currentBuffer: rest,
                    currentNested: newNested
                )
                return
            } else {
                // Different marker — flush current list, start new
                let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
                emit(.list(ListToken(kind: .unordered, items: items + [currentItem])))
                state = .idle
                dispatchNewLine(newLine)
                return
            }
        }

        // Continuation line
        if newLine.hasPrefix("  ") || newLine.hasPrefix("\t") {
            let stripped = newLine.hasPrefix("\t") ? String(newLine.dropFirst()) : String(newLine.dropFirst(2))
            _ = nested.consume(delta: stripped + "\n")
            state = .inBulletList(marker: marker, items: items,
                                  currentBuffer: curBuf + "\n" + stripped, currentNested: nested)
            return
        }

        // End list
        let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
        emit(.list(ListToken(kind: .unordered, items: items + [currentItem])))
        state = .idle
        dispatchNewLine(newLine)
    }

    // MARK: - Task list continuation

    private func continueTaskList(
        items: [ListItemToken],
        curBuf: String,
        nested: IncrementalMarkdownParser,
        newLine: String
    ) {
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))

        if trimmed.isEmpty {
            let currentItem = buildTaskItemFromBuffer(nested: nested, buffer: curBuf)
            emit(.list(ListToken(kind: .task, items: items + [currentItem])))
            state = .idle
            return
        }

        // New task item
        if let (_, rest) = detectBulletListMarker(newLine),
           let (checked, itemContent) = detectTaskListItem(rest) {
            let currentItem = buildTaskItemFromBuffer(nested: nested, buffer: curBuf)
            let newNested = IncrementalMarkdownParser()
            _ = newNested.consume(delta: itemContent + "\n")
            state = .inTaskList(
                items: items + [currentItem],
                currentBuffer: "[\(checked ? "x" : " ")] " + itemContent,
                currentNested: newNested
            )
            return
        }

        // Continuation line
        if newLine.hasPrefix("  ") || newLine.hasPrefix("\t") {
            let stripped = newLine.hasPrefix("\t") ? String(newLine.dropFirst()) : String(newLine.dropFirst(2))
            _ = nested.consume(delta: stripped + "\n")
            state = .inTaskList(items: items,
                                currentBuffer: curBuf + "\n" + stripped, currentNested: nested)
            return
        }

        // End list
        let currentItem = buildTaskItemFromBuffer(nested: nested, buffer: curBuf)
        emit(.list(ListToken(kind: .task, items: items + [currentItem])))
        state = .idle
        dispatchNewLine(newLine)
    }

    // MARK: - Table continuation

    private func continueTable(
        headerLine: String,
        alignments: [ColumnAlignment],
        rows: [TableRowToken],
        pendingHeader: String?,
        newLine: String
    ) {
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))

        if alignments.isEmpty {
            // We have the header line; next line should be the separator
            if let aligns = parseTableSeparatorRow(newLine) {
                state = .inTable(headerLine: headerLine, alignments: aligns, rows: [], pendingHeaderLine: nil)
            } else {
                // Not a valid separator — treat header as paragraph and start fresh
                let children = InlineParser.parseFinalized(headerLine)
                emit(.paragraph(ParagraphToken(children: children)))
                state = .idle
                dispatchNewLine(newLine)
            }
            return
        }

        // We have header + alignments; expecting data rows
        if trimmed.isEmpty {
            // End of table
            let header = parseTableRow(headerLine, alignments: alignments, isHeader: true)
            emit(.table(TableToken(headers: header, rows: rows, alignments: alignments)))
            state = .idle
            return
        }

        if trimmed.hasPrefix("|") || trimmed.contains("|") {
            let newRow = parseTableRow(newLine, alignments: alignments, isHeader: false)
            state = .inTable(headerLine: headerLine, alignments: alignments,
                             rows: rows + [newRow], pendingHeaderLine: nil)
        } else {
            // Non-table line ends the table
            let header = parseTableRow(headerLine, alignments: alignments, isHeader: true)
            emit(.table(TableToken(headers: header, rows: rows, alignments: alignments)))
            state = .idle
            dispatchNewLine(newLine)
        }
    }

    // MARK: - HTML block continuation

    private func continueHTMLBlock(buf: String, newLine: String) {
        let trimmed = newLine.trimmingCharacters(in: .init(charactersIn: " \t"))
        if trimmed.isEmpty {
            emit(.htmlBlock(buf))
            state = .idle
            return
        }
        state = .inHTMLBlock(buffer: buf + "\n" + newLine)
    }

    // MARK: - Flush current state

    /// Finalises the current open block and returns any resulting tokens.
    @discardableResult
    private func flushCurrentState() -> [MarkdownToken] {
        var extra: [MarkdownToken] = []
        switch state {
        case .idle:
            break

        case .inParagraph(let buf):
            let children = InlineParser.parseFinalized(buf)
            extra.append(.paragraph(ParagraphToken(children: children)))

        case .inATXHeading(let level, let buf):
            let children = InlineParser.parseFinalized(buf)
            let anchor = slugify(inlineTokensPlainText(children))
            extra.append(.heading(HeadingToken(level: level, children: children, anchor: anchor)))

        case .inFencedCode(_, let lang, let meta, let buf):
            extra.append(.codeBlock(CodeBlockToken(language: lang, code: buf, meta: meta)))

        case .inIndentedCode(let buf):
            let code = buf.trimmingCharacters(in: .init(charactersIn: "\n"))
            extra.append(.codeBlock(CodeBlockToken(language: nil, code: code, meta: nil)))

        case .inBlockquote(_, let nested):
            let children = nested.finalize()
            extra.append(.blockquote(BlockquoteToken(children: children)))

        case .inOrderedList(let startNum, let items, let curBuf, let nested):
            let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
            extra.append(.list(ListToken(kind: .ordered(start: startNum), items: items + [currentItem])))

        case .inBulletList(_, let items, let curBuf, let nested):
            let currentItem = buildListItem(nested: nested, buffer: curBuf, checkbox: nil)
            extra.append(.list(ListToken(kind: .unordered, items: items + [currentItem])))

        case .inTaskList(let items, let curBuf, let nested):
            let currentItem = buildTaskItemFromBuffer(nested: nested, buffer: curBuf)
            extra.append(.list(ListToken(kind: .task, items: items + [currentItem])))

        case .inTable(let headerLine, let alignments, let rows, _):
            if alignments.isEmpty {
                // No separator seen — emit as paragraph
                let children = InlineParser.parseFinalized(headerLine)
                extra.append(.paragraph(ParagraphToken(children: children)))
            } else {
                let header = parseTableRow(headerLine, alignments: alignments, isHeader: true)
                extra.append(.table(TableToken(headers: header, rows: rows, alignments: alignments)))
            }

        case .inHTMLBlock(let buf):
            extra.append(.htmlBlock(buf))
        }
        state = .idle
        return extra
    }

    // MARK: - Emit

    private func emit(_ token: MarkdownToken) {
        // Filter empty inline-text tokens used as blank-line markers
        if case .inlineToken(.text(let s)) = token, s.isEmpty { return }
        finalized.append(token)
    }

    // MARK: - List item building helpers

    private func buildListItem(
        nested: IncrementalMarkdownParser,
        buffer: String,
        checkbox: TaskCheckboxToken?
    ) -> ListItemToken {
        let children = nested.finalize()
        if children.isEmpty {
            // Fall back to inline parsing if nested parser produced nothing
            let inline = InlineParser.parseFinalized(buffer)
            let para = MarkdownToken.paragraph(ParagraphToken(children: inline))
            return ListItemToken(children: [para], checkbox: checkbox)
        }
        return ListItemToken(children: children, checkbox: checkbox)
    }

    private func buildTaskItemFromBuffer(
        nested: IncrementalMarkdownParser,
        buffer: String
    ) -> ListItemToken {
        // Buffer format: "[x] content" or "[ ] content"
        var checked = false
        var content = buffer
        if buffer.lowercased().hasPrefix("[x] ") {
            checked = true; content = String(buffer.dropFirst(4))
        } else if buffer.hasPrefix("[ ] ") {
            checked = false; content = String(buffer.dropFirst(4))
        }
        let checkbox = TaskCheckboxToken(isChecked: checked)
        let children = nested.finalize()
        if children.isEmpty {
            let inline = InlineParser.parseFinalized(content)
            return ListItemToken(
                children: [.paragraph(ParagraphToken(children: inline))],
                checkbox: checkbox)
        }
        return ListItemToken(children: children, checkbox: checkbox)
    }

    private func buildPartialListItems(
        existing: [ListItemToken],
        currentBuffer: String,
        nested: IncrementalMarkdownParser
    ) -> [ListItemToken] {
        let partialInline = InlineParser.parse(currentBuffer, allowPartial: true)
        let partialItem = ListItemToken(
            children: [.paragraph(ParagraphToken(children: partialInline))],
            checkbox: nil)
        return existing + [partialItem]
    }

    private func buildPartialTaskListItems(
        existing: [ListItemToken],
        currentBuffer: String,
        nested: IncrementalMarkdownParser
    ) -> [ListItemToken] {
        var checked = false
        var content = currentBuffer
        if currentBuffer.lowercased().hasPrefix("[x] ") {
            checked = true; content = String(currentBuffer.dropFirst(4))
        } else if currentBuffer.hasPrefix("[ ] ") {
            content = String(currentBuffer.dropFirst(4))
        }
        let partialInline = InlineParser.parse(content, allowPartial: true)
        let partialItem = ListItemToken(
            children: [.paragraph(ParagraphToken(children: partialInline))],
            checkbox: TaskCheckboxToken(isChecked: checked))
        return existing + [partialItem]
    }

    // MARK: - Speculative partial (when idle but lineBuffer has content)

    private func speculativePartial(for buffer: String) -> MarkdownToken {
        if buffer.hasPrefix("#") {
            if let (level, content) = detectATXHeading(buffer) {
                let children = InlineParser.parse(content, allowPartial: true)
                let anchor = slugify(inlineTokensPlainText(children))
                return .partial(PartialToken(kind: .heading, rawText: buffer,
                                             resolvedChildren: [.heading(HeadingToken(level: level, children: children, anchor: anchor))]))
            }
        }
        if buffer.hasPrefix("```") || buffer.hasPrefix("~~~") {
            return .partial(PartialToken(kind: .codeBlock, rawText: buffer))
        }
        if buffer.trimmingCharacters(in: .init(charactersIn: " \t")).hasPrefix("|") {
            return .partial(PartialToken(kind: .table, rawText: buffer))
        }
        let children = InlineParser.parse(buffer, allowPartial: true)
        return .partial(PartialToken(kind: .paragraph, rawText: buffer,
                                     resolvedChildren: [.paragraph(ParagraphToken(children: children))]))
    }
}
