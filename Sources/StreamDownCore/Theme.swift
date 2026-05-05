// Theme.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

// MARK: - ColorDescription

/// A platform-agnostic RGBA color expressed as normalised doubles (0.0–1.0).
public struct ColorDescription: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Initialise from a hex string such as `"#FF8800"`, `"FF8800"`,
    /// `"#FF8800CC"` (with alpha) or the short forms `"#F80"` / `"F80"`.
    public init?(hex: String) {
        var raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        // Expand short form
        if raw.count == 3 || raw.count == 4 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        guard raw.count == 6 || raw.count == 8,
              let value = UInt64(raw, radix: 16) else { return nil }
        if raw.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255.0
            g = Double((value >> 16) & 0xFF) / 255.0
            b = Double((value >>  8) & 0xFF) / 255.0
            a = Double( value        & 0xFF) / 255.0
        } else {
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >>  8) & 0xFF) / 255.0
            b = Double( value        & 0xFF) / 255.0
            a = 1.0
        }
    }

    // Convenience constants
    public static let black  = ColorDescription(r: 0,     g: 0,     b: 0)
    public static let white  = ColorDescription(r: 1,     g: 1,     b: 1)
    public static let clear  = ColorDescription(r: 0,     g: 0,     b: 0,     a: 0)
}

// MARK: - SyntaxThemeName

public enum SyntaxThemeName: String, Sendable, Equatable, CaseIterable {
    case githubDark      = "github-dark"
    case githubLight     = "github-light"
    case dracula         = "dracula"
    case monokai         = "monokai"
    case nord            = "nord"
    case oneDark         = "one-dark"
    case solarizedDark   = "solarized-dark"
    case solarizedLight  = "solarized-light"
}

// MARK: - TypographyTheme

public struct TypographyTheme: Sendable, Equatable {
    /// Base body font size in points.
    public var bodySize: Double
    /// Scale factor applied per heading level (h1 = bodySize * h1Scale, etc.)
    public var h1Scale: Double
    public var h2Scale: Double
    public var h3Scale: Double
    public var h4Scale: Double
    public var h5Scale: Double
    public var h6Scale: Double
    /// Code / monospace font size.
    public var codeSize: Double
    /// Line height multiplier relative to font size.
    public var lineHeight: Double

    public init(
        bodySize: Double   = 16,
        h1Scale: Double    = 2.0,
        h2Scale: Double    = 1.5,
        h3Scale: Double    = 1.25,
        h4Scale: Double    = 1.0,
        h5Scale: Double    = 0.875,
        h6Scale: Double    = 0.85,
        codeSize: Double   = 14,
        lineHeight: Double = 1.6
    ) {
        self.bodySize   = bodySize
        self.h1Scale    = h1Scale
        self.h2Scale    = h2Scale
        self.h3Scale    = h3Scale
        self.h4Scale    = h4Scale
        self.h5Scale    = h5Scale
        self.h6Scale    = h6Scale
        self.codeSize   = codeSize
        self.lineHeight = lineHeight
    }

    public func headingSize(level: Int) -> Double {
        let scale: Double
        switch level {
        case 1: scale = h1Scale
        case 2: scale = h2Scale
        case 3: scale = h3Scale
        case 4: scale = h4Scale
        case 5: scale = h5Scale
        default: scale = h6Scale
        }
        return bodySize * scale
    }
}

// MARK: - ColorTheme

public struct ColorTheme: Sendable, Equatable {
    public var background: ColorDescription
    public var foreground: ColorDescription
    public var secondaryForeground: ColorDescription
    public var accent: ColorDescription
    public var link: ColorDescription
    public var border: ColorDescription
    public var codeForeground: ColorDescription
    public var codeBackground: ColorDescription
    public var blockquoteBorder: ColorDescription
    public var blockquoteBackground: ColorDescription
    public var tableHeaderBackground: ColorDescription
    public var tableAlternateRowBackground: ColorDescription
    public var selectionBackground: ColorDescription

    public init(
        background: ColorDescription,
        foreground: ColorDescription,
        secondaryForeground: ColorDescription,
        accent: ColorDescription,
        link: ColorDescription,
        border: ColorDescription,
        codeForeground: ColorDescription,
        codeBackground: ColorDescription,
        blockquoteBorder: ColorDescription,
        blockquoteBackground: ColorDescription,
        tableHeaderBackground: ColorDescription,
        tableAlternateRowBackground: ColorDescription,
        selectionBackground: ColorDescription
    ) {
        self.background                 = background
        self.foreground                 = foreground
        self.secondaryForeground        = secondaryForeground
        self.accent                     = accent
        self.link                       = link
        self.border                     = border
        self.codeForeground             = codeForeground
        self.codeBackground             = codeBackground
        self.blockquoteBorder           = blockquoteBorder
        self.blockquoteBackground       = blockquoteBackground
        self.tableHeaderBackground      = tableHeaderBackground
        self.tableAlternateRowBackground = tableAlternateRowBackground
        self.selectionBackground        = selectionBackground
    }

