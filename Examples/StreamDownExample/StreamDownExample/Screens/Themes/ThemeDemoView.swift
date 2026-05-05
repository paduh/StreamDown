// ThemeDemoView.swift
// Live theme preview with horizontal chip selector and optional custom editor.

import SwiftUI
import StreamDownUI
import StreamDownCore

struct ThemeDemoView: View {

    enum ThemePreset: String, CaseIterable, Identifiable {
        case `default` = "Default"
        case github    = "GitHub"
        case minimal   = "Minimal"
        case dark      = "Dark"
        case custom    = "Custom"

        var id: String { rawValue }

        func resolvedTheme(custom: Theme) -> Theme {
            switch self {
            case .default: return .default
            case .github:  return .github
            case .minimal: return .minimal
            case .dark:    return .dark
            case .custom:  return custom
            }
        }
    }

    @State private var selectedPreset: ThemePreset = .default
    @State private var customTheme: Theme = .default
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                presetChips
                Divider()
                previewPane
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedPreset == .custom {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") { showEditor = true }
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                NavigationStack {
                    CustomThemeEditorView(theme: $customTheme)
                        .navigationTitle("Custom Theme")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showEditor = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Subviews

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ThemePreset.allCases) { preset in
                    Button(preset.rawValue) {
                        selectedPreset = preset
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedPreset == preset ? .accentColor : .secondary)
                    .fontWeight(selectedPreset == preset ? .semibold : .regular)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var previewPane: some View {
        let theme = selectedPreset.resolvedTheme(custom: customTheme)
        StreamDownView(markdown: MarkdownFixtures.themeShowcase)
            .theme(theme)
    }
}
