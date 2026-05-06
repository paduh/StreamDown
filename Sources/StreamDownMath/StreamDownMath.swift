// StreamDownMath.swift
// StreamDownMath — LaTeX/KaTeX math renderer for fenced math/latex code blocks.

import SwiftUI
import UIKit
import WebKit
import StreamDownCore
import StreamDownUI
import StreamDownUIKit

// MARK: - KaTeX HTML template

/// Produces the HTML page that loads KaTeX and renders a LaTeX expression.
///
/// Resolution order:
///   1. Bundled `katex.min.js` + `katex.min.css` in the module resources.
///   2. CDN fallback when no bundle resources are found (development / simulator).
private func katexHTML(for latex: String, displayMode: Bool) -> String {
    // Escape backslashes and backticks for safe JS embedding.
    let escaped = latex
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`",  with: "\\`")
        .replacingOccurrences(of: "'",  with: "\\'")

    // Attempt to locate bundled KaTeX resources.
    let bundleBase: String
    if let jsURL = Bundle.module.url(forResource: "katex.min", withExtension: "js",
                                     subdirectory: "katex"),
       let cssURL = Bundle.module.url(forResource: "katex.min", withExtension: "css",
                                      subdirectory: "katex") {
        bundleBase = """
        <link rel="stylesheet" href="\(cssURL.absoluteString)">
        <script src="\(jsURL.absoluteString)"></script>
        """
    } else {
        // CDN fallback — usable during development.
        bundleBase = """
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
        """
    }

    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \(bundleBase)
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body { background: transparent; overflow: hidden; }
      #math { padding: 8px; }
    </style>
    </head>
    <body>
    <div id="math"></div>
    <script>
    function render() {
      try {
        katex.render('\(escaped)', document.getElementById('math'), {
          displayMode: \(displayMode ? "true" : "false"),
          throwOnError: false
        });
      } catch(e) {
        document.getElementById('math').innerText = '\(escaped)';
      }
      // Post rendered height to native.
      var h = document.body.scrollHeight;
      window.webkit.messageHandlers.sizeUpdate.postMessage({ height: h });
    }
    if (typeof katex !== 'undefined') {
      render();
    } else {
      document.addEventListener('DOMContentLoaded', render);
    }
    </script>
    </body>
    </html>
    """
}

// MARK: - MathWebViewController (shared WKWebView host)

/// Hosts a `WKWebView` and handles size-update messages from KaTeX.
@MainActor
private final class MathWebViewController: NSObject, WKScriptMessageHandler {

    let webView: WKWebView
    var onHeightUpdate: ((CGFloat) -> Void)?

    override init() {
        let contentController = WKUserContentController()
        let userConfig = WKWebViewConfiguration()
        userConfig.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: userConfig)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        super.init()
        contentController.add(WeakScriptHandler(target: self), name: "sizeUpdate")
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

/// Weak-reference wrapper for `WKScriptMessageHandler` to prevent retain cycles.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (AnyObject & WKScriptMessageHandler)?

    init(target: AnyObject & WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - SwiftUI UIViewRepresentable wrapper

/// A SwiftUI view that wraps a `WKWebView` rendering a KaTeX expression.
private struct MathWebView: UIViewRepresentable {

    let latex: String
    let displayMode: Bool

    @Binding var renderedHeight: CGFloat

    func makeCoordinator() -> MathWebViewController {
        MathWebViewController()
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = context.coordinator
        controller.onHeightUpdate = { height in
            DispatchQueue.main.async {
                renderedHeight = max(height, 44)
            }
        }
        return controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let html = katexHTML(for: latex, displayMode: displayMode)
        uiView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - StreamDownMath

/// Renders LaTeX math expressions from `math` or `latex` fenced code blocks.
///
/// Usage — add to a `StreamDownView`:
/// ```swift
/// StreamDownView(stream: myStream)
///     .renderer(StreamDownMath())
/// ```
///
/// Or register with a `StreamDownUIView`:
/// ```swift
/// uiView.renderers = [StreamDownMath()]
/// ```
public final class StreamDownMath: SwiftUIRenderer, UIKitRenderer, @unchecked Sendable {

    // MARK: - Identity

    public let rendererIdentifier = "com.streamdown.math"
    public var renderPriority: Int = 10

    // MARK: - Init

    public init() {}

    // MARK: - Helpers

    private func isMathBlock(_ token: MarkdownToken) -> Bool {
        guard case .codeBlock(let cb) = token else { return false }
        let lang = cb.language?.lowercased() ?? ""
        return lang == "math" || lang == "latex"
    }

    // MARK: - StreamDownRenderer

    public func rendererWillActivate(context: RendererContext) {}

    public func canHandle(token: MarkdownToken) -> Bool {
        isMathBlock(token)
    }

    public func willRender(token: MarkdownToken, context: RenderContext) -> RendererDecision {
        // Only handle finalized code blocks (isPartial == false).
        if context.isPartial { return .passthrough }
        guard isMathBlock(token) else { return .passthrough }
        return .handled
    }

    public func transformToken(_ token: MarkdownToken) -> MarkdownToken { token }

    // MARK: - SwiftUIRenderer

    @MainActor
    public func makeView(for token: MarkdownToken, context: RenderContext) -> AnyView? {
        guard !context.isPartial,
              case .codeBlock(let cb) = token else { return nil }

        return AnyView(MathContainerView(latex: cb.code))
    }

    // MARK: - UIKitRenderer

    @MainActor
    public func makeView(for token: MarkdownToken, context: RenderContext) -> UIView? {
        guard !context.isPartial,
              case .codeBlock(let cb) = token else { return nil }

        return MathUIKitView(latex: cb.code)
    }
}

// MARK: - SwiftUI container

private struct MathContainerView: View {

    let latex: String
    @State private var height: CGFloat = 44

    var body: some View {
        MathWebView(latex: latex, displayMode: true, renderedHeight: $height)
            .frame(height: height)
            .background(Color(.systemBackground).opacity(0.01))
    }
}

// MARK: - UIKit container

@MainActor
private final class MathUIKitView: UIView {

    private let controller: MathWebViewController
    private var heightConstraint: NSLayoutConstraint?

    init(latex: String) {
        controller = MathWebViewController()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let webView = controller.webView
        addSubview(webView)

        let hc = webView.heightAnchor.constraint(equalToConstant: 44)
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
                self.heightConstraint?.constant = max(height, 44)
                self.invalidateIntrinsicContentSize()
                self.setNeedsLayout()
            }
        }

        let html = katexHTML(for: latex, displayMode: true)
        webView.loadHTMLString(html, baseURL: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: heightConstraint?.constant ?? 44)
    }
}
