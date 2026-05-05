// SDCursorView.swift
// StreamDownUI — Inline streaming cursor indicator.

import SwiftUI
import StreamDownCore

// MARK: - SDCursorView

struct SDCursorView: View {
    let style: CursorStyle

    @Environment(\.streamDownTheme) private var theme

    @State private var visible: Bool = true

    var body: some View {
        switch style {
        case .none:
            EmptyView()

        case .solid(let colorDesc):
            cursorRect(color: resolvedColor(colorDesc))

        case .blinking(let colorDesc):
            cursorRect(color: resolvedColor(colorDesc))
                .opacity(visible ? 1 : 0)
                .onAppear {
                    withAnimation(
                        Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                    ) {
                        visible = false
                    }
                }
        }
    }

    // MARK: - Helpers

    private func cursorRect(color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 2, height: CGFloat(theme.typography.bodySize) * 1.2)
    }

    private func resolvedColor(_ desc: ColorDescription?) -> Color {
        if let d = desc {
            return Color(red: d.r, green: d.g, blue: d.b, opacity: d.a)
        }
        let accent = theme.colors.accent
        return Color(red: accent.r, green: accent.g, blue: accent.b, opacity: accent.a)
    }
}
