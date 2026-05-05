import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    var isStreaming: Bool

    enum Role {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, content: String = "", isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}
