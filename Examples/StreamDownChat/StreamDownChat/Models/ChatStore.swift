import Foundation

@MainActor
final class ChatStore: ObservableObject {

    // MARK: - Conversation State

    @Published var messages: [ChatMessage] = []
    @Published var isStreaming = false

    // MARK: - Settings (persisted in UserDefaults)

    @Published var useRealAPI: Bool {
        didSet { UserDefaults.standard.set(useRealAPI, forKey: Keys.useRealAPI) }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }
    @Published var themeName: String {
        didSet { UserDefaults.standard.set(themeName, forKey: Keys.themeName) }
    }

    private enum Keys {
        static let useRealAPI = "sd_useRealAPI"
        static let apiKey    = "sd_apiKey"
        static let model     = "sd_model"
        static let themeName = "sd_themeName"
    }

    static let availableModels = [
        "claude-opus-4-6",
        "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001",
    ]

    static let availableThemes = ["default", "github", "minimal", "dark"]

    // MARK: - Private

    private var streamingTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        useRealAPI = UserDefaults.standard.bool(forKey: Keys.useRealAPI)
        apiKey     = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
        model      = UserDefaults.standard.string(forKey: Keys.model) ?? "claude-sonnet-4-6"
        themeName  = UserDefaults.standard.string(forKey: Keys.themeName) ?? "default"
    }

    // MARK: - Actions

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMsg      = ChatMessage(role: .user, content: trimmed)
        let assistantMsg = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(userMsg)
        messages.append(assistantMsg)

        let assistantID = assistantMsg.id
        isStreaming = true

        streamingTask = Task {
            let stream: AsyncStream<String> = useRealAPI && !apiKey.isEmpty
                ? AnthropicStreamClient.stream(
                    messages: buildAPIMessages(),
                    model: model,
                    apiKey: apiKey)
                : SimulatedStreamClient.stream(for: trimmed)

            for await delta in stream {
                guard !Task.isCancelled else { break }
                if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[idx].content += delta
                }
            }

            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].isStreaming = false
            }
            isStreaming = false
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        if let idx = messages.indices.last, messages[idx].isStreaming {
            messages[idx].isStreaming = false
        }
        isStreaming = false
    }

    func clearConversation() {
        stopStreaming()
        messages = []
    }

    // MARK: - Helpers

    private func buildAPIMessages() -> [[String: String]] {
        // Drop the last (empty) assistant placeholder before sending to the API.
        messages.dropLast().map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.content]
        }
    }
}
