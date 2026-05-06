# StreamDown

## Project Context

StreamDown is an open-source native iOS/macOS streaming markdown renderer built for AI-generated content. It takes a stream of text deltas from any source and renders them as live, rich markdown in SwiftUI or UIKit — handling partial and incomplete markdown gracefully during streaming.

### Architecture

```
StreamDownCore   (Pure Swift — zero platform imports — Kotlin Multiplatform ready)
    MarkdownToken         All GFM token types + partial/cursor sentinels
    IncrementalMarkdownParser  Streaming block parser with PartialBlockStrategy
    InlineParser          CommonMark delimiter stack — no regex
    TextDeltaAccumulator  delta → RenderModel pipeline
    RenderModel           Versioned, immutable render snapshot
    StreamDownRenderer    Renderer protocol
    Theme                 Primitive-value theming (Double RGBA, String font names)
         ↓
    ├─→ StreamDownUI      (SwiftUI — depends on StreamDownCore)
    │       StreamDownView       Primary entry point (3 input modes)
    │       SDBlockViews         All GFM block views
    │       SwiftUIRenderer      Platform-specific renderer protocol
    │
    └─→ StreamDownUIKit   (UIKit — depends on StreamDownCore — no SwiftUI, no bridge)
            StreamDownUIView     UIView subclass — correct intrinsicContentSize
            SDInlineRenderer     NSAttributedString from token stream
            UIKitRenderer        Platform-specific renderer protocol

Optional add-ons (depend on Core + UI + UIKit):
    StreamDownCode        Syntax highlighting renderer
    StreamDownMath        LaTeX via KaTeX + WKWebView
    StreamDownDiagram     Mermaid via WKWebView
    StreamDownCJK         CJK ideographic punctuation normalization
```

### Key Directories
- `Sources/StreamDownCore/` — Parser, token types, theming, renderer protocol. **Zero platform imports.**
- `Sources/StreamDownUI/` — SwiftUI views and SwiftUI-specific renderer protocol
- `Sources/StreamDownUIKit/` — UIKit views and UIKit-specific renderer protocol
- `Sources/StreamDownCode/` — Optional syntax highlighting add-on
- `Sources/StreamDownMath/` — Optional LaTeX/KaTeX add-on
- `Sources/StreamDownDiagram/` — Optional Mermaid diagram add-on
- `Sources/StreamDownCJK/` — Optional CJK text normalization add-on
- `Sources/StreamDownTestSupport/` — Shared test helpers (mock streams, fixture builders)
- `Tests/` — Core, UI, and snapshot test suites
- `Examples/` — Self-contained example apps (StreamDownChat, StreamDownExample)

---

## Development Standards

### Platform Requirements
- **iOS**: 16.0+
- **macOS**: 13.0+
- **Swift**: 5.9+
- **Xcode**: 15+

### Critical Constraint: StreamDownCore Zero Platform Imports
`StreamDownCore` must never import platform-specific frameworks. This is **CI-enforced**.

Forbidden imports in `Sources/StreamDownCore/`:
- `SwiftUI`, `UIKit`, `AppKit`, `WatchKit`, `TVUIKit`
- `Combine`, `MapKit`, `ARKit`, `RealityKit`
- Any `#if canImport(UIKit)` / `#if os(iOS)` guards

`StreamDownCore` is the Kotlin Multiplatform portability seam. Every type is designed for mechanical translation: Swift `enum` with associated values → Kotlin `sealed class`, `struct` → `data class`, `protocol` → `interface`, `AsyncStream<String>` → `Flow<String>`.

### Concurrency
- Use `async/await` and structured concurrency (`TaskGroup`, `async let`) over unstructured tasks
- Annotate UI-bound code with `@MainActor`
- Use `actor` for shared mutable state requiring synchronization
- Use `AsyncStream<String>` as the streaming primitive — callers own cancellation via `Task`
- Add `await Task.yield()` after state mutations in tight streaming loops to give SwiftUI one render cycle per token

### Value Types and Safety
- Prefer `struct` over `class`; use `@MainActor final class` for ObservableObjects
- All public types crossing concurrency boundaries must be `Sendable`
- `RenderModel` is versioned and immutable — never mutate in place

