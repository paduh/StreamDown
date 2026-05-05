// RendererDemoView.swift
// Toggle optional renderers on/off and observe how the preview changes.

import SwiftUI
import StreamDownUI
import StreamDownCode
import StreamDownMath
import StreamDownDiagram

struct RendererDemoView: View {

    @State private var codeEnabled     = true
    @State private var mathEnabled     = false
    @State private var diagramEnabled  = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                togglePanel
                Divider()
                RendererPreview(
                    codeEnabled:    codeEnabled,
                    mathEnabled:    mathEnabled,
                    diagramEnabled: diagramEnabled
                )
            }
            .navigationTitle("Renderers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Toggle panel

    private var togglePanel: some View {
        VStack(spacing: 0) {
            RendererToggleRow(
                icon:     "chevron.left.forwardslash.chevron.right",
                title:    "Syntax Highlighting",
                subtitle: "StreamDownCode",
                isOn:     $codeEnabled
            )
            Divider().padding(.leading, 52)
            RendererToggleRow(
                icon:     "function",
                title:    "LaTeX Math",
                subtitle: "StreamDownMath",
                isOn:     $mathEnabled
            )
            Divider().padding(.leading, 52)
            RendererToggleRow(
                icon:     "flowchart",
                title:    "Mermaid Diagrams",
                subtitle: "StreamDownDiagram",
                isOn:     $diagramEnabled
            )
        }
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - RendererToggleRow

struct RendererToggleRow: View {
    let icon:     String
    let title:    String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - RendererPreview
//
// Separated into its own view so that the renderer set is re-evaluated
// whenever any toggle changes, which rebuilds the environment chain.

struct RendererPreview: View {
    let codeEnabled:    Bool
    let mathEnabled:    Bool
    let diagramEnabled: Bool

    var body: some View {
        StreamDownView(markdown: MarkdownFixtures.renderersShowcase)
            .theme(.github)
            .modifier(ActiveRendererModifier(
                codeEnabled:    codeEnabled,
                mathEnabled:    mathEnabled,
                diagramEnabled: diagramEnabled
            ))
    }
}

// MARK: - ActiveRendererModifier

struct ActiveRendererModifier: ViewModifier {
    let codeEnabled:    Bool
    let mathEnabled:    Bool
    let diagramEnabled: Bool

    func body(content: Content) -> some View {
        // Build the renderer chain by wrapping content in AnyView.
        // Each conditional renderer is applied in priority order.
        var result = AnyView(content)

        if codeEnabled {
            result = AnyView(result.renderer(StreamDownCode()))
        }
        if mathEnabled {
            result = AnyView(result.renderer(StreamDownMath()))
        }
        if diagramEnabled {
            result = AnyView(result.renderer(StreamDownDiagram()))
        }

        return result
    }
}
