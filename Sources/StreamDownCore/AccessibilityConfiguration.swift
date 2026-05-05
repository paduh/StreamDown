// AccessibilityConfiguration.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

/// Controls how a screen reader is notified of new streaming content.
public enum AnnouncementPriority: Sendable, Equatable {
    /// Screen reader announcements are disabled entirely.
    case off

    /// The renderer decides when to announce based on content significance
    /// (e.g. heading boundaries, end-of-stream). Suitable for most use cases.
    case adaptive

    /// Every token change is announced immediately via the assertive
    /// accessibility queue. Use with caution — can be disruptive.
    case assertive
}

/// Top-level accessibility settings passed into the renderer.
public struct AccessibilityConfiguration: Sendable, Equatable {
    /// How the system should announce streaming content to assistive technologies.
    public var announcementPriority: AnnouncementPriority

    public init(announcementPriority: AnnouncementPriority) {
        self.announcementPriority = announcementPriority
    }

    public static let `default` = AccessibilityConfiguration(announcementPriority: .adaptive)
}