### API Design
- Protocol-first: `StreamDownRenderer` defines behavior; concrete types implement it
- Tree-shakeable: optional add-ons (Code, Math, Diagram, CJK) import only what the app needs
- Three input modes on `StreamDownView`: stream, static markdown, binding-driven
- Modifier-style configuration: `.theme()`, `.renderer()`, `.tokenAnimation()`, `.linkSafety()`

### Naming Conventions
- Types/Protocols: `UpperCamelCase` — prefix with `SD` for internal UIKit helpers
- Methods: verb phrases for mutations (`beginStreaming`, `reset`), noun phrases for accessors
- Boolean properties: `is`, `has`, `should` prefixes
- Test helpers: `Mock*` prefix for mock implementations

---

## Workflow

### Verification Commands
```bash
swift build                                   # Build all targets
swift test                                    # Run all tests
swift test --filter StreamDownCoreTests       # Run specific test target
swift build --target StreamDownCore           # Build a single target
swift package dump-package                    # Validate Package.swift
```

### Zero Platform Import Check (StreamDownCore)
```bash
grep -rE "^import (SwiftUI|UIKit|AppKit|WatchKit|Combine|MapKit|ARKit)" Sources/StreamDownCore/
# Must return no output
```

### Before Committing
1. `swift build` — no compilation errors
2. `swift test` — all tests pass
3. Zero-platform-import check passes for `StreamDownCore`
4. New public APIs have documentation comments
5. Snapshot test references updated if UI changed intentionally
6. Example apps still compile (open in Xcode and build)

### Branch Naming
- `feature/incremental-table-parser`
- `fix/cursor-blink-memory-leak`
- `refactor/render-model-versioning`
- `docs/docc-streamdownview`

---

## Technical Guidelines

### Parser Design
- `IncrementalMarkdownParser` processes deltas one block at a time using `PartialBlockStrategy` per block type
- Each strategy must render the best possible partial view while a block is still open (e.g., unclosed ` ``` ` renders as plain monospace, not broken)
- `InlineParser` uses a CommonMark delimiter stack — no regex
- All parser types live in `StreamDownCore` with zero platform imports

### Rendering Pipeline
```
AsyncStream<String>
    → TextDeltaAccumulator   (appends delta, calls parser)
    → IncrementalMarkdownParser  (emits RenderModel)
    → StreamDownView / StreamDownUIView  (drives UI)
```

`RenderModel` is versioned. UI layers diff versions and update only changed blocks.

### Renderer System
- Conform to `StreamDownRenderer` (and `SwiftUIRenderer` / `UIKitRenderer`) to handle custom token types
- Set `renderPriority` to control ordering — built-in renderers use priority 0–10
- `canHandle(token:)` gates rendering; `willRender(token:)` returns `.handled` or `.passthrough`
- Register via `.renderer(MyRenderer())` view modifier

### Theming
- `Theme` uses only primitive value types (`Double`, `String`) so it is `Sendable` and KMP-portable
- `ColorDescription` stores RGBA as Doubles — resolved to platform colors at the view layer
- Dark mode: SwiftUI resolves from `@Environment(\.colorScheme)`; UIKit from `traitCollectionDidChange`
- Built-in presets: `.default`, `.github`, `.minimal`, `.dark`

### Link Safety
- Default policy shows a confirmation sheet before opening any URL
- `LinkSafetyPolicy` supports: `.confirm`, custom closures, and host allowlisting
- Blocked schemes are rejected without a prompt

### Testing Strategy
- `StreamDownCoreTests` — unit tests for parser, inline parser, accumulator (pure Swift, no UI)
- `StreamDownUITests` — integration tests for view behavior
- `StreamDownSnapshotTests` — pixel-level regression tests; update references intentionally with `record: true`
- Use `StreamDownTestSupport` helpers (mock streams, fixture markdown strings) in all test targets
- Test async streaming with `AsyncStream` fixtures — no network calls in tests

---

## Sub-Agents

Use specialized agents for focused expertise. Delegate proactively:

| Agent | When to Use |
|---|---|
| `Explore` | Researching codebase before implementation, finding patterns |
| `Plan` | Designing architecture before writing code |
| `general-purpose` | Multi-step tasks spanning many files |

### Context Management
For tasks spanning the parser, renderer system, and views simultaneously, gather codebase context first with an `Explore` agent before implementing.

---

## Git Commit Guidelines
- Follow conventional commit format: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- Keep the first line under 72 characters
- Body explains *why*, not *what* — the diff shows what
- Do not include AI attribution in commit messages
