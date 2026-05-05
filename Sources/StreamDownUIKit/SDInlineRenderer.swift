// SDInlineRenderer.swift
// StreamDownUIKit — UIKit rendering layer for StreamDown

import UIKit
import StreamDownCore

// MARK: - SDInlineRenderer

/// Converts a flat array of `InlineToken` values into an `NSAttributedString`
/// using UIKit-native font and color attributes.
///
/// This type is stateless — all methods are static.
enum SDInlineRenderer {

    // MARK: - Public API

    /// Build an `NSAttributedString` from an array of inline tokens.
    ///
    /// - Parameters:
    ///   - tokens: The inline tokens to render.
    ///   - theme: The active `Theme` (supplies font sizes, colors, etc.).
    ///   - traitCollection: Used to resolve dynamic colors for light/dark mode.
    /// - Returns: A fully attributed string ready to assign to a `UITextView`.
    static func attributedString(
        from tokens: [InlineToken],
        theme: Theme,
        traitCollection: UITraitCollection
    ) -> NSAttributedString {
        let base = baseAttributes(theme: theme, traitCollection: traitCollection)
        let result = NSMutableAttributedString()
        for token in tokens {
            result.append(render(token: token, theme: theme,
                                 traitCollection: traitCollection,
                                 baseAttributes: base))
        }
        return result
    }

    /// Build the base paragraph + font attributes used for body text.
    static func baseAttributes(
        theme: Theme,
        traitCollection: UITraitCollection
    ) -> [NSAttributedString.Key: Any] {
        let bodyFont = UIFont.systemFont(ofSize: CGFloat(theme.typography.bodySize),
                                         weight: .regular)
        let foreground = uiColor(from: theme.colors.foreground,
                                 traitCollection: traitCollection)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = CGFloat(theme.typography.lineHeight)
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .font: bodyFont,
            .foregroundColor: foreground,
            .paragraphStyle: paragraphStyle
        ]
    }

    // MARK: - Private helpers

    /// Recursively render a single `InlineToken` into an attributed string.
    private static func render(
        token: InlineToken,
        theme: Theme,
        traitCollection: UITraitCollection,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        switch token {

        case .text(let string):
            return NSAttributedString(string: string, attributes: baseAttributes)

        case .softBreak:
            // A soft break becomes a space between words.
            return NSAttributedString(string: " ", attributes: baseAttributes)

        case .hardBreak:
            return NSAttributedString(string: "\n", attributes: baseAttributes)

        case .emphasis(let emphasisToken):
            var attrs = baseAttributes
            if let existingFont = attrs[.font] as? UIFont {
                attrs[.font] = UIFont.italicSystemFont(ofSize: existingFont.pointSize)
            }
            return renderChildren(emphasisToken.children,
                                  theme: theme,
                                  traitCollection: traitCollection,
                                  attributes: attrs)

        case .strong(let strongToken):
            var attrs = baseAttributes
            if let existingFont = attrs[.font] as? UIFont {
                attrs[.font] = UIFont.boldSystemFont(ofSize: existingFont.pointSize)
            }
            return renderChildren(strongToken.children,
                                  theme: theme,
                                  traitCollection: traitCollection,
                                  attributes: attrs)

        case .strikethrough(let strikeToken):
            var attrs = baseAttributes
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            return renderChildren(strikeToken.children,
                                  theme: theme,
                                  traitCollection: traitCollection,
                                  attributes: attrs)

        case .codeSpan(let codeSpanToken):
            var attrs = baseAttributes
            attrs[.font] = UIFont.monospacedSystemFont(
                ofSize: CGFloat(theme.typography.codeSize),
                weight: .regular
            )
            attrs[.backgroundColor] = uiColor(from: theme.colors.codeBackground,
                                               traitCollection: traitCollection)
            attrs[.foregroundColor] = uiColor(from: theme.colors.codeForeground,
                                               traitCollection: traitCollection)
            return NSAttributedString(string: codeSpanToken.code, attributes: attrs)

        case .link(let linkToken):
            var attrs = baseAttributes
            if let url = URL(string: linkToken.href) {
                attrs[.link] = url
            }
            attrs[.foregroundColor] = uiColor(from: theme.colors.link,
                                               traitCollection: traitCollection)
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            return renderChildren(linkToken.children,
                                  theme: theme,
                                  traitCollection: traitCollection,
                                  attributes: attrs)

        case .image(let imageToken):
            // Render alt text as plain body text — actual image loading is out-of-scope
            // for the inline renderer.
            let altText = imageToken.alt.isEmpty ? "(image)" : imageToken.alt
            return NSAttributedString(string: altText, attributes: baseAttributes)

        case .autolink(let autolinkToken):
            var attrs = baseAttributes
            let urlString = autolinkToken.isEmail
                ? "mailto:\(autolinkToken.url)"
                : autolinkToken.url
            if let url = URL(string: urlString) {
                attrs[.link] = url
            }
            attrs[.foregroundColor] = uiColor(from: theme.colors.link,
                                               traitCollection: traitCollection)
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            return NSAttributedString(string: autolinkToken.url, attributes: attrs)

        case .taskCheckbox:
            // Task checkboxes are rendered separately at the block level;
            // return an empty string here to avoid duplication.
            return NSAttributedString()

        case .html(let rawHTML):
            // Strip tags and render plain text (HTML passthrough is not supported
            // in the UIKit layer without a WKWebView, which is out of scope).
            let stripped = rawHTML
                .replacingOccurrences(of: "<[^>]+>",
                                      with: "",
                                      options: .regularExpression)
            return NSAttributedString(string: stripped, attributes: baseAttributes)
        }
    }

    /// Render a sequence of child tokens and concatenate the results.
    private static func renderChildren(
        _ children: [InlineToken],
        theme: Theme,
        traitCollection: UITraitCollection,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            result.append(render(token: child,
                                 theme: theme,
                                 traitCollection: traitCollection,
                                 baseAttributes: attributes))
        }
        return result
    }

    // MARK: - Color resolution

    /// Convert a `ColorDescription` from the theme into a `UIColor`.
    ///
    /// The `traitCollection` parameter is provided for future use; currently
    /// `ColorDescription` is a single RGBA value with no dark/light variant.
    static func uiColor(
        from description: ColorDescription,
        traitCollection: UITraitCollection
    ) -> UIColor {
        UIColor(
            red:   CGFloat(description.r),
            green: CGFloat(description.g),
            blue:  CGFloat(description.b),
            alpha: CGFloat(description.a)
        )
    }
}

