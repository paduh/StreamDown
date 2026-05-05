import SwiftUI

/// The fixed-to-bottom input bar: a multiline text field and a send / stop button.
struct InputBarView: View {
    @Binding var text: String
    let onSend: () -> Void
    let onStop: () -> Void
    let isStreaming: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                .disabled(isStreaming)
                .onSubmit { sendIfNotStreaming() }

            actionButton
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Private

    private var actionButton: some View {
        Button(action: isStreaming ? onStop : sendIfNotStreaming) {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    isStreaming ? Color.red : Color.accentColor,
                    in: Circle()
                )
        }
        .disabled(!isStreaming && text.trimmingCharacters(in: .whitespaces).isEmpty)
        .animation(.easeInOut(duration: 0.15), value: isStreaming)
    }

    private func sendIfNotStreaming() {
        guard !isStreaming else { return }
        onSend()
    }
}
