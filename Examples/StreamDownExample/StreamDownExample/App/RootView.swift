// RootView.swift
// Top-level TabView that hosts all demo screens.

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            GalleryView()
                .tabItem { Label("Gallery", systemImage: "doc.richtext") }

            StreamingDemoView()
                .tabItem { Label("Streaming", systemImage: "dot.radiowaves.right") }

            ThemeDemoView()
                .tabItem { Label("Themes", systemImage: "paintpalette") }

            RendererDemoView()
                .tabItem { Label("Renderers", systemImage: "puzzlepiece.extension") }

            UIKitDemoView()
                .tabItem { Label("UIKit", systemImage: "rectangle.3.group") }

            CustomRendererDemoView()
                .tabItem { Label("Custom", systemImage: "wand.and.stars") }
        }
    }
}
