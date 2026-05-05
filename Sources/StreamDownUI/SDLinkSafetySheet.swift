// SDLinkSafetySheet.swift
// StreamDownUI — Confirmation sheet shown before opening an external link.

import SwiftUI
import StreamDownCore

// MARK: - SDLinkSafetySheet

struct SDLinkSafetySheet: View {
    let url: URL
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open Link?")
                        .font(.headline)

                    Text("You are about to open an external link. Make sure you trust this destination before continuing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(url.absoluteString)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.15))
                        )
                }

                Spacer()

                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Label("Open in Safari", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .cancel, action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
#if os(iOS) || os(watchOS) || os(visionOS)
            .toolbar(.hidden, for: .navigationBar)
#endif
        }
        .presentationDetents([.medium])
    }
}
