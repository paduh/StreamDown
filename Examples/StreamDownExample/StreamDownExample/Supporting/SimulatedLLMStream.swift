// SimulatedLLMStream.swift
// Produces an AsyncStream<String> from a pre-written string,
// splitting it into variable-size chunks to mimic real LLM token output.

import Foundation

enum SimulatedLLMStream {

    /// Returns an `AsyncStream<String>` that emits chunks of `text` at
    /// approximately `tokensPerSecond` chunks per second.
    static func stream(
        for text: String,
        tokensPerSecond: Double = 30
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let chunks = makeChunks(from: text)
                let delayNanoseconds = UInt64(max(1_000_000, 1_000_000_000 / tokensPerSecond))

                for chunk in chunks {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    /// Splits a string into 1–4 character chunks, weighted toward 2–3 chars,
    /// mimicking the uneven token sizes produced by real LLM tokenizers.
    private static func makeChunks(from text: String) -> [String] {
        // Weights: size 1 (20%), 2 (35%), 3 (30%), 4 (15%)
        let sizes = [1, 1, 2, 2, 2, 2, 3, 3, 3, 4]
        var chunks: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            let size = sizes.randomElement()!
            let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[index..<end]))
            index = end
        }

        return chunks
    }
}
