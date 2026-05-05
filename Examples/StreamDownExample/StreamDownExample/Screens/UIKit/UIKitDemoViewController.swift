// UIKitDemoViewController.swift
// Demonstrates StreamDownUIView in a pure UIKit context.
//
// Layout:
//  ┌────────────────────────────────┐
//  │         UIToolbar              │  ← Stream / Static / Reset buttons
//  ├────────────────────────────────┤
//  │                                │
//  │        UIScrollView            │  ← 60% of height
//  │     (StreamDownUIView)         │
//  │                                │
//  ├────────────────────────────────┤
//  │  Delegate Log (UITextView)     │  ← remaining height
//  └────────────────────────────────┘

import UIKit
import StreamDownUIKit
import StreamDownCore

final class UIKitDemoViewController: UIViewController {

    // MARK: - Subviews

    private let toolbar       = UIToolbar()
    private let scrollView    = UIScrollView()
    private let markdownView  = StreamDownUIView()
    private let logHeaderLabel = UILabel()
    private let logTextView   = UITextView()

    // MARK: - State

    private var logLines: [String] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLayout()
    }

    // MARK: - Layout

    private func buildLayout() {
        setupToolbar()
        setupScrollView()
        setupMarkdownView()
        setupLogPanel()
    }

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let stream = barItem(title: "Stream", action: #selector(didTapStream))
        let space  = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let static_ = barItem(title: "Static", action: #selector(didTapStatic))
        let space2 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let reset  = barItem(title: "Reset",  action: #selector(didTapReset))
        toolbar.items = [stream, space, static_, space2, reset]

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .systemBackground
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.55),
        ])
    }

    private func setupMarkdownView() {
        markdownView.delegate = self
        markdownView.parentScrollView = scrollView
        markdownView.autoScrollsToBottom = true
        markdownView.theme = .github

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(container)
        container.addSubview(markdownView)

        NSLayoutConstraint.activate([
            // Container fills the scroll view's content area
            container.topAnchor.constraint(equalTo: scrollView.topAnchor),
            container.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Markdown view fills the container with insets
            markdownView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            markdownView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            markdownView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
    }

    private func setupLogPanel() {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator

        logHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        logHeaderLabel.text = "DELEGATE LOG"
        logHeaderLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        logHeaderLabel.textColor = .secondaryLabel

        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.isEditable = false
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.textColor = .secondaryLabel
        logTextView.backgroundColor = UIColor.secondarySystemBackground
        logTextView.text = "Events will appear here after tapping Stream or Static."
        logTextView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        view.addSubview(divider)
        view.addSubview(logHeaderLabel)
        view.addSubview(logTextView)

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            logHeaderLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            logHeaderLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            logTextView.topAnchor.constraint(equalTo: logHeaderLabel.bottomAnchor, constant: 4),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    // MARK: - Toolbar actions

    @objc private func didTapStream() {
        markdownView.reset()
        logLines = []
        let stream = SimulatedLLMStream.stream(for: MarkdownFixtures.longDocument, tokensPerSecond: 40)
        markdownView.beginStreaming(stream)
        appendLog("beginStreaming()")
    }

    @objc private func didTapStatic() {
        markdownView.render(markdown: MarkdownFixtures.themeShowcase)
        appendLog("render(markdown:)")
    }

    @objc private func didTapReset() {
        markdownView.reset()
        logLines = []
        logTextView.text = "Events will appear here after tapping Stream or Static."
        scrollView.contentSize = .zero
    }

    // MARK: - Log helpers

    private func appendLog(_ message: String) {
        let ts = timestamp()
        logLines.append("[\(ts)] \(message)")
        logTextView.text = logLines.joined(separator: "\n")
        let end = NSRange(location: max(0, logTextView.text.count - 1), length: 0)
        logTextView.scrollRangeToVisible(end)
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    private func barItem(title: String, action: Selector) -> UIBarButtonItem {
        UIBarButtonItem(title: title, style: .plain, target: self, action: action)
    }
}

// MARK: - StreamDownUIViewDelegate

extension UIKitDemoViewController: StreamDownUIViewDelegate {

    func streamDownView(_ view: StreamDownUIView, didUpdateContentHeight height: CGFloat) {
        // Update scroll view content size to match rendered content
        scrollView.contentSize = CGSize(
            width: scrollView.bounds.width,
            height: height + 32   // 16pt inset top + bottom
        )
        appendLog("didUpdateContentHeight(\(Int(height))pt)")
    }

    func streamDownView(_ view: StreamDownUIView, didFinishStreaming fullText: String) {
        appendLog("didFinishStreaming — \(fullText.count) chars")
    }

    func streamDownView(_ view: StreamDownUIView, didTapLink url: URL) {
        appendLog("didTapLink: \(url.host ?? url.absoluteString)")
    }

    func streamDownView(_ view: StreamDownUIView, didCopyCode code: String, language: String?) {
        appendLog("didCopyCode: \(language ?? "plain") (\(code.count) chars)")
    }
}
