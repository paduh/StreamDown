import Foundation

/// Produces a canned streaming response without requiring an API key.
/// Useful for demos, screenshots, and testing without network access.
enum SimulatedStreamClient {

    static func stream(for input: String) -> AsyncStream<String> {
        let response = cannedResponse(for: input)
        return AsyncStream { continuation in
            let task = Task {
                let chunks = tokenize(response)
                for chunk in chunks {
                    guard !Task.isCancelled else { break }
                    continuation.yield(chunk)
                    let ns = UInt64.random(in: 18_000_000...65_000_000) // ~18–65 ms
                    try? await Task.sleep(nanoseconds: ns)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    /// Splits `text` into word-level tokens, preserving whitespace separately
    /// so the streaming cadence feels natural rather than character-by-character.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for char in text {
            if char.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func cannedResponse(for input: String) -> String {
        // Return the same rich demo response regardless of the query so every
        // feature of StreamDown is visible in the simulated mode.
        return """
        Great question! Here's how **StreamDown** renders streaming markdown.

        ## Streaming Features

        StreamDown handles *incomplete syntax* gracefully during streaming — no broken renders mid-stream. Every token that arrives is parsed incrementally and displayed immediately.

        ### Code Example

        ```swift
        import StreamDown
        import StreamDownCode

        StreamDownView(text: $content, isStreaming: true)
            .theme(.github)
            .renderer(StreamDownCode())
            .tokenAnimation(.fadeIn(duration: 0.1))
        ```

        ### Supported Formats

        | Format | Syntax | Live? |
        |--------|--------|-------|
        | **Bold** | `**text**` | ✅ |
        | *Italic* | `*text*` | ✅ |
        | `Code span` | `` `code` `` | ✅ |
        | Tables | `|col|` | ✅ |
        | Fenced code | ```` ``` ```` | ✅ |
        | Blockquotes | `>` | ✅ |

        ### Key Benefits

        - Partial markdown renders correctly **while tokens are still arriving**
        - A blinking cursor shows the active stream position
        - Smooth fade-in animations make the output feel polished

        > **Tip:** Open Settings (gear icon) to enter an Anthropic API key and switch to real Claude responses. You can also change the theme — each one styles this content differently.

        This is the power of **StreamDown**: streaming AI responses that *just work* with full markdown fidelity.
        """
    }
}
