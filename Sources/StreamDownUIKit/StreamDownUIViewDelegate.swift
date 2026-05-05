// StreamDownUIViewDelegate.swift
// StreamDownUIKit — UIKit rendering layer for StreamDown

import UIKit
import StreamDownCore

// MARK: - StreamDownUIViewDelegate

/// Delegate protocol for `StreamDownUIView` events.
///
/// All methods have default no-op implementations so conformers only need to
/// implement the callbacks they care about.
public protocol StreamDownUIViewDelegate: AnyObject {

    /// Called whenever the content height changes (e.g. as new tokens stream in).
    func streamDownView(_ view: StreamDownUIView, didUpdateContentHeight height: CGFloat)

    /// Called after the user taps a link inside the view.
    func streamDownView(_ view: StreamDownUIView, didTapLink url: URL)

    /// Called before a link is opened. Return `false` to prevent opening.
    func streamDownView(_ view: StreamDownUIView, willOpenLink url: URL) -> Bool

    /// Called when the upstream `AsyncStream` closes and all content has been rendered.
    func streamDownView(_ view: StreamDownUIView, didFinishStreaming fullText: String)

    /// Called when the user taps the copy button in a code block.
    func streamDownView(_ view: StreamDownUIView, didCopyCode code: String, language: String?)
}

// MARK: - Default no-op implementations

public extension StreamDownUIViewDelegate {

    func streamDownView(_ view: StreamDownUIView, didUpdateContentHeight height: CGFloat) {}

    func streamDownView(_ view: StreamDownUIView, didTapLink url: URL) {}

    func streamDownView(_ view: StreamDownUIView, willOpenLink url: URL) -> Bool { true }

    func streamDownView(_ view: StreamDownUIView, didFinishStreaming fullText: String) {}

    func streamDownView(_ view: StreamDownUIView, didCopyCode code: String, language: String?) {}
}
