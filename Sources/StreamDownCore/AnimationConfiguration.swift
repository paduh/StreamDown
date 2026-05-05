// AnimationConfiguration.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

// MARK: - CursorStyle

/// Describes how the streaming cursor should be rendered.
public enum CursorStyle: Sendable, Equatable {
    /// A blinking block or bar cursor. Pass `nil` to use the theme accent colour.
    case blinking(color: ColorDescription?)

    /// A non-blinking cursor. Pass `nil` to use the theme accent colour.
    case solid(color: ColorDescription?)

    /// No cursor is shown (useful when streaming is complete or animation is disabled).
    case none
}

// MARK: - TokenAnimation

/// Controls how each newly appended token appears on screen.
public enum TokenAnimation: Sendable, Equatable {
    /// Tokens appear instantly with no animation.
    case none

    /// Each token fades in over the given duration (in seconds).
    case fadeIn(duration: Double)

    /// Each token slides up from `distance` points below its final position
    /// over `duration` seconds, optionally fading in simultaneously.
    case slideUp(distance: Double, duration: Double)

    /// Characters appear one-by-one, emulating a typewriter effect.
    /// The speed is derived from the renderer's streaming rate.
    case typewriter
}
