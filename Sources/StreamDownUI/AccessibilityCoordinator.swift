// AccessibilityCoordinator.swift
// StreamDownUI — Coordinates VoiceOver announcements for streaming content.

import SwiftUI
import StreamDownCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - AccessibilityCoordinator

/// Receives `RenderModel` updates and posts platform accessibility announcements
/// at an adaptive rate, targeting sentence and heading boundaries to avoid
/// flooding the screen reader with every character.
@MainActor
final class AccessibilityCoordinator {

    // MARK: - Configuration

    private let configuration: AccessibilityConfiguration

    // MARK: - State

    /// The last version of the render model we announced content for.
    private var lastAnnouncedVersion: Int = -1
    /// Plain text from the last announcement, used for delta diffing.
    private var lastAnnouncedText: String = ""
    /// Tracks newly accumulated characters since the last announcement.
    private var pendingDelta: String = ""
    /// Scheduled work item for adaptive-rate throttling.
    private var pendingWork: DispatchWorkItem?
    /// Minimum number of characters to accumulate before announcing in adaptive mode.
    private let adaptiveCharThreshold: Int = 80
    /// The delay (seconds) before forcing an announcement even if threshold not met.
    private let adaptiveMaxDelay: TimeInterval = 2.5

    // MARK: - Init

    init(configuration: AccessibilityConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Call whenever the `RenderModel` updates with new streaming content.
    func modelDidUpdate(_ model: RenderModel) {
        guard model.version > lastAnnouncedVersion else { return }

        switch configuration.announcementPriority {
        case .off:
            return

        case .assertive:
            let text = plainText(from: model.finalizedTokens)
            let delta = delta(from: lastAnnouncedText, to: text)
            if !delta.isEmpty {
                announce(delta, polite: false)
                lastAnnouncedText = text
                lastAnnouncedVersion = model.version
            }

        case .adaptive:
            handleAdaptive(model: model)
        }
    }

    /// Call when streaming finishes to flush any pending announcement and
    /// post the completion notice.
    func streamingDidComplete(_ model: RenderModel) {
        pendingWork?.cancel()
        pendingWork = nil

        guard configuration.announcementPriority != .off else { return }

        let text = plainText(from: model.finalizedTokens)
        let delta = delta(from: lastAnnouncedText, to: text)

        if !delta.isEmpty {
            announce(delta, polite: true)
            lastAnnouncedText = text
        }

        announce("Streaming complete", polite: true)
        lastAnnouncedVersion = model.version
        pendingDelta = ""
    }

    // MARK: - Adaptive logic

    private func handleAdaptive(model: RenderModel) {
        let text = plainText(from: model.finalizedTokens)
        let newDelta = delta(from: lastAnnouncedText, to: text)
        guard !newDelta.isEmpty else { return }

        pendingDelta = newDelta

        // Announce immediately at semantic boundaries (heading completion, sentence end).
        if endsAtSemanticBoundary(newDelta) || newDelta.count >= adaptiveCharThreshold {
            flushAdaptive(model: model)
            return
        }

        // Schedule a deferred flush so slow streams still get announced.
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.flushAdaptive(model: model)
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + adaptiveMaxDelay, execute: work)
    }

    private func flushAdaptive(model: RenderModel) {
        pendingWork?.cancel()
        pendingWork = nil

        let text = plainText(from: model.finalizedTokens)
        let delta = delta(from: lastAnnouncedText, to: text)
        if !delta.isEmpty {
            announce(delta, polite: true)
            lastAnnouncedText = text
            lastAnnouncedVersion = model.version
        }
        pendingDelta = ""
    }

    // MARK: - Announcement dispatch

    private func announce(_ message: String, polite: Bool) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

#if canImport(UIKit)
        let notification: UIAccessibility.Notification = polite ? .announcement : .announcement
        UIAccessibility.post(notification: notification, argument: message)
#elseif canImport(AppKit)
        let priority: NSAccessibilityPriorityLevel = polite ? .medium : .high
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: priority.rawValue
            ]
        )
#endif
    }

    // MARK: - Text extraction

    private func plainText(from tokens: [MarkdownToken]) -> String {
        tokens.map { plainText(from: $0) }.joined(separator: "\n")
    }

    private func plainText(from token: MarkdownToken) -> String {
        switch token {
        case .heading(let t):
            return inlinePlainText(t.children)
        case .paragraph(let t):
            return inlinePlainText(t.children)
        case .codeBlock(let t):
            return t.code
        case .blockquote(let t):
            return t.children.map { plainText(from: $0) }.joined(separator: "\n")
        case .list(let t):
            return t.items.map { item in
                item.children.map { plainText(from: $0) }.joined(separator: " ")
            }.joined(separator: "\n")
        case .table(let t):
            let headerCells = t.headers.cells.map { inlinePlainText($0.children) }.joined(separator: " ")
            let rowTexts = t.rows.map { row in
                row.cells.map { inlinePlainText($0.children) }.joined(separator: " ")
            }.joined(separator: "\n")
            return [headerCells, rowTexts].joined(separator: "\n")
        case .thematicBreak:
            return ""
        case .htmlBlock:
            return ""
        case .inlineToken(let inline):
            return inlinePlainText([inline])
        case .partial(let p):
            return p.rawText
        case .cursor:
            return ""
        }
    }

    private func inlinePlainText(_ tokens: [InlineToken]) -> String {
        tokens.map { inlinePlainTextSingle($0) }.joined()
    }

    private func inlinePlainTextSingle(_ token: InlineToken) -> String {
        switch token {
        case .text(let s):                    return s
        case .softBreak:                      return " "
        case .hardBreak:                      return "\n"
        case .codeSpan(let t):               return t.code
        case .emphasis(let t):               return inlinePlainText(t.children)
        case .strong(let t):                 return inlinePlainText(t.children)
        case .strikethrough(let t):          return inlinePlainText(t.children)
        case .link(let t):                   return inlinePlainText(t.children)
        case .image(let t):                  return t.alt
        case .autolink(let t):               return t.url
        case .taskCheckbox(let t):           return t.isChecked ? "checked" : "unchecked"
        case .html:                          return ""
        }
    }

    // MARK: - Delta and boundary helpers

    private func delta(from old: String, to new: String) -> String {
        guard new.count > old.count else { return "" }
        return String(new.dropFirst(old.count))
    }

    /// Returns true if the delta ends at a sentence boundary or heading end.
    private func endsAtSemanticBoundary(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return false }
        return last == "." || last == "!" || last == "?" || last == "\n"
    }
}
