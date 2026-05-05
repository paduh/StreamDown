// MarkdownFixtures.swift
// Pre-written markdown strings for each demo screen.

import Foundation

enum MarkdownFixtures {

    // MARK: - Gallery: full GFM coverage

    static let fullGFM = """
    # Heading 1
    ## Heading 2
    ### Heading 3
    #### Heading 4
    ##### Heading 5
    ###### Heading 6

    ---

    A paragraph with **bold**, *italic*, ~~strikethrough~~, `inline code`, and a [link](https://example.com "Example").

    A second paragraph with a hard break\\
    right here, and a soft break
    that continues on the same line.

    > A blockquote spanning multiple lines.
    >
    > > A nested blockquote.

    - Unordered item 1
    - Unordered item 2
        - Nested item A
        - Nested item B
    - Unordered item 3

    1. Ordered item one
    2. Ordered item two
    3. Ordered item three

    - [x] Completed task
    - [ ] Pending task
    - [x] Another done item

    | Alignment | Left | Center | Right |
    |:----------|:-----|:------:|------:|
    | Row 1     | A    |   B    |     C |
    | Row 2     | 1    |   2    |     3 |

    ```swift
    func greet(name: String) -> String {
        "Hello, \\(name)!"
    }
    ```

    ```python
    def greet(name: str) -> str:
        return f"Hello, {name}!"
    ```

    An autolink: <https://example.com> and an email: <user@example.com>

    ***

    *The end.*
    """

    // MARK: - Themes: focused showcase

    static let themeShowcase = """
    # Theme Showcase

    ## Typography Scale

    This is body text at the base font size. **Bold**, *italic*, ~~strikethrough~~, and `inline code` all adapt to the theme.

    ### Heading 3 · *italic*
    #### Heading 4

    ## Code Block

    ```swift
    let message = "Hello, StreamDown!"
    print(message)
    ```

    ## Blockquote

    > "The best way to predict the future is to invent it."
    > — Alan Kay

    ## Link & Table

    Visit [StreamDown on GitHub](https://github.com/paduh/StreamDown) for source.

    | Column A | Column B | Column C |
    |:---------|:--------:|---------:|
    | Left     | Center   | Right    |
    | Value 1  | Value 2  | Value 3  |
    """

    // MARK: - Renderers: one example per optional package

    static let renderersShowcase = """
    ## Syntax Highlighting (`StreamDownCode`)

    ```swift
    import StreamDownUI

    struct ChatView: View {
        let stream: AsyncStream<String>

        var body: some View {
            StreamDownView(stream: stream)
                .theme(.github)
                .renderer(StreamDownCode())
        }
    }
    ```

    ## LaTeX Math (`StreamDownMath`)

    Block equation:

    ```math
    E = mc^2
    ```

    ## Mermaid Diagram (`StreamDownDiagram`)

    ```mermaid
    flowchart TD
        A[Start] --> B{Streaming?}
        B -- Yes --> C[Show cursor]
        B -- No  --> D[Render complete]
        C --> E[Update model]
        D --> E
    ```
    """

    // MARK: - Custom renderer: alert boxes

    static let alertBoxFixture = """
    # Custom Renderer Demo

    Toggle the renderer on/off to compare styled callouts against plain blockquotes.

    > ⚠️ **Warning:** This action cannot be undone. Review carefully before proceeding.

    > ℹ️ **Info:** StreamDown renderers are prioritised — lower `renderPriority` wins.

    > ✅ **Success:** All tests passed. The renderer pipeline is working correctly.

    Without the renderer, these are plain `> blockquote` elements.
    """

    // MARK: - Streaming fixtures

    static let shortResponse = """
    ## Quick Answer

    **StreamDown** is a native iOS streaming markdown renderer.

    It uses `IncrementalMarkdownParser` with per-block `PartialBlockStrategy` to render \
    gracefully as tokens arrive — the first native iOS library to do so.

    Key facts:
    - iOS 16+, macOS 13+
    - Zero external dependencies
    - SwiftUI and UIKit dedicated views
    """

    static let codeHeavy = """
    # Swift Integration Examples

    ## SwiftUI — Basic

    ```swift
    import StreamDownUI

    struct ChatView: View {
        let stream: AsyncStream<String>

        var body: some View {
            StreamDownView(stream: stream)
                .theme(.github)
                .cursor(.blinking(color: nil))
                .tokenAnimation(.fadeIn(duration: 0.15))
        }
    }
    ```

    ## UIKit — Cell Embedding

    ```swift
    import StreamDownUIKit

    final class MessageCell: UICollectionViewCell {
        private let markdownView = StreamDownUIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.addSubview(markdownView)
            // Auto Layout constraints…
        }

        func configure(with stream: AsyncStream<String>) {
            markdownView.beginStreaming(stream)
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            markdownView.reset()   // cancels the stream cleanly
        }
    }
    ```

    ## Custom Renderer

    ```swift
    import StreamDownUI
    import StreamDownCore

    final class AlertBoxRenderer: SwiftUIRenderer, @unchecked Sendable {
        let rendererIdentifier = "com.myapp.alertbox"
        var renderPriority = 10

        func canHandle(token: MarkdownToken) -> Bool {
            guard case .blockquote(let bq) = token,
                  case .paragraph(let p) = bq.children.first,
                  case .text(let s) = p.children.first
            else { return false }
            return s.hasPrefix("⚠️")
        }

        @MainActor
        func makeView(for token: MarkdownToken, context: RenderContext) -> AnyView? {
            // Return your custom SwiftUI view here
            AnyView(EmptyView())
        }
    }
    ```
    """

