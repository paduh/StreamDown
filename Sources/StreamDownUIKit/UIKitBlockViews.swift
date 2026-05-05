// UIKitBlockViews.swift
// StreamDownUIKit — UIKit rendering layer for StreamDown

import UIKit
import StreamDownCore

// MARK: - Non-scrolling UITextView factory

/// Creates a `UITextView` configured for static, non-scrolling display.
private func makeStaticTextView() -> UITextView {
    let tv = UITextView()
    tv.isScrollEnabled = false
    tv.isEditable = false
    tv.isSelectable = true
    tv.backgroundColor = .clear
    tv.textContainerInset = .zero
    tv.textContainer.lineFragmentPadding = 0
    tv.translatesAutoresizingMaskIntoConstraints = false
    tv.setContentCompressionResistancePriority(.required, for: .vertical)
    tv.setContentHuggingPriority(.required, for: .vertical)
    return tv
}

// MARK: - SDUKHeadingView

/// Renders a Markdown heading (h1–h6) using a non-scrolling `UITextView`.
final class SDUKHeadingView: UIView {

    // MARK: Subviews
    private let textView = makeStaticTextView()

    // MARK: State
    private var widthConstraint: NSLayoutConstraint?

    // MARK: Init
    init(token: HeadingToken, theme: Theme, traitCollection: UITraitCollection) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        configure(token: token, theme: theme, traitCollection: traitCollection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Configuration

    func configure(token: HeadingToken, theme: Theme, traitCollection: UITraitCollection) {
        textView.attributedText = SDInlineRenderer.headingAttributedString(
            from: token.children,
            level: token.level,
            theme: theme,
            traitCollection: traitCollection
        )
        // Accessibility
        accessibilityTraits = .header
        accessibilityLabel = token.children.compactMap { inlineTokenPlainText($0) }.joined()
    }

    // MARK: Preferred width (drives height)

    var preferredWidth: CGFloat = 0 {
        didSet {
            guard preferredWidth != oldValue, preferredWidth > 0 else { return }
            widthConstraint?.isActive = false
            widthConstraint = textView.widthAnchor.constraint(equalToConstant: preferredWidth)
            widthConstraint?.isActive = true
        }
    }

    override var intrinsicContentSize: CGSize {
        let w = preferredWidth > 0 ? preferredWidth : UIView.noIntrinsicMetric
        let size = textView.sizeThatFits(CGSize(width: w, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: w, height: size.height)
    }
}

// MARK: - SDUKParagraphView

/// Renders a Markdown paragraph using a non-scrolling `UITextView`.
final class SDUKParagraphView: UIView {

    // MARK: Subviews
    let textView = makeStaticTextView()

    // MARK: State
    private var widthConstraint: NSLayoutConstraint?

    // MARK: Init
    init(tokens: [InlineToken], theme: Theme, traitCollection: UITraitCollection) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        configure(tokens: tokens, theme: theme, traitCollection: traitCollection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Configuration

    func configure(tokens: [InlineToken], theme: Theme, traitCollection: UITraitCollection) {
        textView.attributedText = SDInlineRenderer.attributedString(
            from: tokens,
            theme: theme,
            traitCollection: traitCollection
        )
    }

    // MARK: Preferred width

    var preferredWidth: CGFloat = 0 {
        didSet {
            guard preferredWidth != oldValue, preferredWidth > 0 else { return }
            widthConstraint?.isActive = false
            widthConstraint = textView.widthAnchor.constraint(equalToConstant: preferredWidth)
            widthConstraint?.isActive = true
        }
    }

    override var intrinsicContentSize: CGSize {
        let w = preferredWidth > 0 ? preferredWidth : UIView.noIntrinsicMetric
        let size = textView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: w, height: size.height)
    }
}

// MARK: - SDUKCodeBlockView

/// Renders a fenced or indented code block.
///
/// Layout:
/// ```
/// ┌─────────────────────────────────────────┐
/// │ [language label]          [Copy button] │  ← toolbar
/// ├─────────────────────────────────────────┤
/// │  horizontally-scrollable code text      │  ← content
/// └─────────────────────────────────────────┘
/// ```
final class SDUKCodeBlockView: UIView {

    // MARK: Subviews
    private let toolbarView   = UIView()
    private let languageLabel = UILabel()
    private let copyButton    = UIButton(type: .system)
    private let scrollView    = UIScrollView()
    private let codeTextView  = makeStaticTextView()

    // MARK: State
    private var codeToken: CodeBlockToken?
    private var onCopy: ((String, String?) -> Void)?

    /// Set to `true` while the block is still being received — disables syntax
    /// highlighting and the copy button.
    var isPartial: Bool = false {
        didSet { copyButton.isEnabled = !isPartial }
    }

    // MARK: Init

    init(
        token: CodeBlockToken,
        theme: Theme,
        traitCollection: UITraitCollection,
        isPartial: Bool = false,
        onCopy: ((String, String?) -> Void)? = nil
    ) {
        super.init(frame: .zero)
        self.onCopy = onCopy
        self.isPartial = isPartial
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout(theme: theme)
        configure(token: token, theme: theme, traitCollection: traitCollection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Layout

    private func buildLayout(theme: Theme) {
        layer.cornerRadius = CGFloat(theme.codeBlock.cornerRadius)
        layer.masksToBounds = true

        // Toolbar
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbarView)

        languageLabel.font = UIFont.monospacedSystemFont(
            ofSize: CGFloat(theme.typography.codeSize) - 2,
            weight: .regular
        )
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(languageLabel)

        copyButton.setTitle("Copy", for: .normal)
        copyButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        toolbarView.addSubview(copyButton)

        // Scroll view wrapping the code text
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        codeTextView.isScrollEnabled = false
        scrollView.addSubview(codeTextView)

        NSLayoutConstraint.activate([
            // Toolbar
            toolbarView.topAnchor.constraint(equalTo: topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 36),

            // Language label inside toolbar
            languageLabel.leadingAnchor.constraint(
                equalTo: toolbarView.leadingAnchor, constant: 12),
            languageLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),

            // Copy button inside toolbar
            copyButton.trailingAnchor.constraint(
                equalTo: toolbarView.trailingAnchor, constant: -12),
            copyButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),

            // Scroll view below toolbar
            scrollView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Code text view fills scroll view
            codeTextView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            codeTextView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            codeTextView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            codeTextView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
    }

    // MARK: Configuration

    func configure(
        token: CodeBlockToken,
        theme: Theme,
        traitCollection: UITraitCollection
    ) {
        codeToken = token

        // Toolbar colors
        let toolbarBg = UIColor(
            red: CGFloat(theme.codeBlock.toolbarBackground.r),
            green: CGFloat(theme.codeBlock.toolbarBackground.g),
            blue: CGFloat(theme.codeBlock.toolbarBackground.b),
            alpha: CGFloat(theme.codeBlock.toolbarBackground.a)
        )
        toolbarView.backgroundColor = toolbarBg

        let toolbarFg = UIColor(
            red: CGFloat(theme.codeBlock.toolbarForeground.r),
            green: CGFloat(theme.codeBlock.toolbarForeground.g),
            blue: CGFloat(theme.codeBlock.toolbarForeground.b),
            alpha: CGFloat(theme.codeBlock.toolbarForeground.a)
        )
        languageLabel.textColor = toolbarFg
        languageLabel.text = token.language ?? ""
        languageLabel.isHidden = token.language == nil

        copyButton.isEnabled = !isPartial

        // Code background
        let codeBg = SDInlineRenderer.uiColor(
            from: theme.colors.codeBackground,
            traitCollection: traitCollection
        )
        scrollView.backgroundColor = codeBg
        codeTextView.backgroundColor = codeBg

        // Code text
        let codeFg = SDInlineRenderer.uiColor(
            from: theme.colors.codeForeground,
            traitCollection: traitCollection
        )
        let codeFont = UIFont.monospacedSystemFont(
            ofSize: CGFloat(theme.typography.codeSize),
            weight: .regular
        )
        let padding = CGFloat(theme.spacing.codePadding)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping  // horizontal scroll — don't wrap

        codeTextView.attributedText = NSAttributedString(
            string: token.code,
            attributes: [
                .font: codeFont,
                .foregroundColor: codeFg,
                .paragraphStyle: paragraphStyle
            ]
        )
        codeTextView.textContainerInset = UIEdgeInsets(
            top: padding, left: padding, bottom: padding, right: padding
        )

        accessibilityLabel = "Code block"
        if let lang = token.language { accessibilityLabel = "\(lang) code block" }
    }

    // MARK: Copy action

    @objc private func copyTapped() {
        guard let token = codeToken else { return }
        UIPasteboard.general.string = token.code
        onCopy?(token.code, token.language)

        // Brief visual feedback
        copyButton.setTitle("Copied!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.setTitle("Copy", for: .normal)
        }
    }

    // MARK: Intrinsic content size

    var preferredWidth: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize {
        let w = preferredWidth > 0 ? preferredWidth : bounds.width
        guard w > 0 else { return CGSize(width: UIView.noIntrinsicMetric, height: 100) }
        // Code content: measure using actual code length; cap height for very long blocks.
        let codeSize = codeTextView.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: w, height: 36 + codeSize.height)
    }
}

// MARK: - SDUKBlockquoteView

/// Renders a Markdown blockquote with a coloured left border and inset content.
final class SDUKBlockquoteView: UIView {

    // MARK: Subviews
    private let borderView    = UIView()
    private let contentStack  = UIStackView()

    // MARK: State
    private var widthConstraint: NSLayoutConstraint?

    // MARK: Init
    init(token: BlockquoteToken, theme: Theme, traitCollection: UITraitCollection) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout(theme: theme)
        configure(token: token, theme: theme, traitCollection: traitCollection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Layout

    private func buildLayout(theme: Theme) {
        let borderWidth = CGFloat(theme.spacing.blockquoteBorderWidth)
        let padding     = CGFloat(theme.spacing.blockquotePadding)
        let cornerRadius = CGFloat(theme.blockquote.cornerRadius)

        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true

        borderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(borderView)

        contentStack.axis = .vertical
        contentStack.spacing = CGFloat(theme.spacing.blockSpacing)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            borderView.topAnchor.constraint(equalTo: topAnchor),
            borderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderView.bottomAnchor.constraint(equalTo: bottomAnchor),
            borderView.widthAnchor.constraint(equalToConstant: borderWidth),

            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            contentStack.leadingAnchor.constraint(
                equalTo: borderView.trailingAnchor, constant: padding),
            contentStack.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -padding),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding)
        ])
    }

    func configure(token: BlockquoteToken, theme: Theme, traitCollection: UITraitCollection) {
        borderView.backgroundColor = SDInlineRenderer.uiColor(
            from: theme.colors.blockquoteBorder,
            traitCollection: traitCollection
        )
        backgroundColor = SDInlineRenderer.uiColor(
            from: theme.colors.blockquoteBackground,
            traitCollection: traitCollection
        )

        // Remove previous content views
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Render children
        for childToken in token.children {
            let childView = makeChildView(token: childToken, theme: theme,
                                          traitCollection: traitCollection)
            contentStack.addArrangedSubview(childView)
        }
    }

    private func makeChildView(
        token: MarkdownToken,
        theme: Theme,
        traitCollection: UITraitCollection
    ) -> UIView {
        switch token {
        case .paragraph(let p):
            return SDUKParagraphView(tokens: p.children, theme: theme,
                                      traitCollection: traitCollection)
        case .heading(let h):
            return SDUKHeadingView(token: h, theme: theme, traitCollection: traitCollection)
        case .blockquote(let bq):
            return SDUKBlockquoteView(token: bq, theme: theme, traitCollection: traitCollection)
        default:
            // Fallback: render raw text
            let label = UILabel()
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }
    }

    // MARK: Preferred width

    var preferredWidth: CGFloat = 0 {
        didSet {
            guard preferredWidth != oldValue, preferredWidth > 0 else { return }
            widthConstraint?.isActive = false
            widthConstraint = widthAnchor.constraint(equalToConstant: preferredWidth)
            widthConstraint?.isActive = true
        }
    }

    override var intrinsicContentSize: CGSize {
        systemLayoutSizeFitting(
            CGSize(width: preferredWidth > 0 ? preferredWidth : UIView.noIntrinsicMetric,
                   height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: preferredWidth > 0 ? .required : .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
    }
}

// MARK: - SDUKListView

/// Renders ordered, unordered, and task lists using a vertical `UIStackView`.
final class SDUKListView: UIView {

    // MARK: Subviews
    private let itemsStack = UIStackView()

    // MARK: State
    private var widthConstraint: NSLayoutConstraint?

    // MARK: Init

    init(token: ListToken, theme: Theme, traitCollection: UITraitCollection) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout(theme: theme)
        configure(token: token, theme: theme, traitCollection: traitCollection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Layout

    private func buildLayout(theme: Theme) {
        itemsStack.axis = .vertical
        itemsStack.spacing = CGFloat(theme.spacing.listItemSpacing)
        itemsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(itemsStack)
        NSLayoutConstraint.activate([
            itemsStack.topAnchor.constraint(equalTo: topAnchor),
            itemsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            itemsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            itemsStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: Configuration

    func configure(token: ListToken, theme: Theme, traitCollection: UITraitCollection) {
        itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (idx, item) in token.items.enumerated() {
            let itemView = makeItemRow(
                item: item,
                index: idx,
                listKind: token.kind,
                theme: theme,
                traitCollection: traitCollection
            )
            itemsStack.addArrangedSubview(itemView)
        }
    }

    // MARK: Item row factory

    private func makeItemRow(
        item: ListItemToken,
        index: Int,
        listKind: ListKind,
        theme: Theme,
        traitCollection: UITraitCollection
    ) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        // Bullet / number / checkbox
        if let checkbox = item.checkbox {
            let button = makeCheckboxButton(isChecked: checkbox.isChecked, theme: theme,
                                            traitCollection: traitCollection)
            row.addArrangedSubview(button)
        } else {
            let markerLabel = makeMarkerLabel(
                index: index, kind: listKind, theme: theme, traitCollection: traitCollection
            )
            row.addArrangedSubview(markerLabel)
        }

        // Content: paragraph(s) from item children
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = CGFloat(theme.spacing.listItemSpacing)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        for child in item.children {
            switch child {
            case .paragraph(let p):
                let pv = SDUKParagraphView(tokens: p.children, theme: theme,
                                            traitCollection: traitCollection)
                contentStack.addArrangedSubview(pv)
            case .list(let nested):
                let lv = SDUKListView(token: nested, theme: theme,
                                       traitCollection: traitCollection)
                contentStack.addArrangedSubview(lv)
            default:
                break
            }
        }

        row.addArrangedSubview(contentStack)
        return row
    }

    private func makeMarkerLabel(
        index: Int,
        kind: ListKind,
        theme: Theme,
        traitCollection: UITraitCollection
    ) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: CGFloat(theme.typography.bodySize))
        label.textColor = SDInlineRenderer.uiColor(
            from: theme.colors.foreground,
            traitCollection: traitCollection
        )
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        switch kind {
        case .unordered:
            label.text = "•"
        case .ordered(let start):
            label.text = "\(start + index)."
        case .task:
            label.text = "•"
        }
        return label
    }

    private func makeCheckboxButton(
        isChecked: Bool,
        theme: Theme,
        traitCollection: UITraitCollection
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Use SF Symbols for the checkbox appearance
        let imageName = isChecked ? "checkmark.square.fill" : "square"
        let image = UIImage(systemName: imageName)
        button.setImage(image, for: .normal)
        button.tintColor = isChecked
            ? SDInlineRenderer.uiColor(from: theme.colors.accent,
                                        traitCollection: traitCollection)
            : SDInlineRenderer.uiColor(from: theme.colors.border,
                                        traitCollection: traitCollection)

        // Task list checkboxes are intentionally non-interactive in the renderer.
        button.isUserInteractionEnabled = false
        button.accessibilityLabel = isChecked ? "Checked" : "Unchecked"
        return button
    }

    // MARK: Preferred width

    var preferredWidth: CGFloat = 0 {
        didSet {
            guard preferredWidth != oldValue, preferredWidth > 0 else { return }
            widthConstraint?.isActive = false
            widthConstraint = widthAnchor.constraint(equalToConstant: preferredWidth)
            widthConstraint?.isActive = true
        }
    }

    override var intrinsicContentSize: CGSize {
        systemLayoutSizeFitting(
            CGSize(width: preferredWidth > 0 ? preferredWidth : UIView.noIntrinsicMetric,
                   height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: preferredWidth > 0 ? .required : .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
    }
}

// MARK: - SDUKTableView

/// Renders a GFM table using a `UICollectionView` with compositional layout.
@MainActor
final class SDUKTableView: UIView, UICollectionViewDataSource {

    // MARK: Types

    private struct CellItem {
        let tokens: [InlineToken]
        let isHeader: Bool
        let alignment: ColumnAlignment
        let rowIndex: Int
        let colIndex: Int
    }

    // MARK: State

    private var tableToken: TableToken?
    private var storedTheme: Theme?
    private var storedTraitCollection: UITraitCollection?
    private var collectionView: UICollectionView?
    private var heightConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var columnCount: Int = 0

    // MARK: Init

    init(token: TableToken, theme: Theme, traitCollection: UITraitCollection) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure(token: token, theme: theme, traitCollection: traitCollection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Configuration

    func configure(
        token: TableToken,
        theme: Theme,
        traitCollection: UITraitCollection
    ) {
        tableToken = token
        storedTheme = theme
        storedTraitCollection = traitCollection
        columnCount = token.alignments.count

        // Remove any existing collection view
        collectionView?.removeFromSuperview()

        let layout = makeCompositionalLayout(columnCount: columnCount, theme: theme)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.isScrollEnabled = false
        cv.backgroundColor = .clear
        cv.dataSource = self
        cv.register(SDUKTableCell.self,
                     forCellWithReuseIdentifier: SDUKTableCell.reuseIdentifier)
        addSubview(cv)

        heightConstraint = cv.heightAnchor.constraint(equalToConstant: 200)
        NSLayoutConstraint.activate([
            cv.topAnchor.constraint(equalTo: topAnchor),
            cv.leadingAnchor.constraint(equalTo: leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint!
        ])

        collectionView = cv
        cv.reloadData()

        // Compute height after layout
        DispatchQueue.main.async { [weak self] in
            self?.updateCollectionViewHeight()
        }
    }

    // MARK: Compositional layout

    private func makeCompositionalLayout(
        columnCount: Int,
        theme: Theme
    ) -> UICollectionViewCompositionalLayout {
        let hPad = CGFloat(theme.spacing.tableCellHorizontalPadding)
        let vPad = CGFloat(theme.spacing.tableCellVerticalPadding)

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(max(columnCount, 1))),
            heightDimension: .estimated(40)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(
            top: vPad, leading: hPad, bottom: vPad, trailing: hPad
        )

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(40)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: max(columnCount, 1)
        )

        let section = NSCollectionLayoutSection(group: group)
        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: Collection view data source

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        guard let token = tableToken else { return 0 }
        let rowCount = 1 + token.rows.count   // header row + data rows
        return rowCount * columnCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SDUKTableCell.reuseIdentifier,
            for: indexPath
        ) as! SDUKTableCell

        guard let token = tableToken,
              let theme = storedTheme,
              let tc = storedTraitCollection else { return cell }

        let totalColumns = columnCount
        guard totalColumns > 0 else { return cell }

        let rowIndex = indexPath.item / totalColumns
        let colIndex = indexPath.item % totalColumns
        let isHeaderRow = (rowIndex == 0)

        let rowToken = isHeaderRow ? token.headers : token.rows[rowIndex - 1]
        let alignment = colIndex < token.alignments.count ? token.alignments[colIndex] : .none
        let cellToken = colIndex < rowToken.cells.count ? rowToken.cells[colIndex] : nil

        cell.configure(
            tokens: cellToken?.children ?? [],
            isHeader: isHeaderRow,
            alignment: alignment,
            rowIndex: rowIndex,
            theme: theme,
            traitCollection: tc
        )
        return cell
    }

    // MARK: Height update

    private func updateCollectionViewHeight() {
        guard let cv = collectionView else { return }
        cv.layoutIfNeeded()
        heightConstraint?.constant = cv.collectionViewLayout.collectionViewContentSize.height
        invalidateIntrinsicContentSize()
    }

    // MARK: Preferred width

    var preferredWidth: CGFloat = 0 {
        didSet {
            guard preferredWidth != oldValue, preferredWidth > 0 else { return }
            widthConstraint?.isActive = false
            widthConstraint = widthAnchor.constraint(equalToConstant: preferredWidth)
            widthConstraint?.isActive = true
        }
    }

    override var intrinsicContentSize: CGSize {
        let h = heightConstraint?.constant ?? 200
        return CGSize(width: preferredWidth > 0 ? preferredWidth : UIView.noIntrinsicMetric,
                      height: h)
    }
}

// MARK: - SDUKTableCell

private final class SDUKTableCell: UICollectionViewCell {

    static let reuseIdentifier = "SDUKTableCell"

    private let textView = makeStaticTextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func configure(
        tokens: [InlineToken],
        isHeader: Bool,
        alignment: ColumnAlignment,
        rowIndex: Int,
        theme: Theme,
        traitCollection: UITraitCollection
    ) {
        var attrs = SDInlineRenderer.baseAttributes(theme: theme, traitCollection: traitCollection)
        if isHeader {
            let size = CGFloat(theme.typography.bodySize)
            attrs[.font] = UIFont.boldSystemFont(ofSize: size)
        }

        let attrStr = NSMutableAttributedString()
        let base = SDInlineRenderer.attributedString(from: tokens,
                                                      theme: theme,
                                                      traitCollection: traitCollection)

        // Apply alignment via paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        switch alignment {
        case .left, .none: paragraphStyle.alignment = .left
        case .center:      paragraphStyle.alignment = .center
        case .right:       paragraphStyle.alignment = .right
        }
        let mutable = NSMutableAttributedString(attributedString: base)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        if isHeader {
            let size = CGFloat(theme.typography.bodySize)
            mutable.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: size),
                                  range: fullRange)
        }
        attrStr.append(mutable)
        textView.attributedText = attrStr

        // Row background
        if isHeader {
            backgroundColor = SDInlineRenderer.uiColor(
                from: theme.colors.tableHeaderBackground,
                traitCollection: traitCollection
            )
        } else if rowIndex % 2 == 0 {
            backgroundColor = SDInlineRenderer.uiColor(
                from: theme.colors.tableAlternateRowBackground,
                traitCollection: traitCollection
            )
        } else {
            backgroundColor = .clear
        }
    }
}

