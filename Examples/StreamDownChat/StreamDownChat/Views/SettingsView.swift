import SwiftUI

/// A settings sheet for configuring the API connection, model, and theme.
struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                appearanceSection
                conversationSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            Toggle("Use Anthropic API", isOn: $store.useRealAPI)

            if store.useRealAPI {
                SecureField("API Key (sk-ant-…)", text: $store.apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Picker("Model", selection: $store.model) {
                    ForEach(ChatStore.availableModels, id: \.self) { id in
                        Text(modelDisplayName(id)).tag(id)
                    }
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            Text(
                store.useRealAPI
                    ? "Responses come from the live Claude API. Keep your key private."
                    : "Simulated mode streams pre-written markdown — no API key required."
            )
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $store.themeName) {
                ForEach(ChatStore.availableThemes, id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var conversationSection: some View {
        Section {
            Button("Clear Conversation", role: .destructive) {
                store.clearConversation()
                dismiss()
            }
            .disabled(store.messages.isEmpty)
        }
    }

    // MARK: - Helpers

    private func modelDisplayName(_ id: String) -> String {
        switch id {
        case "claude-opus-4-6":           return "Opus 4.6"
        case "claude-sonnet-4-6":         return "Sonnet 4.6"
        case "claude-haiku-4-5-20251001": return "Haiku 4.5"
        default: return id
        }
    }
}
