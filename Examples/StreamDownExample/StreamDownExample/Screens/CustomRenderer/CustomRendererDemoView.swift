// CustomRendererDemoView.swift
// Shows AlertBoxRenderer in action — toggle it off to see the raw blockquotes.

import SwiftUI
import StreamDownUI
import StreamDownCore

struct CustomRendererDemoView: View {

    @State private var rendererActive = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toggleBar
                Divider()
                if rendererActive {
                    StreamDownView(markdown: MarkdownFixtures.alertBoxFixture)
                        .theme(.github)
                        .renderer(AlertBoxRenderer())
                } else {
                    StreamDownView(markdown: MarkdownFixtures.alertBoxFixture)
                        .theme(.github)
                }
            }
            .navigationTitle("Custom Renderer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("How it works") {
                        RendererCodeView()
                    }
                }
            }
        }
    }

    private var toggleBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AlertBox Renderer")
                    .font(.body)
                Text("Intercepts ⚠️ ℹ️ ✅ blockquotes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $rendererActive)
                .labelsHidden()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - RendererCodeView

/// Shows the AlertBoxRenderer implementation as formatted markdown —
/// a meta demonstration of StreamDown rendering its own code.
private struct RendererCodeView: View {

    private let snippet = """
    # AlertBoxRenderer

    Conforms to `SwiftUIRenderer` from `StreamDownUI`.

    ```swift
    final class AlertBoxRenderer: SwiftUIRenderer, @unchecked Sendable {

        let rendererIdentifier = "com.example.alertbox"
        var renderPriority: Int = 10

        func canHandle(token: MarkdownToken) -> Bool {
            guard case .blockquote(let bq) = token,
                  case .paragraph(let p) = bq.children.first,
                  case .text(let s) = p.children.first
            else { return false }
            return s.hasPrefix("⚠️") || s.hasPrefix("ℹ️") || s.hasPrefix("✅")
        }

        @MainActor
        func makeView(for token: MarkdownToken, context: RenderContext) -> AnyView? {
            guard case .blockquote(let bq) = token else { return nil }
            return AnyView(AlertBoxView(blockquote: bq))
        }
    }
    ```

    ## Registration

    ```swift
    StreamDownView(stream: stream)
        .renderer(AlertBoxRenderer())
    ```

    Renderers are applied in ascending `renderPriority` order.
    The built-in pipeline only sees tokens that no renderer has claimed.
    """

    var body: some View {
        StreamDownView(markdown: snippet)
            .theme(.github)
            .navigationTitle("Implementation")
            .navigationBarTitleDisplayMode(.inline)
    }
}
