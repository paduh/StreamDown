// GalleryView.swift
// Renders the full GFM token set from a static markdown string.
// Use the theme menu in the navigation bar to swap presets.

import SwiftUI
import StreamDownUI
import StreamDownCore

struct GalleryView: View {

    @State private var selectedTheme = Theme.default

    private let themePresets: [(String, Theme)] = [
        ("Default", .default),
        ("GitHub",  .github),
        ("Minimal", .minimal),
        ("Dark",    .dark),
    ]

    var body: some View {
        NavigationStack {
            StreamDownView(markdown: MarkdownFixtures.fullGFM)
                .theme(selectedTheme)
                .navigationTitle("GFM Gallery")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            ForEach(themePresets, id: \.0) { name, theme in
                                Button {
                                    selectedTheme = theme
                                } label: {
                                    HStack {
                                        Text(name)
                                        if selectedTheme.name == theme.name {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Theme", systemImage: "paintpalette")
                        }
                    }
                }
        }
    }
}
