import SwiftUI

/// Renders a single message — user messages appear as a right-aligned bubble,
/// assistant messages are handed off to `AssistantMessageView`.
struct MessageBubbleView: View {
    let messageID: UUID
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        if let message = store.messages.first(where: { $0.id == messageID }) {
            switch message.role {
            case .user:
                userBubble(message.content)
            case .assistant:
                AssistantMessageView(messageID: messageID)
            }
        }
    }

    // MARK: - Private

    private func userBubble(_ text: String) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 60)
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.white)
        }
    }
}