    // MARK: Static presets

    public static let light = ColorTheme(
        background:                  ColorDescription(hex: "#FFFFFF")!,
        foreground:                  ColorDescription(hex: "#24292F")!,
        secondaryForeground:         ColorDescription(hex: "#57606A")!,
        accent:                      ColorDescription(hex: "#0969DA")!,
        link:                        ColorDescription(hex: "#0969DA")!,
        border:                      ColorDescription(hex: "#D0D7DE")!,
        codeForeground:              ColorDescription(hex: "#24292F")!,
        codeBackground:              ColorDescription(hex: "#F6F8FA")!,
        blockquoteBorder:            ColorDescription(hex: "#D0D7DE")!,
        blockquoteBackground:        ColorDescription(hex: "#F6F8FA")!,
        tableHeaderBackground:       ColorDescription(hex: "#F6F8FA")!,
        tableAlternateRowBackground: ColorDescription(hex: "#FAFBFC")!,
        selectionBackground:         ColorDescription(hex: "#0969DA33")!
    )

    public static let dark = ColorTheme(
        background:                  ColorDescription(hex: "#0D1117")!,
        foreground:                  ColorDescription(hex: "#E6EDF3")!,
        secondaryForeground:         ColorDescription(hex: "#8B949E")!,
        accent:                      ColorDescription(hex: "#58A6FF")!,
        link:                        ColorDescription(hex: "#58A6FF")!,
        border:                      ColorDescription(hex: "#30363D")!,
        codeForeground:              ColorDescription(hex: "#E6EDF3")!,
        codeBackground:              ColorDescription(hex: "#161B22")!,
        blockquoteBorder:            ColorDescription(hex: "#30363D")!,
        blockquoteBackground:        ColorDescription(hex: "#161B22")!,
        tableHeaderBackground:       ColorDescription(hex: "#161B22")!,
        tableAlternateRowBackground: ColorDescription(hex: "#0D1117")!,
        selectionBackground:         ColorDescription(hex: "#58A6FF33")!
    )
}

// MARK: - SpacingTheme

public struct SpacingTheme: Sendable, Equatable {
    /// Horizontal inset for the entire content area.
    public var contentPadding: Double
    /// Vertical gap between block-level elements.
    public var blockSpacing: Double
    /// Vertical gap between list items.
    public var listItemSpacing: Double
    /// Indentation per list nesting level.
    public var listIndentation: Double
    /// Internal padding for code blocks.
    public var codePadding: Double
    /// Internal padding for blockquotes.
    public var blockquotePadding: Double
    /// Left border width for blockquotes.
    public var blockquoteBorderWidth: Double
    /// Vertical cell padding in tables.
    public var tableCellVerticalPadding: Double
    /// Horizontal cell padding in tables.
    public var tableCellHorizontalPadding: Double

    public init(
        contentPadding: Double            = 16,
        blockSpacing: Double              = 12,
        listItemSpacing: Double           = 4,
        listIndentation: Double           = 20,
        codePadding: Double               = 12,
        blockquotePadding: Double         = 12,
        blockquoteBorderWidth: Double     = 4,
        tableCellVerticalPadding: Double  = 6,
        tableCellHorizontalPadding: Double = 12
    ) {
        self.contentPadding             = contentPadding
        self.blockSpacing               = blockSpacing
        self.listItemSpacing            = listItemSpacing
        self.listIndentation            = listIndentation
        self.codePadding                = codePadding
        self.blockquotePadding          = blockquotePadding
        self.blockquoteBorderWidth      = blockquoteBorderWidth
        self.tableCellVerticalPadding   = tableCellVerticalPadding
        self.tableCellHorizontalPadding = tableCellHorizontalPadding
    }
}

// MARK: - CodeBlockTheme

public struct CodeBlockTheme: Sendable, Equatable {
    public var syntaxTheme: SyntaxThemeName
    public var cornerRadius: Double
    public var showLineNumbers: Bool
    public var lineNumberForeground: ColorDescription
    public var toolbarBackground: ColorDescription
    public var toolbarForeground: ColorDescription

    public init(
        syntaxTheme: SyntaxThemeName            = .githubLight,
        cornerRadius: Double                    = 8,
        showLineNumbers: Bool                   = false,
        lineNumberForeground: ColorDescription  = ColorDescription(hex: "#8B949E")!,
        toolbarBackground: ColorDescription     = ColorDescription(hex: "#F6F8FA")!,
        toolbarForeground: ColorDescription     = ColorDescription(hex: "#57606A")!
    ) {
        self.syntaxTheme          = syntaxTheme
        self.cornerRadius         = cornerRadius
        self.showLineNumbers      = showLineNumbers
        self.lineNumberForeground = lineNumberForeground
        self.toolbarBackground    = toolbarBackground
        self.toolbarForeground    = toolbarForeground
    }
}

