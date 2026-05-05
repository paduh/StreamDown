// ThemeEnvironment.swift
// StreamDownUI — SwiftUI environment keys for StreamDown rendering settings.

import SwiftUI
import StreamDownCore

// MARK: - Environment keys

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .default
}

private struct ConfigurationKey: EnvironmentKey {
    static let defaultValue: StreamDownConfiguration = .default
}

// MARK: - EnvironmentValues extensions

public extension EnvironmentValues {
    /// The active StreamDown theme used for typography, colors, and spacing.
    var streamDownTheme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    /// The active StreamDown configuration controlling streaming behavior,
    /// link safety, cursor style, and accessibility.
    var streamDownConfiguration: StreamDownConfiguration {
        get { self[ConfigurationKey.self] }
        set { self[ConfigurationKey.self] = newValue }
    }
}