    static let tableHeavy = """
    # StreamDown — Reference Tables

    ## Library Comparison

    | Library | Streaming | GFM | UIKit Native | iOS 16+ |
    |:--------|:---------:|:---:|:------------:|:-------:|
    | **StreamDown** | ✅ | ✅ | ✅ | ✅ |
    | swift-markdown-ui | ❌ | ✅ | ❌ | ✅ |
    | Textual | ❌ | ✅ | ❌ | ✅ |
    | MarkdownView | ❌ | Partial | ❌ | ✅ |

    ## Token Types

    | Token | Description | Partial |
    |:------|:-----------|:-------:|
    | `.heading` | h1–h6 with anchor | ✅ |
    | `.paragraph` | Text block | ✅ |
    | `.codeBlock` | Fenced + indented | ✅ |
    | `.blockquote` | Nested blocks | ✅ |
    | `.list` | Ordered, unordered, task | ✅ |
    | `.table` | GFM tables | ✅ |
    | `.thematicBreak` | Horizontal rule | — |
    | `.partial` | In-flight block | — |
    | `.cursor` | Streaming sentinel | — |

    ## Optional Packages

    | Package | Technology | Use case |
    |:--------|:-----------|:---------|
    | `StreamDownCode` | Custom tokeniser | Code output |
    | `StreamDownMath` | KaTeX + WKWebView | Math / science |
    | `StreamDownDiagram` | Mermaid + WKWebView | Architecture diagrams |
    | `StreamDownCJK` | Unicode transforms | CJK language apps |

    ## Theme Properties

    | Property | Type | Default |
    |:---------|:-----|:--------|
    | `typography.bodySize` | `Double` | `16` |
    | `typography.h1Scale` | `Double` | `2.0` |
    | `colors.foreground` | `ColorDescription` | `#24292F` |
    | `colors.link` | `ColorDescription` | `#0969DA` |
    | `spacing.blockSpacing` | `Double` | `12` |
    | `codeBlock.syntaxTheme` | `SyntaxThemeName` | `.githubLight` |
    """

    static let longDocument = """
    # StreamDown Architecture

    StreamDown is architected in layers, each with a clear single responsibility.

    ## Core Layer (`StreamDownCore`)

    The core layer is **pure Swift with zero platform imports**. This design makes it \
    portable to Kotlin Multiplatform with mechanical translation.

    ### `IncrementalMarkdownParser`

    The parser operates line-by-line, maintaining a `BlockParserState` that tracks the \
    current block type. Each line dispatches to a type-specific handler:

    - **Heading**: Detected by leading `#` symbols. Finalized immediately (single-line).
    - **Paragraph**: Accumulates lines; speculative inline parsing on each delta.
    - **Code block**: Buffers body between fences; language tag from opening fence.
    - **Blockquote**: Strips `>` prefix; delegates to a nested recursive parser instance.
    - **List**: Emits completed items immediately; the current item stays partial.
    - **Table**: Held until the separator row `|---|` arrives to confirm table intent.

    ### `InlineParser`

    Inline parsing uses a **CommonMark-compliant delimiter stack** — no regular expressions. \
    This correctly handles:

    - Nested emphasis: `***bold and italic***`
    - Escaped characters: `\\*not bold\\*`
    - Rule-of-three avoidance
    - Partial spans: unclosed delimiters rendered as plain text when `allowPartial: true`

    ### `RenderModel`

    A versioned, immutable snapshot:

    ```swift
    public struct RenderModel: Sendable, Equatable {
        public let tokens: [MarkdownToken]
        public let isStreaming: Bool
        public let version: Int
    }
    ```

    The monotonically increasing `version` lets UI layers skip stale updates.

    ## UI Layers

    ### SwiftUI (`StreamDownUI`)

    `StreamDownView` holds a `TextDeltaAccumulator` as an `@StateObject`. The accumulator \
    publishes a `RenderModel` on every delta, driving a `LazyVStack` of block views.

    The `.task(id:)` modifier cancels the stream task automatically on disappear.

    ### UIKit (`StreamDownUIKit`)

    `StreamDownUIView` is a `UIView` subclass — **not** a `UIHostingController` wrapper:

    - `UIStackView` for block layout
    - `UITextView` for text rendering with `NSAttributedString`
    - `invalidateIntrinsicContentSize()` for dynamic height
    - KVO on `parentScrollView.contentOffset` for scroll coordination

    ## Kotlin Multiplatform Portability

    `StreamDownCore` is the KMP seam:

    | Swift | Kotlin |
    |:------|:-------|
    | `enum` with associated values | `sealed class` |
    | `struct` | `data class` |
    | `protocol` | `interface` |
    | `AsyncStream<String>` | `Flow<String>` |

    ## Optional Packages

    Each optional package is tree-shakeable — import only what your app needs:

    | Package | Technology |
    |:--------|:-----------|
    | `StreamDownCode` | Custom tokeniser — 20 grammars |
    | `StreamDownMath` | KaTeX + WKWebView |
    | `StreamDownDiagram` | Mermaid + WKWebView |
    | `StreamDownCJK` | Unicode transforms |

    ---

    *StreamDown is open source under the MIT License.*
    """
}