// MARK: - Heading inline renderer

extension SDInlineRenderer {

    /// Build an attributed string for heading content.
    ///
    /// - Parameters:
    ///   - tokens: The inline children of the heading token.
    ///   - level: 1–6, used to determine font size from the theme.
    ///   - theme: Active theme.
    ///   - traitCollection: Trait collection for color resolution.
    static func headingAttributedString(
        from tokens: [InlineToken],
        level: Int,
        theme: Theme,
        traitCollection: UITraitCollection
    ) -> NSAttributedString {
        let fontSize = CGFloat(theme.typography.headingSize(level: level))
        let font = UIFont.systemFont(ofSize: fontSize, weight: fontWeight(forLevel: level))
        let foreground = uiColor(from: theme.colors.foreground,
                                 traitCollection: traitCollection)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        var baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraphStyle
        ]

        // Headings h1–h2 get a slightly heavier weight; already covered above.
        // Use baseAttrs as the base for child rendering.
        let result = NSMutableAttributedString()
        for token in tokens {
            result.append(render(token: token,
                                 theme: theme,
                                 traitCollection: traitCollection,
                                 baseAttributes: baseAttrs))
        }
        return result
    }

    /// Map heading level to `UIFont.Weight`.
    private static func fontWeight(forLevel level: Int) -> UIFont.Weight {
        switch level {
        case 1: return .bold
        case 2: return .semibold
        case 3: return .medium
        default: return .regular
        }
    }
}
