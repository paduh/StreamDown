// MarkdownFixtures.swift
// StreamDownTestSupport — Shared test fixtures for StreamDown test targets.

import StreamDownCore

// MARK: - MarkdownFixtures

/// A catalog of canonical Markdown samples used across StreamDown's test suite.
///
/// Each entry exposes the raw Markdown string together with a human-readable name
/// that identifies the Markdown construct being exercised.
///
/// Use `deltaSequence(for:chunkSize:)` to split a sample into streaming chunks
/// that simulate real token-at-a-time delivery from an LLM.
public enum MarkdownFixtures {

    // MARK: - Fixture catalog

    /// All fixtures as `(name, markdown)` pairs.
    ///
    /// The `name` field uses snake_case and describes the primary construct
    /// exercised by the sample.
    public static let all: [(name: String, markdown: String)] = [
        ("heading_h1",        "# Hello World"),
        ("heading_h2",        "## Subheading"),
        ("bold",              "**bold text**"),
        ("italic",            "*italic text*"),
        ("strikethrough",     "~~struck~~"),
        ("code_span",         "Use `print()` here"),
        ("code_block_swift",
         """
         ```swift
         let x = 1
         ```
         """),
        ("code_block_python",
         """
         ```python
         def hello():
             pass
         ```
         """),
        ("link",              "[OpenAI](https://openai.com)"),
        ("image",             "![Logo](https://example.com/logo.png)"),
        ("blockquote",        "> This is quoted"),
        ("unordered_list",    "- Item one\n- Item two\n- Item three"),
        ("ordered_list",      "1. First\n2. Second\n3. Third"),
        ("task_list",         "- [x] Done\n- [ ] Todo"),
        ("table",
         """
         | Name | Age |
         |------|-----|
         | Alice | 30 |
         """),
        ("thematic_break",    "---"),
        ("paragraph",         "This is a paragraph with **bold** and *italic* text."),
        ("nested_blockquote", "> Outer\n> > Inner"),
        ("mixed_inline",      "Visit [site](https://example.com) or use `code` here"),
        ("hard_break",        "Line one  \nLine two"),
    ]

    // MARK: - Named fixture lookup

    /// Returns the Markdown string for a fixture with the given name, or `nil` if not found.
    public static func fixture(named name: String) -> String? {
        all.first(where: { $0.name == name })?.markdown
    }

    // MARK: - Delta streaming simulation

    /// Splits `markdown` into consecutive chunks of at most `chunkSize` characters.
    ///
    /// This simulates the token-at-a-time delivery from a streaming LLM API:
    ///
    /// ```swift
    /// let chunks = MarkdownFixtures.deltaSequence(for: "# Hello World", chunkSize: 3)
    /// // → ["# H", "ell", "o W", "orl", "d"]
    /// ```
    ///
    /// - Parameters:
    ///   - markdown:  The full Markdown string to split.
    ///   - chunkSize: Maximum characters per chunk. Defaults to `5`.
    /// - Returns: An array of non-empty substrings covering the full input.
    public static func deltaSequence(for markdown: String, chunkSize: Int = 5) -> [String] {
        guard chunkSize > 0 else { return markdown.isEmpty ? [] : [markdown] }

        return stride(from: 0, to: markdown.count, by: chunkSize).map { i in
            let start = markdown.index(markdown.startIndex, offsetBy: i)
            let end   = markdown.index(
                start,
                offsetBy: min(chunkSize, markdown.count - i)
            )
            return String(markdown[start..<end])
        }
    }

    // MARK: - Complete-stream helper

    /// Feeds all chunks produced by `deltaSequence` through a fresh `IncrementalMarkdownParser`
    /// and returns the fully finalized token list.
    ///
    /// Useful for golden-value tests where you want the parser's output for a given fixture
    /// without caring about the intermediate partial state.
    ///
    /// - Parameters:
    ///   - markdown:  The full Markdown string to parse.
    ///   - chunkSize: Chunk size forwarded to `deltaSequence`. Defaults to `5`.
    /// - Returns: All tokens finalized by the parser after the stream closes.
    public static func parseStreaming(
        _ markdown: String,
        chunkSize: Int = 5
    ) -> [MarkdownToken] {
        let parser = IncrementalMarkdownParser()
        var tokens: [MarkdownToken] = []
        for chunk in deltaSequence(for: markdown, chunkSize: chunkSize) {
            tokens += parser.consume(delta: chunk)
        }
        tokens += parser.finalize()
        return tokens
    }

    /// Parse a Markdown string in a single shot (no streaming simulation).
    ///
    /// Equivalent to calling `parser.consume(delta: markdown)` followed by
    /// `parser.finalize()`.
    public static func parseDirect(_ markdown: String) -> [MarkdownToken] {
        let parser = IncrementalMarkdownParser()
        var tokens = parser.consume(delta: markdown)
        tokens += parser.finalize()
        return tokens
    }
}
