// StreamingDemoView.swift
// Demonstrates live streaming with configurable speed, fixture, and animation.

import SwiftUI
import StreamDownUI
import StreamDownCore

struct StreamingDemoView: View {

    // MARK: - Fixture options

    enum FixtureOption: String, CaseIterable, Identifiable {
        case shortResponse = "Short"
        case codeHeavy     = "Code"
        case tableHeavy    = "Tables"
        case longDocument  = "Long"

        var id: String { rawValue }

        var markdown: String {
            switch self {
            case .shortResponse: return MarkdownFixtures.shortResponse
            case .codeHeavy:    return MarkdownFixtures.codeHeavy
            case .tableHeavy:   return MarkdownFixtures.tableHeavy
            case .longDocument: return MarkdownFixtures.longDocument
            }
        }
    }

    // MARK: - Animation options

    enum AnimationOption: String, CaseIterable, Identifiable {
        case none    = "None"
        case fadeIn  = "Fade"
        case slideUp = "Slide"

        var id: String { rawValue }

        var tokenAnimation: TokenAnimation {
            switch self {
            case .none:    return .none
            case .fadeIn:  return .fadeIn(duration: 0.15)
            case .slideUp: return .slideUp(distance: 8, duration: 0.2)
            }
        }
    }

    // MARK: - State

    @State private var activeStream: AsyncStream<String>?
    @State private var streamID = UUID()
    @State private var isStreaming = false
    @State private var tokensPerSecond: Double = 30
    @State private var selectedFixture: FixtureOption = .shortResponse
    @State private var selectedAnimation: AnimationOption = .fadeIn

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StreamingControlPanel(
                    isStreaming: isStreaming,
                    tokensPerSecond: $tokensPerSecond,
                    selectedFixture: $selectedFixture,
                    selectedAnimation: $selectedAnimation,
                    onStart: startStream,
                    onStop:  stopStream,
                    onReset: resetStream
                )

                Divider()

                if let stream = activeStream {
                    StreamDownView(stream: stream)
                        .id(streamID)
                        .theme(.github)
                        .cursor(.blinking(color: nil))
                        .tokenAnimation(selectedAnimation.tokenAnimation)
                        .onStreamComplete { isStreaming = false }
                } else {
                    ContentUnavailableView(
                        "Ready to stream",
                        systemImage: "dot.radiowaves.right",
                        description: Text("Choose a fixture and tap **Start**.")
                    )
                }
            }
            .navigationTitle("Streaming")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Actions

    private func startStream() {
        streamID = UUID()
        isStreaming = true
        activeStream = SimulatedLLMStream.stream(
            for: selectedFixture.markdown,
            tokensPerSecond: tokensPerSecond
        )
    }

    private func stopStream() {
        activeStream = nil
        isStreaming = false
    }

    private func resetStream() {
        activeStream = nil
        isStreaming = false
    }
}
