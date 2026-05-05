# StreamDown

A fully-loaded native iOS streaming markdown renderer for AI-generated content.

StreamDown takes a stream of text deltas from any source and renders them as live, rich markdown — in SwiftUI or UIKit. It handles partial/incomplete markdown gracefully during streaming, which no existing iOS markdown library does.

```swift
// SwiftUI
StreamDownView(stream: myAsyncStream)
    .renderer(StreamDownCode())
    .theme(.github)

// UIKit
let view = StreamDownUIView()
view.beginStreaming(myAsyncStream)
```

---

## Why StreamDown

Every existing iOS markdown library (`swift-markdown-ui`, `Textual`, `MarkdownView`) requires complete input before it can render. LLM responses arrive token-by-token, producing syntactically incomplete markdown mid-stream — an unclosed `**bold`, a code fence with no closing ` ``` `, a table mid-row. The industry workaround is plain text during streaming and formatted markdown only after completion.

StreamDown solves this natively with an incremental parser that renders each construct as gracefully as possible while it is still arriving.

---

## Features

- **Streaming-first** — `IncrementalMarkdownParser` renders partial blocks with best-effort inline parsing at every delta
- **Full GFM** — headings, bold, italic, strikethrough, tables, task lists, code blocks, blockquotes, links, images, autolinks, horizontal rules, HTML passthrough
- **Two dedicated views** — `StreamDownView` (SwiftUI) and `StreamDownUIView` (UIKit `UIView` subclass — not a `UIHostingController` bridge)
- **Renderer system** — extend with `StreamDownRenderer` conformances, tree-shakeable optional packages
- **Theming** — `Theme.default`, `.github`, `.minimal`, `.dark` with full color and typography control
- **Link safety** — confirm modal before navigation, blocked schemes, allowlist support
- **Code blocks** — language label, copy button, download, line numbers, stream-aware syntax highlighting
- **Accessibility** — VoiceOver announcements at adaptive rate, heading rotor, custom actions
- **Kotlin-ready** — `StreamDownCore` has zero platform imports; designed for Kotlin Multiplatform portability

---

## Requirements

- iOS 16+ / macOS 13+
- Swift 5.9+
- Xcode 15+

---

## Installation

### Swift Package Manager

Add StreamDown to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/paduh/StreamDown", from: "0.1.0")
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

### Choosing what to import

| Import | What you get |
|---|---|
| `StreamDown` | SwiftUI `StreamDownView` + core parser |
| `StreamDownNative` | UIKit `StreamDownUIView` + core parser |
| `StreamDownCore` | Parser and types only — no UI (for KMP / server-side Swift) |
| `StreamDownCode` | Syntax highlighting renderer (add-on) |
| `StreamDownMath` | LaTeX / KaTeX renderer (add-on) |
| `StreamDownDiagram` | Mermaid diagram renderer (add-on) |
| `StreamDownCJK` | CJK ideographic punctuation normalization (add-on) |

---

## Quick Start

### SwiftUI

```swift
import SwiftUI
import StreamDown

struct ContentView: View {
    // Provide any AsyncStream<String> — from URLSession SSE, a local model, or a test fixture
    let stream: AsyncStream<String>

    var body: some View {
        StreamDownView(stream: stream)
    }
}
```

With renderers and theming:

```swift
import StreamDown
import StreamDownCode
import StreamDownMath

StreamDownView(stream: stream)
    .renderer(StreamDownCode())
    .renderer(StreamDownMath())
    .theme(.github)
    .linkSafety(.default)       // shows URL confirmation before opening
    .cursor(.blinking(color: nil))
    .tokenAnimation(.fadeIn(duration: 0.15))
```

Static markdown (no streaming):

```swift
StreamDownView(markdown: "# Hello\n\nThis is **bold** and *italic*.")
```

Binding-driven (you manage the text):

```swift
@State private var text = ""
@State private var streaming = true

StreamDownView(text: $text, isStreaming: streaming)
```

### UIKit

```swift
import UIKit
import StreamDownNative

final class ViewController: UIViewController {
    private let markdownView = StreamDownUIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(markdownView)
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            markdownView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            markdownView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        markdownView.delegate = self
        markdownView.beginStreaming(myStream)
    }
}

