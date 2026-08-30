import AppKit

/// One entry in the middle column.
struct SettingsListItem: Equatable {
    let id: String
    let title: String
    /// The folder, the organisation — whatever tells two similarly named things apart.
    let subtitle: String
    /// Green when it is up, grey when it is not, nil when the item has no such state.
    let state: NSColor?
}

/// The middle column: which account or project is being edited.
///
/// The whole reason the settings window has three columns. With every project's fields on one
/// long page it was impossible to see where one ended and the next began; here only the
/// selected one has a form, and this list carries the identity.
@MainActor
final class SettingsListView: NSView {
    private let scroll = NSScrollView()
    private let document = FlippedContainer()
    private var rows: [SettingsListRow] = []

    private(set) var items: [SettingsListItem] = []
    private(set) var selectedID: String?

    var onSelect: ((String) -> Void)?
    var onAdd: (() -> Void)?
    var onRemove: (() -> Void)?

    private let footerHeight: CGFloat = 30

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor

        scroll.frame = NSRect(x: 0, y: footerHeight, width: bounds.width, height: bounds.height - footerHeight)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        addSubview(scroll)

        // The `+` and `−` pair macOS puts under every editable list.
        let add = NSButton(title: "+", target: self, action: #selector(addTapped))
        add.frame = NSRect(x: 8, y: 5, width: 26, height: 20)
        add.bezelStyle = .smallSquare
        add.setButtonType(.momentaryPushIn)
        add.autoresizingMask = [.maxXMargin]
        addSubview(add)

        let remove = NSButton(title: "−", target: self, action: #selector(removeTapped))
        remove.frame = NSRect(x: 34, y: 5, width: 26, height: 20)
        remove.bezelStyle = .smallSquare
        remove.autoresizingMask = [.maxXMargin]
        addSubview(remove)

        let separator = NSView(frame: NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separator.autoresizingMask = [.height, .minXMargin]
        addSubview(separator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    func show(_ items: [SettingsListItem], selecting id: String?) {
        self.items = items
        self.selectedID = id ?? items.first?.id

        for row in rows { row.removeFromSuperview() }
        rows = []

        var y: CGFloat = 6
        let width = scroll.contentSize.width
        for item in items {
            let row = SettingsListRow(item: item, width: width)
            row.frame.origin = NSPoint(x: 0, y: y)
            row.autoresizingMask = [.width]
            row.isSelected = item.id == selectedID
            row.onClick = { [weak self] in
                guard let self else { return }
                self.selectedID = item.id
                for candidate in self.rows { candidate.isSelected = candidate.item.id == item.id }
                self.onSelect?(item.id)
            }
            document.addSubview(row)
            rows.append(row)
            y += SettingsListRow.height
        }

        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y + 6, scroll.contentSize.height))
    }

    @objc private func addTapped() { onAdd?() }
    @objc private func removeTapped() { onRemove?() }
}

/// One row of the list: a name, what tells it apart, and its state.
@MainActor
final class SettingsListRow: NSView {
    static let height: CGFloat = 42

    let item: SettingsListItem
    var onClick: (() -> Void)?

    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let dot = NSView()

    var isSelected = false {
        didSet { applySelection() }
    }

    init(item: SettingsListItem, width: CGFloat) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        let hasDot = item.state != nil
        let left: CGFloat = hasDot ? 24 : 12

        if let state = item.state {
            dot.frame = NSRect(x: 12, y: Self.height / 2 - 3, width: 6, height: 6)
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.backgroundColor = state.cgColor
            dot.autoresizingMask = [.maxXMargin]
            addSubview(dot)
        }

        titleField.stringValue = item.title
        titleField.font = NSFont.systemFont(ofSize: 13)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: left, y: 21, width: width - left - 10, height: 16)
        titleField.autoresizingMask = [.width]
        addSubview(titleField)

        subtitleField.stringValue = item.subtitle
        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = NSColor.secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingMiddle
        subtitleField.frame = NSRect(x: left, y: 5, width: width - left - 10, height: 14)
        subtitleField.autoresizingMask = [.width]
        addSubview(subtitleField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func applySelection() {
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        titleField.textColor = isSelected ? .white : .labelColor
        subtitleField.textColor = isSelected ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
    }
}
