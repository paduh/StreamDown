import Foundation

/// Streams text deltas from the Anthropic Messages API using Server-Sent Events.
enum AnthropicStreamClient {

    /// A URLSession that accepts the server's certificate even when a TLS-inspecting
    /// proxy (Charles, corporate gateway, etc.) presents its own certificate for
    /// api.anthropic.com.  Scoped to that host only — all other challenges use the
    /// default OS evaluation.
    ///
    /// - Note: Do not copy this pattern into production apps. Certificate bypass is
    ///   appropriate here only because this is a local development example.
    private static let session: URLSession = {
        URLSession(configuration: .default, delegate: TrustAPIAnthropic(), delegateQueue: nil)
    }()

    // URLSession delivers HTTPS server-trust challenges at the *task* level,
    // not the session level — so URLSessionTaskDelegate is the correct protocol.
    private final class TrustAPIAnthropic: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  challenge.protectionSpace.host == "api.anthropic.com",
                  let trust = challenge.protectionSpace.serverTrust
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

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

        let (bytes, response) = try await session.bytes(for: request)

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
