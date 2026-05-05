// StreamingControlPanel.swift
// Control bar shown above the streaming preview.

import SwiftUI

struct StreamingControlPanel: View {

    let isStreaming: Bool
    @Binding var tokensPerSecond: Double
    @Binding var selectedFixture: StreamingDemoView.FixtureOption
    @Binding var selectedAnimation: StreamingDemoView.AnimationOption
    let onStart: () -> Void
    let onStop:  () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Fixture picker
            Picker("Fixture", selection: $selectedFixture) {
                ForEach(StreamingDemoView.FixtureOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isStreaming)

            // Speed slider
            HStack(spacing: 8) {
                Image(systemName: "tortoise")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Slider(value: $tokensPerSecond, in: 5...200, step: 5)
                    .disabled(isStreaming)

                Image(systemName: "hare")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text("\(Int(tokensPerSecond)) tok/s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 68, alignment: .trailing)
            }

            // Animation picker + Start/Stop/Reset
            HStack {
                Picker("", selection: $selectedAnimation) {
                    ForEach(StreamingDemoView.AnimationOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .disabled(isStreaming)

                Spacer()

                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isStreaming)

                Button(isStreaming ? "Stop" : "Start") {
                    isStreaming ? onStop() : onStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(isStreaming ? .red : .accentColor)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}
