// IncrementalMarkdownParserTests.swift
// StreamDownCoreTests — XCTest suite for IncrementalMarkdownParser.

import XCTest
@testable import StreamDownCore
import StreamDownTestSupport

final class IncrementalMarkdownParserTests: XCTestCase {

    // MARK: - Helpers

    private func parse(_ markdown: String) -> [MarkdownToken] {
        MarkdownFixtures.parseDirect(markdown)
    }

    private func parseStreaming(_ markdown: String, chunkSize: Int = 5) -> [MarkdownToken] {
        MarkdownFixtures.parseStreaming(markdown, chunkSize: chunkSize)
    }

    /// Assert that a token array contains at least one heading at the given level
    /// whose text (joined from all `.text` inline children) contains `substring`.
    private func assertContainsHeading(
        _ tokens: [MarkdownToken],
        level: Int,
        containing substring: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let found = tokens.contains { token -> Bool in
            guard case .heading(let h) = token, h.level == level else { return false }
            let text = h.children.compactMap { inline -> String? in
                if case .text(let s) = inline { return s }
                return nil
            }.joined()
            return text.contains(substring)
        }
        XCTAssertTrue(found,
                      "Expected heading level \(level) containing '\(substring)' in tokens: \(tokens)",
                      file: file, line: line)
    }

    // MARK: - Heading tests

    func testH1Heading() {
        let tokens = parse("# Hello World\n")
        assertContainsHeading(tokens, level: 1, containing: "Hello World")
    }

    func testH2Heading() {
        let tokens = parse("## Subheading\n")
        assertContainsHeading(tokens, level: 2, containing: "Subheading")
    }

    func testHeadingAnchorGeneration() {
        let tokens = parse("# Hello World\n")
        let heading = tokens.compactMap { (t: MarkdownToken) -> HeadingToken? in
            if case .heading(let h) = t { return h } else { return nil }
        }.first
        XCTAssertNotNil(heading)
        XCTAssertEqual(heading?.anchor, "hello-world")
    }

    func testH3ThroughH6() {
        for level in 3...6 {
            let hashes = String(repeating: "#", count: level)
            let tokens = parse("\(hashes) Level \(level)\n")
            assertContainsHeading(tokens, level: level, containing: "Level \(level)")
        }
    }

    // MARK: - Paragraph / inline tests

    func testBoldParagraph() {
        let tokens = parse("**bold text**\n")
        let hasStrong = tokens.contains { token -> Bool in
            guard case .paragraph(let p) = token else { return false }
            return p.children.contains { inline in
                if case .strong = inline { return true }
                return false
            }
        }
        XCTAssertTrue(hasStrong, "Expected a paragraph with a strong child in \(tokens)")
    }

    func testItalicParagraph() {
        let tokens = parse("*italic text*\n")
        let hasEmphasis = tokens.contains { token -> Bool in
            guard case .paragraph(let p) = token else { return false }
            return p.children.contains { inline in
                if case .emphasis = inline { return true }
                return false
            }
        }
        XCTAssertTrue(hasEmphasis, "Expected paragraph with emphasis in \(tokens)")
    }

    // MARK: - Code block tests

    func testCodeBlockFenced() {
        let md = "```swift\nlet x = 1\n```\n"
        let tokens = parse(md)
        let codeBlock = tokens.compactMap { (t: MarkdownToken) -> CodeBlockToken? in
            if case .codeBlock(let cb) = t { return cb } else { return nil }
        }.first
        XCTAssertNotNil(codeBlock, "Expected a code block token")
        XCTAssertEqual(codeBlock?.language, "swift")
        XCTAssertTrue(codeBlock?.code.contains("let x = 1") ?? false,
                      "Code block should contain source")
    }

    func testCodeBlockIsPartialUntilClose() {
        // Feed the opening fence and some body — no closing fence yet.
        let parser = IncrementalMarkdownParser()
        var finalized: [MarkdownToken] = []
        finalized += parser.consume(delta: "```python\n")
        finalized += parser.consume(delta: "def hello():\n")
        finalized += parser.consume(delta: "    pass\n")

        // The parser should NOT have emitted a finalized codeBlock yet.
        let hasCodeBlock = finalized.contains { if case .codeBlock = $0 { return true }; return false }
        XCTAssertFalse(hasCodeBlock, "Code block should not be finalized before closing fence")

        // The partial token should indicate an in-progress code block.
        let partial = parser.currentPartialToken
        XCTAssertNotNil(partial, "Parser should expose a partial token")
        if let partial {
            if case .partial(let p) = partial {
                XCTAssertEqual(p.kind, .codeBlock)
            } else {
                XCTFail("Expected a .partial token, got \(partial)")
            }
        }

        // Now close the fence.
        finalized += parser.consume(delta: "```\n")
        let nowHasCodeBlock = finalized.contains { if case .codeBlock = $0 { return true }; return false }
        XCTAssertTrue(nowHasCodeBlock, "Code block should be finalized after closing fence")
    }