// MARK: - SDUKThematicBreakView

/// A 1-point horizontal rule rendered as a thin `UIView`.
final class SDUKThematicBreakView: UIView {

    private var widthConstraint: NSLayoutConstraint?

    init(theme: Theme, traitCollection: UITraitCollection) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = SDInlineRenderer.uiColor(
            from: theme.colors.border,
            traitCollection: traitCollection
        )
        heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: preferredWidth > 0 ? preferredWidth : UIView.noIntrinsicMetric,
               height: 1.0 / UIScreen.main.scale)
    }

    var preferredWidth: CGFloat = 0 {
        didSet {
            guard preferredWidth != oldValue, preferredWidth > 0 else { return }
            widthConstraint?.isActive = false
            widthConstraint = widthAnchor.constraint(equalToConstant: preferredWidth)
            widthConstraint?.isActive = true
        }
    }
}

// MARK: - SDUKPartialView

/// Wraps any block view to indicate partial (in-flight) rendering.
///
/// The wrapped view is displayed at reduced opacity so callers can visually
/// distinguish fully finalised blocks from the current streaming block.
final class SDUKPartialView: UIView {

    /// The view being wrapped.
    private(set) var wrappedView: UIView?

    init(wrapping view: UIView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        alpha = 0.7
        embed(view)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Replace the wrapped view with a new one.
    func update(wrapping view: UIView) {
        wrappedView?.removeFromSuperview()
        embed(view)
    }

    private func embed(_ view: UIView) {
        wrappedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Propagate a preferred width to the wrapped view if it supports the pattern.
    var preferredWidth: CGFloat = 0 {
        didSet {
            applyPreferredWidth(preferredWidth, to: wrappedView)
        }
    }

    override var intrinsicContentSize: CGSize {
        wrappedView?.intrinsicContentSize ?? super.intrinsicContentSize
    }
}

// MARK: - Preferred-width propagation helper

/// Applies `width` to any recognised block-view type that exposes a `preferredWidth` property.
///
/// This internal free function is the single canonical implementation shared across the
/// `StreamDownUIKit` module. Pass an optional `UIView?` — `nil` is handled gracefully.
@MainActor
func applyPreferredWidth(_ width: CGFloat, to view: UIView?) {
    guard let view, width > 0 else { return }
    switch view {
    case let v as SDUKHeadingView:         v.preferredWidth = width
    case let v as SDUKParagraphView:       v.preferredWidth = width
    case let v as SDUKCodeBlockView:       v.preferredWidth = width
    case let v as SDUKBlockquoteView:      v.preferredWidth = width
    case let v as SDUKListView:            v.preferredWidth = width
    case let v as SDUKTableView:           v.preferredWidth = width
    case let v as SDUKThematicBreakView:   v.preferredWidth = width
    case let v as SDUKPartialView:         v.preferredWidth = width
    default: break
    }
}

// MARK: - Inline token → plain text helper (for accessibility)

private func inlineTokenPlainText(_ token: InlineToken) -> String? {
    switch token {
    case .text(let s):              return s
    case .softBreak:                return " "
    case .hardBreak:                return "\n"
    case .emphasis(let e):          return e.children.compactMap(inlineTokenPlainText).joined()
    case .strong(let s):            return s.children.compactMap(inlineTokenPlainText).joined()
    case .strikethrough(let st):    return st.children.compactMap(inlineTokenPlainText).joined()
    case .codeSpan(let c):          return c.code
    case .link(let l):              return l.children.compactMap(inlineTokenPlainText).joined()
    case .autolink(let a):          return a.url
    case .image(let i):             return i.alt
    default:                        return nil
    }
}
