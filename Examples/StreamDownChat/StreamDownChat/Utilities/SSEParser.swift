import Foundation

/// Parses a single Server-Sent Events line from the Anthropic streaming API
/// and returns the text delta, if any.
enum SSEParser {

    private struct StreamEvent: Decodable {
        let type: String
        let delta: Delta?

        struct Delta: Decodable {
            let type: String?
            let text: String?
        }
    }

    /// Returns the text delta from a `content_block_delta` SSE line, or `nil`
    /// for all other event types (ping, message_start, etc.).
    static func parseDelta(from line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        guard json != "[DONE]",
              let data  = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
              event.type == "content_block_delta",
              event.delta?.type == "text_delta"
        else { return nil }
        return event.delta?.text
    }
}