    func testCodeBlockPythonLanguageTag() {
        let md = "```python\ndef hello():\n    pass\n```\n"
        let tokens = parse(md)
        let codeBlock = tokens.compactMap { (t: MarkdownToken) -> CodeBlockToken? in
            if case .codeBlock(let cb) = t { return cb } else { return nil }
        }.first
        XCTAssertEqual(codeBlock?.language, "python")
    }

    func testCodeBlockNoLanguage() {
        let md = "```\nsome code\n```\n"
        let tokens = parse(md)
        let codeBlock = tokens.compactMap { (t: MarkdownToken) -> CodeBlockToken? in
            if case .codeBlock(let cb) = t { return cb } else { return nil }
        }.first
        XCTAssertNotNil(codeBlock)
        XCTAssertNil(codeBlock?.language)
    }

    // MARK: - List tests

    func testUnorderedList() {
        let md = "- Item one\n- Item two\n- Item three\n"
        let tokens = parse(md)
        let list = tokens.compactMap { (t: MarkdownToken) -> ListToken? in
            if case .list(let l) = t { return l } else { return nil }
        }.first
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.kind, .unordered)
        XCTAssertEqual(list?.items.count, 3)
    }

    func testOrderedList() {
        let md = "1. First\n2. Second\n3. Third\n"
        let tokens = parse(md)
        let list = tokens.compactMap { (t: MarkdownToken) -> ListToken? in
            if case .list(let l) = t { return l } else { return nil }
        }.first
        XCTAssertNotNil(list)
        if case .ordered(let start) = list?.kind {
            XCTAssertEqual(start, 1)
        } else {
            XCTFail("Expected ordered list, got \(String(describing: list?.kind))")
        }
        XCTAssertEqual(list?.items.count, 3)
    }

    func testTaskList() {
        let md = "- [x] Done\n- [ ] Todo\n"
        let tokens = parse(md)
        let list = tokens.compactMap { (t: MarkdownToken) -> ListToken? in
            if case .list(let l) = t { return l } else { return nil }
        }.first
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.kind, .task)
        XCTAssertEqual(list?.items.count, 2)

        let checked = list?.items.first?.checkbox?.isChecked
        XCTAssertEqual(checked, true, "First task item should be checked")

        let unchecked = list?.items.last?.checkbox?.isChecked
        XCTAssertEqual(unchecked, false, "Second task item should be unchecked")
    }

    // MARK: - Blockquote test

    func testBlockquote() {
        let md = "> This is quoted\n"
        let tokens = parse(md)
        let blockquote = tokens.compactMap { (t: MarkdownToken) -> BlockquoteToken? in
            if case .blockquote(let b) = t { return b } else { return nil }
        }.first
        XCTAssertNotNil(blockquote, "Expected a blockquote token in \(tokens)")
        XCTAssertFalse(blockquote?.children.isEmpty ?? true,
                       "Blockquote should have children")
    }

    func testNestedBlockquote() {
        let md = "> Outer\n> > Inner\n"
        let tokens = parse(md)
        let blockquote = tokens.compactMap { (t: MarkdownToken) -> BlockquoteToken? in
            if case .blockquote(let b) = t { return b } else { return nil }
        }.first
        XCTAssertNotNil(blockquote)
        // The outer blockquote's children should contain an inner blockquote.
        let hasNestedBlockquote = blockquote?.children.contains { inner in
            if case .blockquote = inner { return true }
            return false
        } ?? false
        XCTAssertTrue(hasNestedBlockquote,
                      "Expected inner blockquote in children: \(String(describing: blockquote?.children))")
    }

    // MARK: - Table test

    func testTable() {
        let md = "| Name | Age |\n|------|-----|\n| Alice | 30 |\n"
        let tokens = parse(md)
        let table = tokens.compactMap { (t: MarkdownToken) -> TableToken? in
            if case .table(let t) = t { return t } else { return nil }
        }.first
        XCTAssertNotNil(table, "Expected table token in \(tokens)")
        XCTAssertEqual(table?.headers.cells.count, 2)
        XCTAssertEqual(table?.rows.count, 1)
    }

    // MARK: - Thematic break test

    func testThematicBreak() {
        let tokens = parse("---\n")
        let hasBreak = tokens.contains { $0 == .thematicBreak }
        XCTAssertTrue(hasBreak, "Expected .thematicBreak in \(tokens)")
    }

    func testThematicBreakAsterisk() {
        let tokens = parse("***\n")
        let hasBreak = tokens.contains { $0 == .thematicBreak }
        XCTAssertTrue(hasBreak)
    }

    // MARK: - Mixed inline test

    func testMixedInline() {
        let md = "Visit [site](https://example.com) or use `code` here\n"
        let tokens = parse(md)
        let paragraph = tokens.compactMap { (t: MarkdownToken) -> ParagraphToken? in
            if case .paragraph(let p) = t { return p } else { return nil }
        }.first
        XCTAssertNotNil(paragraph)

        let inlineKinds = paragraph?.children ?? []
        let hasLink = inlineKinds.contains { if case .link = $0 { return true }; return false }
        let hasCode = inlineKinds.contains { if case .codeSpan = $0 { return true }; return false }
        XCTAssertTrue(hasLink, "Expected inline link")
        XCTAssertTrue(hasCode, "Expected inline code span")
    }

    // MARK: - Streaming chunk test

    func testStreamingInChunks() {
        // Parse the same Markdown both directly and via chunks, expect equal output.
        for (name, markdown) in MarkdownFixtures.all {
            let direct   = MarkdownFixtures.parseDirect(markdown + "\n")
            let streamed = MarkdownFixtures.parseStreaming(markdown + "\n", chunkSize: 3)
            XCTAssertEqual(direct, streamed,
                           "Fixture '\(name)' produced different results for direct vs streaming parse")
        }
    }

    func testStreamingPreservesAllTokens() {
        // Feed a multi-block document chunk-by-chunk; verify all blocks are present.
        let md = "# Title\n\nParagraph text.\n\n- A\n- B\n\n```swift\nlet x = 1\n```\n"
        let tokens = parseStreaming(md, chunkSize: 4)
        let hasHeading   = tokens.contains { if case .heading   = $0 { return true }; return false }
        let hasParagraph = tokens.contains { if case .paragraph = $0 { return true }; return false }
        let hasList      = tokens.contains { if case .list      = $0 { return true }; return false }
        let hasCode      = tokens.contains { if case .codeBlock = $0 { return true }; return false }
        XCTAssertTrue(hasHeading,   "Missing heading in streamed output")
        XCTAssertTrue(hasParagraph, "Missing paragraph in streamed output")
        XCTAssertTrue(hasList,      "Missing list in streamed output")
        XCTAssertTrue(hasCode,      "Missing code block in streamed output")
    }

    // MARK: - finalize / reset tests

    func testFinalizeFlushesState() {
        // Feed an unclosed code block — finalize should emit it.
        let parser = IncrementalMarkdownParser()
        _ = parser.consume(delta: "```swift\nlet x = 1\n")
        // No closing fence — finalize should flush the partial.
        let tokens = parser.finalize()
        let hasCode = tokens.contains { if case .codeBlock = $0 { return true }; return false }
        XCTAssertTrue(hasCode, "Finalize should flush partial code block; got \(tokens)")
    }

    func testFinalizeFlushesPartialParagraph() {
        let parser = IncrementalMarkdownParser()
        _ = parser.consume(delta: "Hello world")  // no newline
        let tokens = parser.finalize()
        let hasParagraph = tokens.contains { if case .paragraph = $0 { return true }; return false }
        XCTAssertTrue(hasParagraph, "Finalize should flush partial paragraph; got \(tokens)")
    }

    func testResetClearsState() {
        let parser = IncrementalMarkdownParser()
        _ = parser.consume(delta: "# Heading\n")
        _ = parser.consume(delta: "Some text\n")
        parser.reset()

        // After reset, finalize should return nothing.
        let tokens = parser.finalize()
        XCTAssertTrue(tokens.isEmpty, "After reset, parser should be empty; got \(tokens)")

        // Partial token should also be nil.
        XCTAssertNil(parser.currentPartialToken,
                     "After reset, currentPartialToken should be nil")
    }

    func testResetAndReuse() {
        let parser = IncrementalMarkdownParser()
        // First parse.
        _ = parser.consume(delta: "# First\n")
        let first = parser.finalize()
        XCTAssertFalse(first.isEmpty)

        // Reset and re-use.
        parser.reset()
        _ = parser.consume(delta: "# Second\n")
        let second = parser.finalize()
        assertContainsHeading(second, level: 1, containing: "Second")
    }

    // MARK: - Edge cases

    func testEmptyInput() {
        let tokens = parse("")
        XCTAssertTrue(tokens.isEmpty, "Empty input should produce no tokens")
    }

    func testBlankLines() {
        // Blank lines between blocks should not produce visible tokens.
        let tokens = parse("# A\n\n# B\n")
        let headings = tokens.compactMap { (t: MarkdownToken) -> HeadingToken? in
            if case .heading(let h) = t { return h } else { return nil }
        }
        XCTAssertEqual(headings.count, 2)
    }

    func testSetextH1Heading() {
        let tokens = parse("Hello\n=====\n")
        assertContainsHeading(tokens, level: 1, containing: "Hello")
    }

    func testSetextH2Heading() {
        let tokens = parse("Hello\n-----\n")
        assertContainsHeading(tokens, level: 2, containing: "Hello")
    }
}
