// StreamDownDiagram.swift
// StreamDownDiagram — Mermaid diagram renderer for fenced `mermaid` code blocks.

import SwiftUI
import UIKit
import WebKit
import StreamDownCore
import StreamDownUI
import StreamDownUIKit

// MARK: - Mermaid HTML template

/// Builds the HTML page that initializes Mermaid and renders the diagram.
///
/// Resource resolution order:
///   1. Bundled `mermaid.min.js` inside the module resources at `mermaid/`.
///   2. CDN fallback for development / when the file is not yet bundled.
private func mermaidHTML(for source: String) -> String {
    // Escape the source so it is safe to embed inside a JS template literal.
    let escaped = source
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`",  with: "\\`")
        .replacingOccurrences(of: "$",  with: "\\$")

    let scriptTag: String
    if let jsURL = Bundle.module.url(forResource: "mermaid.min", withExtension: "js",
                                      subdirectory: "mermaid") {
        scriptTag = "<script src=\"\(jsURL.absoluteString)\"></script>"
    } else {
        // CDN fallback — usable during development when resources are not bundled.
        scriptTag = "<script src=\"https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js\"></script>"
    }

    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \(scriptTag)
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body { background: transparent; overflow: hidden; }
      #diagram { padding: 8px; }
      .mermaid svg { max-width: 100%; }
    </style>
    </head>
    <body>
    <div id="diagram" class="mermaid">\(escaped)</div>
    <script>
    mermaid.initialize({ startOnLoad: false, theme: 'default' });

    async function render() {
      try {
        const { svg } = await mermaid.render('mermaid-svg', `\(escaped)`);
        document.getElementById('diagram').innerHTML = svg;
      } catch (e) {
        document.getElementById('diagram').innerText = 'Diagram error: ' + e.message;
      }
      // Report height back to native.
      var h = document.body.scrollHeight;
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sizeUpdate) {
        window.webkit.messageHandlers.sizeUpdate.postMessage({ height: h });
      }
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', render);
    } else {
      render();
    }
    </script>
    </body>
    </html>
    """
}

// MARK: - DiagramWebViewController

/// Hosts a `WKWebView` and relays size-update messages from Mermaid.
@MainActor
private final class DiagramWebViewController: NSObject, WKScriptMessageHandler {

    let webView: WKWebView
    var onHeightUpdate: ((CGFloat) -> Void)?

    override init() {
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        super.init()

        contentController.add(WeakHandler(target: self), name: "sizeUpdate")
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "sizeUpdate",
              let body = message.body as? [String: Any],
              let height = body["height"] as? CGFloat else { return }
        onHeightUpdate?(height)
    }
}

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: (AnyObject & WKScriptMessageHandler)?
    init(target: AnyObject & WKScriptMessageHandler) { self.target = target }
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - SwiftUI representable

private struct DiagramWebView: UIViewRepresentable {

    let source: String
    @Binding var renderedHeight: CGFloat

    func makeCoordinator() -> DiagramWebViewController {
        DiagramWebViewController()
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = context.coordinator
        controller.onHeightUpdate = { height in
            DispatchQueue.main.async { renderedHeight = max(height, 100) }
        }
        return controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(mermaidHTML(for: source), baseURL: nil)
    }
}

// MARK: - StreamDownDiagram

/// Renders Mermaid diagrams embedded in `mermaid` fenced code blocks.
///
/// While the block is still streaming, a lightweight placeholder ("Diagram loading…")
/// is shown instead of spinning up a `WKWebView`.  Once the closing fence arrives,
/// the finalized source is handed off to Mermaid for rendering.
///
/// Usage — SwiftUI:
/// ```swift
/// StreamDownView(stream: myStream)
///     .renderer(StreamDownDiagram())
/// ```
///
/// Usage — UIKit:
/// ```swift
/// uiView.renderers = [StreamDownDiagram()]
/// ```
public final class StreamDownDiagram: SwiftUIRenderer, UIKitRenderer, @unchecked Sendable {

    // MARK: - Identity

    public let rendererIdentifier = "com.streamdown.diagram"
    public var renderPriority: Int = 10

    // MARK: - Init

    public init() {}

    // MARK: - Helpers

    private func isMermaidBlock(_ token: MarkdownToken) -> Bool {
        guard case .codeBlock(let cb) = token else { return false }
        return cb.language?.lowercased() == "mermaid"
    }

    // MARK: - StreamDownRenderer

    public func rendererWillActivate(context: RendererContext) {}

    public func canHandle(token: MarkdownToken) -> Bool {
        // Also match partial blocks so we can show the loading placeholder.
        if case .codeBlock = token { return true }
        if case .partial(let p) = token {
            return p.resolvedChildren.contains { isMermaidBlock($0) }
        }
        return false
    }

    public func willRender(token: MarkdownToken, context: RenderContext) -> RendererDecision {
        // Partial mermaid blocks → placeholder.
        if context.isPartial {
            if case .partial(let p) = token,
               p.resolvedChildren.contains(where: { isMermaidBlock($0) }) {
                return .handled
            }
            // Partial with no resolved children yet — check the raw kind.
            if case .partial(let p) = token, p.kind == .codeBlock {
                // Could become mermaid; defer until we know the language.
                return .passthrough
            }
            return .passthrough
        }
        guard isMermaidBlock(token) else { return .passthrough }
        return .handled
    }

    public func transformToken(_ token: MarkdownToken) -> MarkdownToken { token }

    // MARK: - SwiftUIRenderer

    @MainActor
    public func makeView(for token: MarkdownToken, context: RenderContext) -> AnyView? {
        // Partial → loading placeholder.
        if context.isPartial {
            return AnyView(
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Diagram loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
        }

        guard case .codeBlock(let cb) = token else { return nil }
        return AnyView(DiagramContainerView(source: cb.code))
    }

    // MARK: - UIKitRenderer

    @MainActor
    public func makeView(for token: MarkdownToken, context: RenderContext) -> UIView? {
        if context.isPartial {
            return makePlaceholderView()
        }

        guard case .codeBlock(let cb) = token else { return nil }
        return DiagramUIKitView(source: cb.code)
    }

    // MARK: - UIKit placeholder

    @MainActor
    private func makePlaceholderView() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.secondarySystemBackground
        container.layer.cornerRadius = 8
        container.layer.masksToBounds = true

        let activity = UIActivityIndicatorView(style: .medium)
        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.startAnimating()

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Diagram loading…"
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [activity, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }
}

// MARK: - SwiftUI container view

private struct DiagramContainerView: View {

    let source: String
    @State private var height: CGFloat = 100

    var body: some View {
        DiagramWebView(source: source, renderedHeight: $height)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - UIKit container view

@MainActor
private final class DiagramUIKitView: UIView {

    private let controller: DiagramWebViewController
    private var heightConstraint: NSLayoutConstraint?

    init(source: String) {
        controller = DiagramWebViewController()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 8
        layer.masksToBounds = true

        let webView = controller.webView
        addSubview(webView)

        let hc = webView.heightAnchor.constraint(equalToConstant: 100)
        heightConstraint = hc

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hc,
        ])

        controller.onHeightUpdate = { [weak self] height in
            DispatchQueue.main.async {
                guard let self else { return }
                self.heightConstraint?.constant = max(height, 100)
                self.invalidateIntrinsicContentSize()
                self.setNeedsLayout()
            }
        }

        webView.loadHTMLString(mermaidHTML(for: source), baseURL: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: heightConstraint?.constant ?? 100)
    }
}
