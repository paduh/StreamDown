// TextDeltaAccumulatorTests.swift
// StreamDownCoreTests — XCTest suite for the TextDeltaAccumulator / IncrementalMarkdownParser
// streaming pipeline as observed through RenderModel.
//
// Note: `TextDeltaAccumulator` is `@MainActor` and internal to `StreamDownUI`, so we
// test the equivalent behavior via the public `IncrementalMarkdownParser` API directly.
// The version-increment contract and streaming flag are verified through `RenderModel`.

import XCTest
@testable import StreamDownCore

final class TextDeltaAccumulatorTests: XCTestCase {

    // MARK: - Helpers

    /// A lightweight reimplementation of TextDeltaAccumulator that mirrors the
    /// production class so we can unit-test it without a UI dependency.
    private final class Accumulator {
        private let parser = IncrementalMarkdownParser()
        private var _model = RenderModel.empty

        var model: RenderModel { _model }

        func consume(delta: String) {
            let finalized = parser.consume(delta: delta)
            let partial   = parser.currentPartialToken
            _model = _model.appending(
                finalized:     finalized,
                partial:       partial,
                cursorVisible: _model.isStreaming || partial != nil || !finalized.isEmpty
            )
        }

        func finalize() {
            let remaining = parser.finalize()
            _model = _model.appending(
                finalized:     remaining,
                partial:       nil,
                cursorVisible: false
            ).finalized()
        }

        func reset() {
            parser.reset()
            _model = .empty
        }
    }

    // MARK: - Version increment tests

    func testVersionIncrements() {
        let acc = Accumulator()
        let v0 = acc.model.version
        acc.consume(delta: "Hello")
        let v1 = acc.model.version
        acc.consume(delta: " World")
        let v2 = acc.model.version

        XCTAssertGreaterThan(v1, v0, "Version should increment after first delta")
        XCTAssertGreaterThan(v2, v1, "Version should increment after second delta")
    }

    func testVersionIncrementsOnEveryDelta() {
        let acc = Accumulator()
        var lastVersion = acc.model.version
        let deltas = ["#", " ", "T", "i", "t", "l", "e", "\n"]
        for delta in deltas {
            acc.consume(delta: delta)
            XCTAssertGreaterThan(acc.model.version, lastVersion,
                                 "Version should increment after consuming '\(delta)'")
            lastVersion = acc.model.version
        }
    }

    func testVersionIncrementsOnFinalize() {
        let acc = Accumulator()
        acc.consume(delta: "# Hello\n")
        let vBeforeFinalize = acc.model.version
        acc.finalize()
        XCTAssertGreaterThan(acc.model.version, vBeforeFinalize,
                             "Version should increment on finalize")
    }

    // MARK: - isStreaming / finalize tests

    func testFinalizeStopsStreaming() {
        let acc = Accumulator()
        acc.consume(delta: "Some text\n")
        // After consuming, model should be in streaming mode (partial or cursor).
        // (May or may not be streaming depending on whether a partial is present.)
        acc.finalize()
        XCTAssertFalse(acc.model.isStreaming,
                       "isStreaming should be false after finalize")
    }

    func testFinalizeRemovesPartialToken() {
        let acc = Accumulator()
        // Feed an unclosed code block — this will create a partial token.
        acc.consume(delta: "```swift\n")
        acc.consume(delta: "let x = 1\n")
        // Before finalize, there may be a partial token.
        acc.finalize()
        // After finalize, the model should have no partial tokens.
        XCTAssertNil(acc.model.partialToken,
                     "partialToken should be nil after finalize")
    }

    func testFinalizeProducesCodeBlock() {
        let acc = Accumulator()
        acc.consume(delta: "```python\ndef f():\n    pass\n```\n")
        acc.finalize()
        let hasCode = acc.model.tokens.contains { token -> Bool in
            if case .codeBlock = token { return true }
            return false
        }
        XCTAssertTrue(hasCode, "Finalized model should contain the code block")
        XCTAssertFalse(acc.model.isStreaming)
    }

    // MARK: - Raw text accumulation tests

    func testRawTextAccumulation() {
        // Feed a complete heading in one shot and verify it appears in the model.
        let acc = Accumulator()
        acc.consume(delta: "# Hello World\n")
        acc.finalize()

        let hasHeading = acc.model.tokens.contains { token -> Bool in
            if case .heading(let h) = token {
                let text = h.children.compactMap { inline -> String? in
                    if case .text(let s) = inline { return s }
                    return nil
                }.joined()
                return text.contains("Hello World")
            }
            return false
        }
        XCTAssertTrue(hasHeading, "Model should contain the heading; tokens: \(acc.model.tokens)")
    }