// MARK: - BlockquoteTheme

public struct BlockquoteTheme: Sendable, Equatable {
    public var cornerRadius: Double
    public var iconSize: Double

    public init(
        cornerRadius: Double = 4,
        iconSize: Double     = 16
    ) {
        self.cornerRadius = cornerRadius
        self.iconSize     = iconSize
    }
}

// MARK: - Theme

public struct Theme: Sendable, Equatable {
    public var name: String
    public var typography: TypographyTheme
    public var colors: ColorTheme
    public var spacing: SpacingTheme
    public var codeBlock: CodeBlockTheme
    public var blockquote: BlockquoteTheme

    public init(
        name: String,
        typography: TypographyTheme,
        colors: ColorTheme,
        spacing: SpacingTheme,
        codeBlock: CodeBlockTheme,
        blockquote: BlockquoteTheme
    ) {
        self.name       = name
        self.typography = typography
        self.colors     = colors
        self.spacing    = spacing
        self.codeBlock  = codeBlock
        self.blockquote = blockquote
    }

    // MARK: Static presets

    /// Default theme — matches GitHub Flavored Markdown light rendering.
    public static let `default` = Theme(
        name:       "Default",
        typography: TypographyTheme(),
        colors:     .light,
        spacing:    SpacingTheme(),
        codeBlock:  CodeBlockTheme(syntaxTheme: .githubLight),
        blockquote: BlockquoteTheme()
    )

    /// GitHub-style theme, identical palette to `.default` but with slightly
    /// tighter spacing to match github.com's rendered markdown.
    public static let github = Theme(
        name:       "GitHub",
        typography: TypographyTheme(bodySize: 16, lineHeight: 1.5),
        colors:     .light,
        spacing:    SpacingTheme(
            contentPadding:  16,
            blockSpacing:    16,
            listItemSpacing: 2,
            listIndentation: 24,
            codePadding:     16,
            blockquotePadding: 16,
            blockquoteBorderWidth: 4
        ),
        codeBlock:  CodeBlockTheme(syntaxTheme: .githubLight, cornerRadius: 6),
        blockquote: BlockquoteTheme(cornerRadius: 0)
    )

    /// Minimal / stripped-back theme with generous whitespace and no decorative chrome.
    public static let minimal = Theme(
        name:       "Minimal",
        typography: TypographyTheme(
            bodySize:   17,
            h1Scale:    1.8,
            h2Scale:    1.4,
            h3Scale:    1.2,
            lineHeight: 1.75
        ),
        colors: ColorTheme(
            background:                  ColorDescription(hex: "#FAFAFA")!,
            foreground:                  ColorDescription(hex: "#111111")!,
            secondaryForeground:         ColorDescription(hex: "#666666")!,
            accent:                      ColorDescription(hex: "#0066CC")!,
            link:                        ColorDescription(hex: "#0066CC")!,
            border:                      ColorDescription(hex: "#E5E5E5")!,
            codeForeground:              ColorDescription(hex: "#111111")!,
            codeBackground:              ColorDescription(hex: "#F0F0F0")!,
            blockquoteBorder:            ColorDescription(hex: "#CCCCCC")!,
            blockquoteBackground:        ColorDescription(hex: "#F5F5F5")!,
            tableHeaderBackground:       ColorDescription(hex: "#F0F0F0")!,
            tableAlternateRowBackground: ColorDescription(hex: "#FAFAFA")!,
            selectionBackground:         ColorDescription(hex: "#0066CC22")!
        ),
        spacing: SpacingTheme(
            contentPadding:  24,
            blockSpacing:    20,
            listItemSpacing: 6,
            listIndentation: 22,
            codePadding:     16,
            blockquotePadding: 16,
            blockquoteBorderWidth: 3
        ),
        codeBlock:  CodeBlockTheme(syntaxTheme: .githubLight, cornerRadius: 4, showLineNumbers: false),
        blockquote: BlockquoteTheme(cornerRadius: 2)
    )

    /// Dark theme mirroring GitHub dark palette.
    public static let dark = Theme(
        name:       "Dark",
        typography: TypographyTheme(),
        colors:     .dark,
        spacing:    SpacingTheme(),
        codeBlock:  CodeBlockTheme(
            syntaxTheme:          .githubDark,
            cornerRadius:         8,
            showLineNumbers:      false,
            lineNumberForeground: ColorDescription(hex: "#8B949E")!,
            toolbarBackground:    ColorDescription(hex: "#161B22")!,
            toolbarForeground:    ColorDescription(hex: "#8B949E")!
        ),
        blockquote: BlockquoteTheme()
    )
}