extension ViewController: StreamDownUIViewDelegate {
    func streamDownView(_ view: StreamDownUIView, didUpdateContentHeight height: CGFloat) {
        // Update your scroll view content size or constraint here
    }
    func streamDownView(_ view: StreamDownUIView, didFinishStreaming fullText: String) {
        print("Done: \(fullText.count) characters")
    }
}
```

### UICollectionViewCell embedding

```swift
final class MessageCell: UICollectionViewCell {
    private let markdownView = StreamDownUIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(markdownView)
        // constrain to contentView edges...
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

Self-sizing cell height works automatically — `StreamDownUIView` has a correct `intrinsicContentSize` that updates via `invalidateIntrinsicContentSize()` on every `RenderModel` version change. No `UIHostingController` required.

---

## Connecting an LLM Stream

StreamDown is agnostic about where deltas come from. Here is a minimal example connecting it to the Anthropic Messages API via `URLSession`:

```swift
func makeAnthropicStream(prompt: String, apiKey: String) -> AsyncStream<String> {
    AsyncStream { continuation in
        Task {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try! JSONSerialization.data(withJSONObject: [
                "model": "claude-opus-4-6",
                "max_tokens": 1024,
                "stream": true,
                "messages": [["role": "user", "content": prompt]]
            ])

            let (bytes, _) = try! await URLSession.shared.bytes(for: request)
            for try await line in bytes.lines {
                guard line.hasPrefix("data: "),
                      let data = line.dropFirst(6).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String,
                      type == "content_block_delta",
                      let delta = (json["delta"] as? [String: Any])?["text"] as? String
                else { continue }
                continuation.yield(delta)
            }
            continuation.finish()
        }
    }
}
```

---

## Optional Renderers

Renderers are separately importable packages. Import only what your app needs.

### Syntax Highlighting

```swift
import StreamDownCode

StreamDownView(stream: stream)
    .renderer(StreamDownCode(theme: .githubDark))
```

Supported syntax themes: `githubDark`, `githubLight`, `dracula`, `monokai`, `nord`, `oneDark`, `solarizedDark`, `solarizedLight`.

Highlighting is **deferred until the code block closes** — partial code renders as plain monospace to avoid mid-token colour artifacts.

### LaTeX Math

```swift
import StreamDownMath

StreamDownView(stream: stream)
    .renderer(StreamDownMath())
```

Handles fenced code blocks with `language: "math"` or `"latex"` and inline `$...$` delimiters. Renders via WKWebView with bundled KaTeX (CDN fallback during development).

### Mermaid Diagrams

```swift
import StreamDownDiagram

StreamDownView(stream: stream)
    .renderer(StreamDownDiagram())
```

Handles fenced code blocks with `language: "mermaid"`. Shows a placeholder while the block is still streaming, renders the diagram on close. Supports flowcharts, sequence diagrams, Gantt charts, ER diagrams.

### CJK Text

```swift
import StreamDownCJK

StreamDownView(stream: stream)
    .renderer(StreamDownCJK())
```

Normalizes CJK ideographic punctuation and corrects kerning at CJK–Latin boundaries for apps targeting Japanese, Chinese, or Korean markets.

---

## Theming

```swift
// Built-in presets
StreamDownView(stream: stream).theme(.github)
StreamDownView(stream: stream).theme(.dark)
StreamDownView(stream: stream).theme(.minimal)

// Custom theme
var custom = Theme.default
custom.colors.linkColor = ColorDescription(hex: 0xFF6B6B)
custom.typography.baseSizePoints = 16
custom.codeBlock.showLineNumbers = true
custom.codeBlock.syntaxTheme = .dracula

StreamDownView(stream: stream).theme(custom)
```

Dark mode is handled automatically — `ColorTheme` has `.light` and `.dark` variants resolved from `@Environment(\.colorScheme)` in SwiftUI and `traitCollectionDidChange` in UIKit.

---

## Building a Custom Renderer

Conform to `StreamDownRenderer` (and optionally `SwiftUIRenderer` / `UIKitRenderer`) to handle any token type:

```swift
import StreamDownCore
import StreamDownUI

final class AlertBoxRenderer: SwiftUIRenderer {
    let rendererIdentifier = "com.myapp.alertbox"
    let renderPriority = 20

    // Handle blockquotes that start with "> ⚠️"
    func canHandle(token: MarkdownToken) -> Bool {
        guard case .blockquote(let t) = token,
              case .text(let s) = t.content.first else { return false }
        return s.hasPrefix("⚠️")
    }

    @MainActor
    func makeView(for token: MarkdownToken, context: RenderContext) -> AnyView? {
        guard case .blockquote(let t) = token else { return nil }
        return AnyView(
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                // render t.content inline...
            }
            .padding()
            .background(.yellow.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
    }

    func willRender(token: MarkdownToken, context: RenderContext) -> RendererDecision { .handled }
    func transformToken(_ token: MarkdownToken) -> MarkdownToken { token }
    func rendererWillActivate(context: RendererContext) {}
}

// Register
StreamDownView(stream: stream)
    .renderer(AlertBoxRenderer())
```

---

## Link Safety

```swift
// Default: confirmation sheet before opening any link
StreamDownView(stream: stream)
    .linkSafety(.default)

// Strict: confirmation + restrict to allowed hosts
StreamDownView(stream: stream)
    .linkSafety(LinkSafetyPolicy(
        mode: .confirm,
        allowedHosts: ["docs.myapp.com", "support.myapp.com"]
    ))

// Permissive: open immediately
StreamDownView(stream: stream)
    .linkSafety(.permissive)

// Custom
StreamDownView(stream: stream)
    .linkSafety(LinkSafetyPolicy(mode: .custom { url in
        url.host == "trusted.example.com" ? .open : .confirm
    }))
```

---

## Architecture

```
StreamDownCore          Pure Swift — zero platform imports — Kotlin Multiplatform ready
    MarkdownToken           All GFM token types + partial/cursor sentinels
    IncrementalMarkdownParser   Streaming block parser with PartialBlockStrategy per block
    InlineParser            CommonMark delimiter stack — no regex
    TextDeltaAccumulator    delta → RenderModel pipeline
    RenderModel             Versioned, immutable render snapshot
    StreamDownRenderer      Renderer protocol
    Theme                   Primitive-value theming (Double RGBA, String font names)

StreamDownUI            SwiftUI — depends on StreamDownCore
    StreamDownView          Primary entry point (3 input modes)
    SDBlockViews            All GFM block views
    SwiftUIRenderer         Platform-specific renderer protocol

StreamDownUIKit         UIKit — depends on StreamDownCore (no SwiftUI, no bridge)
    StreamDownUIView        UIView subclass — correct intrinsicContentSize, scroll KVO
    SDInlineRenderer        NSAttributedString from token stream
    SDUKBlockViews          Non-scrolling UITextView for all text content
    UIKitRenderer           Platform-specific renderer protocol

StreamDownCode          Optional — syntax highlighting
StreamDownMath          Optional — LaTeX via KaTeX + WKWebView
StreamDownDiagram       Optional — Mermaid via WKWebView
StreamDownCJK           Optional — CJK text normalization
```

`StreamDownCore` is the Kotlin portability seam. Every type is designed for mechanical translation: Swift `enum` with associated values → Kotlin `sealed class`, `struct` → `data class`, `protocol` → `interface`, `AsyncStream<String>` → `Flow<String>`.

---

## Roadmap

- [x] Phase 0 — Package structure, `MarkdownToken` API surface
- [x] Phase 1 — `IncrementalMarkdownParser`, `InlineParser`, `TextDeltaAccumulator`
- [x] Phase 2 — `StreamDownView` (SwiftUI), all GFM block views
- [x] Phase 3 — `StreamDownUIView` (UIKit), `SDInlineRenderer`
- [ ] Phase 4 — Theming audit, VoiceOver user review, accessibility test suite
- [ ] Phase 5 — `CodeBlockView` polish, 20-grammar `StreamDownCode`
- [ ] Phase 6 — `StreamDownMath`, `StreamDownDiagram`, `StreamDownCJK` hardening
- [ ] Phase 7 — DocC documentation, performance benchmarks, v1.0.0

---

## Contributing

Pull requests are welcome. For significant changes please open an issue first to discuss the approach.

All contributions to `StreamDownCore` must pass the zero-platform-import check (CI enforced). All new public API requires DocC documentation. Snapshot test references must be updated when UI changes are intentional.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
