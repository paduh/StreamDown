// LinkSafetyPolicy.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

import Foundation

// MARK: - LinkSafetyDecision

/// The action the renderer should take after evaluating a link.
public enum LinkSafetyDecision: Sendable {
    /// Open the link immediately.
    case open

    /// Show a confirmation prompt before opening.
    case confirm

    /// Prevent the link from being activated.
    case block
}

// MARK: - LinkSafetyPolicy

/// Governs which links the renderer will open, prompt on, or block.
///
/// `LinkSafetyPolicy` intentionally does **not** conform to `Equatable`
/// because the `.custom` mode stores a closure, which cannot be compared.
public struct LinkSafetyPolicy: Sendable {

    // MARK: Mode

    /// The evaluation strategy for a given URL.
    public enum Mode: Sendable {
        /// Allow all links unless they match a blocked scheme.
        case allow

        /// Always show a confirmation prompt before opening any link.
        case confirm

        /// Block all link activation.
        case block

        /// Delegate the decision to a caller-supplied closure.
        ///
        /// - Important: The closure must be `Sendable`. On Swift 5.x this
        ///   requires `@Sendable`; the typealias below enforces this.
        case custom(@Sendable (URL) -> LinkSafetyDecision)
    }

    // MARK: Properties

    /// The primary evaluation strategy.
    public var mode: Mode

    /// When non-nil, only links whose host is in this set pass without confirmation.
    /// Applies to `.allow` and `.confirm` modes; ignored in `.block` and `.custom`.
    public var allowedHosts: Set<String>?

    /// URL schemes that are always blocked regardless of mode.
    /// Defaults to `["javascript", "data", "vbscript"]`.
    public var blockedSchemes: Set<String>

    /// When non-nil, only images whose host is in this set are loaded inline.
    public var allowedImageHosts: Set<String>?

    // MARK: Init

    public init(
        mode: Mode,
        allowedHosts: Set<String>?     = nil,
        blockedSchemes: Set<String>    = ["javascript", "data", "vbscript"],
        allowedImageHosts: Set<String>? = nil
    ) {
        self.mode              = mode
        self.allowedHosts      = allowedHosts
        self.blockedSchemes    = blockedSchemes
        self.allowedImageHosts = allowedImageHosts
    }

    // MARK: Evaluation

    /// Evaluates `url` against the policy and returns the appropriate decision.
    public func decision(for url: URL) -> LinkSafetyDecision {
        // Always block dangerous schemes first.
        if let scheme = url.scheme?.lowercased(), blockedSchemes.contains(scheme) {
            return .block
        }

        switch mode {
        case .allow:
            if let allowed = allowedHosts, let host = url.host {
                return allowed.contains(host) ? .open : .confirm
            }
            return .open

        case .confirm:
            return .confirm

        case .block:
            return .block

        case .custom(let handler):
            return handler(url)
        }
    }

    // MARK: Static presets

    /// Balanced default — blocks dangerous schemes, allows everything else.
    public static let `default` = LinkSafetyPolicy(
        mode:           .allow,
        allowedHosts:   nil,
        blockedSchemes: ["javascript", "data", "vbscript"]
    )

    /// Strict — confirms every link, blocks dangerous schemes.
    public static let strict = LinkSafetyPolicy(
        mode:           .confirm,
        allowedHosts:   nil,
        blockedSchemes: ["javascript", "data", "vbscript", "file", "tel", "sms"]
    )

    /// Permissive — opens all links including those with only dangerous schemes blocked.
    /// Use only in fully trusted content environments.
    public static let permissive = LinkSafetyPolicy(
        mode:           .allow,
        allowedHosts:   nil,
        blockedSchemes: []
    )
}