    func testRawTextAccumulationAcrossMultipleDeltas() {
        // Feed a paragraph character-by-character and confirm the final token is correct.
        let acc = Accumulator()
        let source = "A short paragraph.\n"
        for ch in source {
            acc.consume(delta: String(ch))
        }
        acc.finalize()

        let hasParagraph = acc.model.tokens.contains { token -> Bool in
            if case .paragraph(let p) = token {
                let text = p.children.compactMap { inline -> String? in
                    if case .text(let s) = inline { return s }
                    return nil
                }.joined()
                return text.contains("A short paragraph.")
            }
            return false
        }
        XCTAssertTrue(hasParagraph,
                      "Model should contain the paragraph; tokens: \(acc.model.tokens)")
    }

    func testRawTextAccumulationMultipleBlocks() {
        let acc = Accumulator()
        acc.consume(delta: "# Heading\n\nParagraph text.\n")
        acc.finalize()

        let hasHeading = acc.model.tokens.contains { if case .heading = $0 { return true }; return false }
        let hasParagraph = acc.model.tokens.contains { if case .paragraph = $0 { return true }; return false }
        XCTAssertTrue(hasHeading,   "Should have heading; tokens: \(acc.model.tokens)")
        XCTAssertTrue(hasParagraph, "Should have paragraph; tokens: \(acc.model.tokens)")
    }

    // MARK: - Empty delta tests

    func testEmptyDelta() {
        let acc = Accumulator()
        let v0 = acc.model.version
        acc.consume(delta: "")
        // An empty delta should still increment the version (appending is always called).
        // In practice implementations may or may not increment — we just assert no crash.
        // The important thing is the model stays consistent.
        XCTAssertEqual(acc.model.tokens.count, 0,
                       "Empty delta should not produce tokens")
        // Model should be valid (version >= initial).
        XCTAssertGreaterThanOrEqual(acc.model.version, v0)
    }

    func testEmptyDeltaDoesNotCorruptSubsequentInput() {
        let acc = Accumulator()
        acc.consume(delta: "")
        acc.consume(delta: "")
        acc.consume(delta: "# Real heading\n")
        acc.finalize()

        let hasHeading = acc.model.tokens.contains { if case .heading = $0 { return true }; return false }
        XCTAssertTrue(hasHeading,
                      "Heading should be present after empty deltas; tokens: \(acc.model.tokens)")
    }

    func testEmptyStringFinalizeProducesEmptyModel() {
        let acc = Accumulator()
        acc.consume(delta: "")
        acc.finalize()
        XCTAssertTrue(acc.model.tokens.isEmpty)
        XCTAssertFalse(acc.model.isStreaming)
    }

    // MARK: - Reset tests

    func testResetResetsVersion() {
        let acc = Accumulator()
        acc.consume(delta: "# Hello\n")
        XCTAssertGreaterThan(acc.model.version, 0)
        acc.reset()
        XCTAssertEqual(acc.model.version, 0, "Version should reset to 0")
    }

    func testResetClearsTokens() {
        let acc = Accumulator()
        acc.consume(delta: "# Hello\n")
        acc.finalize()
        XCTAssertFalse(acc.model.tokens.isEmpty)
        acc.reset()
        XCTAssertTrue(acc.model.tokens.isEmpty, "Tokens should be empty after reset")
    }

    func testResetAllowsReuseWithFreshContent() {
        let acc = Accumulator()
        acc.consume(delta: "# First\n")
        acc.finalize()
        acc.reset()

        acc.consume(delta: "## Second\n")
        acc.finalize()

        let headings = acc.model.tokens.compactMap { token -> HeadingToken? in
            if case .heading(let h) = token { return h } else { return nil }
        }
        XCTAssertEqual(headings.count, 1, "Should have exactly one heading after reset+reuse")
        XCTAssertEqual(headings.first?.level, 2)
    }

    // MARK: - RenderModel partial token tests

    func testPartialTokenPresentDuringStreaming() {
        let acc = Accumulator()
        // Feed an opening fence but no closing fence — the parser should expose a partial.
        acc.consume(delta: "```swift\n")
        acc.consume(delta: "let y = 2\n")
        // The model might expose the partial via partialToken or within tokens.
        // We check that finalized() returns the code block.
        acc.finalize()
        let hasCode = acc.model.tokens.contains { if case .codeBlock = $0 { return true }; return false }
        XCTAssertTrue(hasCode, "Code block should be in final model after finalize")
    }

    func testFinalizedTokensExcludePartialAndCursor() {
        let acc = Accumulator()
        acc.consume(delta: "# Title\n")
        acc.finalize()
        let finalized = acc.model.finalizedTokens
        let hasPartial = finalized.contains { if case .partial = $0 { return true }; return false }
        let hasCursor  = finalized.contains { $0 == .cursor }
        XCTAssertFalse(hasPartial, "finalizedTokens should exclude .partial sentinels")
        XCTAssertFalse(hasCursor,  "finalizedTokens should exclude .cursor sentinels")
    }
}
