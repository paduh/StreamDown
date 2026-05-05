import Foundation

/// Streams text deltas from the Anthropic Messages API using Server-Sent Events.
enum AnthropicStreamClient {

    static func stream(
        messages: [[String: String]],
        model: String,
        apiKey: String
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await fetch(
                        messages: messages,
                        model: model,
                        apiKey: apiKey,
                        continuation: continuation
                    )
                } catch {
                    // Silently finish on any network / API error.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private static func fetch(
        messages: [[String: String]],
        model: String,
        apiKey: String,
        continuation: AsyncStream<String>.Continuation
    ) async throws {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey,        forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",  forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 2048,
            "stream":     true,
            "messages":   messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // Read the error body for debugging, then bail.
            return
        }

        for try await line in bytes.lines {
            guard !Task.isCancelled else { return }
            if let delta = SSEParser.parseDelta(from: line) {
                continuation.yield(delta)
            }
        }
    }
}
