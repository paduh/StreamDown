// SDUKCursorView.swift
// StreamDownUIKit — UIKit rendering layer for StreamDown

import UIKit
import StreamDownCore

// MARK: - SDUKCursorView

/// A narrow view that renders the streaming cursor (blinking bar or solid bar).
///
/// Attach this view at the trailing edge of the last rendered text block.
/// Call `configure(style:theme:)` to set the cursor style. The view
/// self-manages its `CADisplayLink` and tears it down on `removeFromSuperview`.
final class SDUKCursorView: UIView {

    // MARK: - Private state

    private var style: CursorStyle = .blinking(color: nil)
    private var displayLink: CADisplayLink?

    /// Toggles on each blink tick.
    private var blinkPhase: Bool = true

    /// Frame counter — blink toggles every 30 frames (≈2 Hz at 60 fps).
    private var frameCount: Int = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        clipsToBounds = false
    }

    // MARK: - Configuration

    /// Set the cursor style and begin (or stop) the blink animation.
    ///
    /// Must be called from the main thread.
    func configure(style: CursorStyle, theme: Theme) {
        self.style = style
        stopDisplayLink()

        switch style {
        case .blinking(let colorDescription):
            let resolvedColor = colorDescription.map {
                UIColor(red: CGFloat($0.r), green: CGFloat($0.g),
                        blue: CGFloat($0.b), alpha: CGFloat($0.a))
            } ?? UIColor(
                red: CGFloat(theme.colors.accent.r),
                green: CGFloat(theme.colors.accent.g),
                blue: CGFloat(theme.colors.accent.b),
                alpha: CGFloat(theme.colors.accent.a)
            )
            backgroundColor = resolvedColor
            startDisplayLink()

        case .solid(let colorDescription):
            let resolvedColor = colorDescription.map {
                UIColor(red: CGFloat($0.r), green: CGFloat($0.g),
                        blue: CGFloat($0.b), alpha: CGFloat($0.a))
            } ?? UIColor(
                red: CGFloat(theme.colors.accent.r),
                green: CGFloat(theme.colors.accent.g),
                blue: CGFloat(theme.colors.accent.b),
                alpha: CGFloat(theme.colors.accent.a)
            )
            backgroundColor = resolvedColor
            alpha = 1.0

        case .none:
            alpha = 0.0
        }
    }

    // MARK: - Intrinsic size

    override var intrinsicContentSize: CGSize {
        // A 2-pt wide bar at the current body text cap height.
        CGSize(width: 2, height: 18)
    }

    // MARK: - Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else if case .blinking = style {
            startDisplayLink()
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Display link

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Called every frame by the display link.
    @objc private func tick(_ link: CADisplayLink) {
        frameCount += 1
        // Derive the display refresh rate from the actual frame interval.
        // targetTimestamp - timestamp gives the duration of one frame.
        // We target a 2 Hz blink: one half-period = fps / 2 frames.
        let fps: Double
        let interval = link.targetTimestamp - link.timestamp
        if interval > 0 {
            fps = (1.0 / interval).rounded()
        } else {
            fps = 60.0
        }
        let threshold = max(Int(fps / 2.0), 1)
        if frameCount >= threshold {
            frameCount = 0
            blinkPhase.toggle()
            alpha = blinkPhase ? 1.0 : 0.0
        }
    }
}
