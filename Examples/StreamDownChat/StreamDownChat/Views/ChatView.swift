import SwiftUI

/// The root view: a scrolling message thread above a fixed input bar.
struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var inputText = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageThread
                InputBarView(
                    text: $inputText,
                    onSend: sendMessage,
                    onStop: store.stopStreaming,
                    isStreaming: store.isStreaming
                )
            }
            .navigationTitle("StreamDown Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Private

    private var messageThread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if store.messages.isEmpty {
                        welcomePlaceholder
                    }

                    ForEach(store.messages) { message in
                        MessageBubbleView(messageID: message.id)
                            .padding(.horizontal)
                    }

                    // Invisible anchor at the very bottom for auto-scroll.
                    Color.clear
                        .frame(height: 1)
                        .id("scrollBottom")
                }
                .padding(.vertical, 12)
            }
            .onChange(of: store.messages.last?.content) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("scrollBottom", anchor: .bottom)
                }
            }
        }
    }

    private var welcomePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text("StreamDown Chat")
                .font(.title2.bold())

            Text("A real-world example of streaming markdown.\nTap ⚙ to enter your Anthropic API key,\nor try simulated mode right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 32)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        store.send(trimmed)
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatStore())
}
