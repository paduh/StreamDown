// StreamDownConfiguration.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

import Foundation

// MARK: - ImageSecurityPolicy

/// Controls which image hosts are permitted to load inline images.
public struct ImageSecurityPolicy: Sendable, Equatable {
    /// When non-nil, only images whose host is in this set are loaded.
    /// When `nil`, all hosts are permitted.
    public var allowedHosts: Set<String>?

    public init(allowedHosts: Set<String>? = nil) {
        self.allowedHosts = allowedHosts
    }

    /// Permissive default — all image hosts are allowed.
    public static let `default` = ImageSecurityPolicy(allowedHosts: nil)

    /// Returns `true` if the given URL's host is permitted by this policy.
    public func permits(url: URL) -> Bool {
        guard let allowed = allowedHosts else { return true }
        guard let host = url.host else { return false }
        return allowed.contains(host)
    }
}

// MARK: - CodeBlockActions

/// Feature flags that control the action bar shown above code blocks.
public struct CodeBlockActions: Sendable, Equatable {
    /// Show a copy-to-clipboard button.
    public var showCopy: Bool

    /// Show a download-as-file button.
    public var showDownload: Bool

    /// Show the detected language label.
    public var showLanguageLabel: Bool

    /// Show line numbers in the gutter.
    public var showLineNumbers: Bool

    public init(
        showCopy: Bool          = true,
        showDownload: Bool      = true,
        showLanguageLabel: Bool = true,
        showLineNumbers: Bool   = false
    ) {
        self.showCopy          = showCopy
        self.showDownload      = showDownload
        self.showLanguageLabel = showLanguageLabel
        self.showLineNumbers   = showLineNumbers
    }

    public static let `default` = CodeBlockActions(
        showCopy:          true,
        showDownload:      true,
        showLanguageLabel: true,
        showLineNumbers:   false
    )
}

// MARK: - StreamDownConfiguration

/// Top-level configuration object passed to every StreamDown renderer.
///
/// All properties have sensible defaults — callers only need to customise
/// the specific behaviour they want to change.
public struct StreamDownConfiguration: Sendable {
    /// Link activation safety policy.
    public var linkSafety: LinkSafetyPolicy

    /// Inline image security policy.
    public var imageSecurity: ImageSecurityPolicy

    /// Streaming cursor style.
    public var cursor: CursorStyle

    /// Animation applied as new tokens stream in.
    public var tokenAnimation: TokenAnimation

    /// Code block action bar configuration.
    public var codeActions: CodeBlockActions

    /// Accessibility / screen reader configuration.
    public var accessibility: AccessibilityConfiguration

    public init(
        linkSafety: LinkSafetyPolicy                  = .default,
        imageSecurity: ImageSecurityPolicy             = .default,
        cursor: CursorStyle                            = .blinking(color: nil),
        tokenAnimation: TokenAnimation                 = .fadeIn(duration: 0.15),
        codeActions: CodeBlockActions                  = .default,
        accessibility: AccessibilityConfiguration      = .default
    ) {
        self.linkSafety      = linkSafety
        self.imageSecurity   = imageSecurity
        self.cursor          = cursor
        self.tokenAnimation  = tokenAnimation
        self.codeActions     = codeActions
        self.accessibility   = accessibility
    }

    /// Sensible out-of-the-box configuration suitable for most applications.
    public static let `default` = StreamDownConfiguration(
        linkSafety:     .default,
        imageSecurity:  .default,
        cursor:         .blinking(color: nil),
        tokenAnimation: .fadeIn(duration: 0.15),
        codeActions:    .default,
        accessibility:  .default
    )
}
