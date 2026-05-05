// MarkdownToken.swift
// StreamDownCore — pure Swift, no UIKit/SwiftUI/AppKit

// MARK: - Inline span types

public struct EmphasisToken: Sendable, Equatable {
    public let children: [InlineToken]
    public init(children: [InlineToken]) { self.children = children }
}

public struct StrongToken: Sendable, Equatable {
    public let children: [InlineToken]
    public init(children: [InlineToken]) { self.children = children }
}

public struct StrikethroughToken: Sendable, Equatable {
    public let children: [InlineToken]
    public init(children: [InlineToken]) { self.children = children }
}

public struct CodeSpanToken: Sendable, Equatable {
    public let code: String
    public init(code: String) { self.code = code }
}

public struct LinkToken: Sendable, Equatable {
    public let href: String
    public let title: String?
    public let children: [InlineToken]
    public init(href: String, title: String? = nil, children: [InlineToken]) {
        self.href = href
        self.title = title
        self.children = children
    }
}

public struct ImageToken: Sendable, Equatable {
    public let src: String
    public let alt: String
    public let title: String?
    public init(src: String, alt: String, title: String? = nil) {
        self.src = src
        self.alt = alt
        self.title = title
    }
}

public struct AutolinkToken: Sendable, Equatable {
    public let url: String
    public let isEmail: Bool
    public init(url: String, isEmail: Bool) {
        self.url = url
        self.isEmail = isEmail
    }
}

public struct TaskCheckboxToken: Sendable, Equatable {
    public let isChecked: Bool
    public init(isChecked: Bool) { self.isChecked = isChecked }
}

// MARK: - Inline token container

/// Flat representation of inline (span-level) content.
public indirect enum InlineToken: Sendable, Equatable {
    case text(String)
    case softBreak
    case hardBreak
    case emphasis(EmphasisToken)
    case strong(StrongToken)
    case strikethrough(StrikethroughToken)
    case codeSpan(CodeSpanToken)
    case link(LinkToken)
    case image(ImageToken)
    case autolink(AutolinkToken)
    case taskCheckbox(TaskCheckboxToken)
    case html(String)
}

// MARK: - Block-level associated types

public struct HeadingToken: Sendable, Equatable {
    /// 1–6
    public let level: Int
    public let children: [InlineToken]
    public let anchor: String?
    public init(level: Int, children: [InlineToken], anchor: String? = nil) {
        self.level = level
        self.children = children
        self.anchor = anchor
    }
}

public struct ParagraphToken: Sendable, Equatable {
    public let children: [InlineToken]
    public init(children: [InlineToken]) { self.children = children }
}

public struct CodeBlockToken: Sendable, Equatable {
    public let language: String?
    public let code: String
    /// Optional info string beyond the language tag (e.g. filename)
    public let meta: String?
    public init(language: String? = nil, code: String, meta: String? = nil) {
        self.language = language
        self.code = code
        self.meta = meta
    }
}

public struct BlockquoteToken: Sendable, Equatable {
    public let children: [MarkdownToken]
    public init(children: [MarkdownToken]) { self.children = children }
}

public enum ListKind: Sendable, Equatable {
    case ordered(start: Int)
    case unordered
    case task
}

public struct ListItemToken: Sendable, Equatable {
    public let children: [MarkdownToken]
    /// Non-nil only when the list kind is `.task`.
    public let checkbox: TaskCheckboxToken?
    public let isLoose: Bool
    public init(children: [MarkdownToken], checkbox: TaskCheckboxToken? = nil, isLoose: Bool = false) {
        self.children = children
        self.checkbox = checkbox
        self.isLoose = isLoose
    }
}

public struct ListToken: Sendable, Equatable {
    public let kind: ListKind
    public let items: [ListItemToken]
    public let isLoose: Bool
    public init(kind: ListKind, items: [ListItemToken], isLoose: Bool = false) {
        self.kind = kind
        self.items = items
        self.isLoose = isLoose
    }
}

public enum ColumnAlignment: Sendable, Equatable {
    case none
    case left
    case center
    case right
}

public struct TableCellToken: Sendable, Equatable {
    public let children: [InlineToken]
    public let alignment: ColumnAlignment
    public let isHeader: Bool
    public init(children: [InlineToken], alignment: ColumnAlignment = .none, isHeader: Bool = false) {
        self.children = children
        self.alignment = alignment
        self.isHeader = isHeader
    }
}

public struct TableRowToken: Sendable, Equatable {
    public let cells: [TableCellToken]
    public let isHeader: Bool
    public init(cells: [TableCellToken], isHeader: Bool = false) {
        self.cells = cells
        self.isHeader = isHeader
    }
}

public struct TableToken: Sendable, Equatable {
    public let headers: TableRowToken
    public let rows: [TableRowToken]
    public let alignments: [ColumnAlignment]
    public init(headers: TableRowToken, rows: [TableRowToken], alignments: [ColumnAlignment]) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
    }
}

// MARK: - Partial / streaming helpers

public enum PartialBlockKind: Sendable, Equatable {
    case heading
    case paragraph
    case codeBlock
    case blockquote
    case list
    case table
    case unknown
}

/// Represents an incomplete (mid-stream) token that has not yet been finalised.
public struct PartialToken: Sendable, Equatable {
    public let kind: PartialBlockKind
    /// Raw accumulated text so far.
    public let rawText: String
    /// Any already-resolved children (e.g. complete lines in a code block).
    public let resolvedChildren: [MarkdownToken]
    public init(kind: PartialBlockKind, rawText: String, resolvedChildren: [MarkdownToken] = []) {
        self.kind = kind
        self.rawText = rawText
        self.resolvedChildren = resolvedChildren
    }
}

// MARK: - Top-level token enum

public enum MarkdownToken: Sendable, Equatable {
    // Block tokens
    case heading(HeadingToken)
    case paragraph(ParagraphToken)
    case codeBlock(CodeBlockToken)
    case blockquote(BlockquoteToken)
    case list(ListToken)
    case table(TableToken)
    case thematicBreak
    case htmlBlock(String)

    // Inline tokens promoted to block level for convenience
    case inlineToken(InlineToken)

    // Streaming / partial state
    case partial(PartialToken)

    // Cursor sentinel — rendered as a blinking cursor by the UI layer
    case cursor
}
