import SwiftUI
import StreamDownCore   // Theme, TokenAnimation, LinkSafetyPolicy
import StreamDownUI     // StreamDownView + view modifiers
import StreamDownCode   // StreamDownCode renderer

/// Renders an assistant message using StreamDownView with the user's active theme.
struct AssistantMessageView: View {
    let messageID: UUID
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        if let message = store.messages.first(where: { $0.id == messageID }) {
            StreamDownView(
                text: Binding(
                    get: { message.content },
                    set: { _ in }   // content is driven by the store, never by the view
                ),
                isStreaming: message.isStreaming
            )
            .theme(resolvedTheme)
            .renderer(StreamDownCode())
            .tokenAnimation(.fadeIn(duration: 0.12))
            .linkSafety(.default)
        }
    }

    // MARK: - Private

    private var resolvedTheme: Theme {
        switch store.themeName {
        case "github":  return .github
        case "minimal": return .minimal
        case "dark":    return .dark
        default:        return .default
        }
    }
}
