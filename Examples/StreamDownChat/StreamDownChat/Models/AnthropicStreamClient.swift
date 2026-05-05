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
                } catch is CancellationError {
                    // Clean stop — no error to show.
                } catch {
                    continuation.yield("**Network error:** \(error.localizedDescription)")
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
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            continuation.yield(apiErrorMessage(from: errorData, statusCode: http.statusCode))
            return
        }

        for try await line in bytes.lines {
            guard !Task.isCancelled else { return }
            if let delta = SSEParser.parseDelta(from: line) {
                continuation.yield(delta)
            }
        }
    }

    // MARK: - Error formatting

    private struct APIError: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }

    private static func apiErrorMessage(from data: Data, statusCode: Int) -> String {
        if let err = try? JSONDecoder().decode(APIError.self, from: data) {
            return "**API error \(statusCode):** \(err.error.message)"
        }
        let raw = String(data: data, encoding: .utf8) ?? "(no body)"
        return "**HTTP \(statusCode):** \(raw)"
    }
}
