import AppKit

/// A group of rows in the sidebar, under a heading or, for the pages at the top, under none.
struct SettingsListSection {
    let title: String?
    let items: [SettingsListItem]

    init(title: String?, items: [SettingsListItem]) {
        self.title = title
        self.items = items
    }
}

/// One row of the sidebar.
struct SettingsListItem {
    let id: String
    let title: String
    /// What tells two similar rows apart, shown as a tooltip rather than a second line: a list
    /// of fifteen two-line rows filled the whole column and said the same thing twice.
    let detail: String
    let icon: NSImage?
    /// Only when the colour means something: a project running or starting, a token refused.
    /// Every row wore a green dot before, which meant every dot said nothing.
    let dot: NSColor?
    /// A thing that is configured but not on the deck.
    let isDimmed: Bool

    init(id: String, title: String, detail: String = "", icon: NSImage?, dot: NSColor? = nil, isDimmed: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.icon = icon
        self.dot = dot
        self.isDimmed = isDimmed
    }
}

/// The sidebar: the pages, then accounts, then projects.
///
/// It takes the keyboard. Up and down move the selection, Delete asks to remove the selected
/// thing, and the search field narrows the list, which with fifteen projects is the quickest way
/// to one of them. The rows used to be plain views that only answered a mouse click.
@MainActor
final class SettingsListView: NSView, NSSearchFieldDelegate {
    private let scroll = NSScrollView()
    private let document = FlippedContainer()
    private let search = NSSearchField()
    private var rows: [SettingsListRow] = []
    private var headers: [NSView] = []
    private var sections: [SettingsListSection] = []

    private(set) var selectedID: String?

    var onSelect: ((String) -> Void)?
    /// The kind picked from the `+` menu.
    var onAdd: ((String) -> Void)?
    var onRemove: (() -> Void)?

    private let addButton = NSPopUpButton()
    private let removeButton = NSButton()
    private let footerHeight: CGFloat = 32

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let material = NSVisualEffectView(frame: bounds)
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        material.autoresizingMask = [.width, .height]
        addSubview(material)

        // Under the traffic lights: the window's content runs beneath a transparent title bar.
        search.frame = NSRect(x: 10, y: bounds.height - 62, width: bounds.width - 20, height: 24)
        search.autoresizingMask = [.width, .minYMargin]
        search.placeholderString = "Search"
        search.controlSize = .regular
        search.sendsSearchStringImmediately = true
        search.delegate = self
        addSubview(search)

        scroll.frame = NSRect(x: 0, y: footerHeight, width: bounds.width, height: bounds.height - footerHeight - 70)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        addSubview(scroll)

        addButton.frame = NSRect(x: 8, y: 5, width: 40, height: 22)
        addButton.pullsDown = true
        addButton.isBordered = false
        addButton.autoresizingMask = [.maxXMargin]
        addButton.setAccessibilityLabel("Add")
        addSubview(addButton)

        removeButton.frame = NSRect(x: 50, y: 5, width: 24, height: 22)
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")
        removeButton.isBordered = false
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.autoresizingMask = [.maxXMargin]
        addSubview(removeButton)

        let footerLine = NSBox(frame: NSRect(x: 0, y: footerHeight, width: bounds.width, height: 1))
        footerLine.boxType = .separator
        footerLine.autoresizingMask = [.width]
        addSubview(footerLine)

        let edge = NSBox(frame: NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height))
        edge.boxType = .separator
        edge.autoresizingMask = [.height, .minXMargin]
        addSubview(edge)

        setAccessibilityRole(.list)
        setAccessibilityLabel("Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override var isFlipped: Bool { false }

    // MARK: Content

    func show(_ sections: [SettingsListSection], selecting id: String?) {
        self.sections = sections
        selectedID = id
        rebuild()
    }

    /// Whether the selected row can be removed. The pages cannot, so the minus says so.
    func setRemovable(_ removable: Bool) {
        removeButton.isEnabled = removable
    }

    private func rebuild() {
        for row in rows { row.removeFromSuperview() }
        for header in headers { header.removeFromSuperview() }
        rows = []
        headers = []

        let query = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        var y: CGFloat = 4
        let width = scroll.contentSize.width

        for section in sections {
            let items = query.isEmpty
                ? section.items
                : section.items.filter { $0.title.lowercased().contains(query) || $0.detail.lowercased().contains(query) }
            guard !items.isEmpty else { continue }

            if let title = section.title {
                let label = SettingsForm.label(title, size: 11, weight: .semibold, color: .secondaryLabelColor)
                label.frame = NSRect(x: 18, y: y + 12, width: width - 30, height: 14)
                label.autoresizingMask = [.width]
                document.addSubview(label)
                headers.append(label)
                y += 30
            }

            for item in items {
                let row = SettingsListRow(item: item, width: width)
                row.frame.origin = NSPoint(x: 0, y: y)
                row.autoresizingMask = [.width]
                row.isSelected = item.id == selectedID
                row.onClick = { [weak self] in
                    guard let self else { return }
                    // Taking focus first ends any edit in the form, which is what saves it.
                    self.window?.makeFirstResponder(self)
                    self.select(item.id)
                }
                document.addSubview(row)
                rows.append(row)
                y += SettingsListRow.height
            }
            y += 4
        }

        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y + 8, scroll.contentSize.height))
    }

    private func select(_ id: String) {
        selectedID = id
        for row in rows { row.isSelected = row.item.id == id }
        if let row = rows.first(where: { $0.item.id == id }) {
            document.scrollToVisible(row.frame.insetBy(dx: 0, dy: -8))
        }
        onSelect?(id)
    }

    /// The `+` menu. An empty string is a separator.
    func setAddOptions(_ titles: [String]) {
        addButton.removeAllItems()
        addButton.addItem(withTitle: "")
        addButton.item(at: 0)?.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        for title in titles {
            if title.isEmpty {
                addButton.menu?.addItem(.separator())
            } else {
                addButton.addItem(withTitle: title)
            }
        }
        addButton.target = self
        addButton.action = #selector(addTapped)
    }

    @objc private func addTapped() {
        guard let title = addButton.titleOfSelectedItem, !title.isEmpty else { return }
        onAdd?(title)
    }

    @objc private func removeTapped() { onRemove?() }

    // MARK: Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let visible = rows.map(\.item.id)
        let index = selectedID.flatMap { visible.firstIndex(of: $0) }
        switch event.keyCode {
        case 125: // Down.
            let next = index.map { min($0 + 1, visible.count - 1) } ?? 0
            if visible.indices.contains(next) { select(visible[next]) }
        case 126: // Up.
            let previous = index.map { max($0 - 1, 0) } ?? 0
            if visible.indices.contains(previous) { select(visible[previous]) }
        case 51, 117: // Delete, forward delete.
            onRemove?()
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "f" {
                window?.makeFirstResponder(search)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// ⌘F from anywhere in the window lands in the search field.
    func focusSearch() {
        window?.makeFirstResponder(search)
    }

    func controlTextDidChange(_ notification: Notification) {
        rebuild()
    }
}

/// One row: the mark, the name, and a dot only when the dot means something.
@MainActor
final class SettingsListRow: NSView {
    static let height: CGFloat = 28

    let item: SettingsListItem
    var onClick: (() -> Void)?

    private let titleField = NSTextField(labelWithString: "")
    private let selection = SelectionView()

    var isSelected = false {
        didSet {
            selection.isSelected = isSelected
            titleField.textColor = isSelected ? .white : (item.isDimmed ? .tertiaryLabelColor : .labelColor)
            setAccessibilitySelected(isSelected)
        }
    }

    init(item: SettingsListItem, width: CGFloat) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        selection.frame = NSRect(x: 10, y: 1, width: width - 20, height: Self.height - 2)
        selection.autoresizingMask = [.width]
        addSubview(selection)

        var left: CGFloat = 20
        if let icon = item.icon {
            let image = NSImageView(frame: NSRect(x: 18, y: 4, width: 20, height: 20))
            image.image = icon
            image.alphaValue = item.isDimmed ? 0.45 : 1
            addSubview(image)
            left = 46
        }

        var right: CGFloat = 20
        if let color = item.dot {
            let dot = DotView(color: color)
            dot.frame = NSRect(x: width - 28, y: 11, width: 7, height: 7)
            dot.autoresizingMask = [.minXMargin]
            addSubview(dot)
            right = 34
        }

        titleField.stringValue = item.title
        titleField.font = NSFont.systemFont(ofSize: 13)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.textColor = item.isDimmed ? .tertiaryLabelColor : .labelColor
        titleField.frame = NSRect(x: left, y: 6, width: width - left - right, height: 16)
        titleField.autoresizingMask = [.width]
        addSubview(titleField)

        toolTip = [item.title, item.detail, item.isDimmed ? "not on the deck" : ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel(toolTip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// The rounded selection, in the accent colour when the window is key and grey when it is not.
@MainActor
private final class SelectionView: NSView {
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let color: NSColor = window?.isKeyWindow == false
            ? .unemphasizedSelectedContentBackgroundColor
            : .controlAccentColor
        layer?.backgroundColor = isSelected ? color.cgColor : NSColor.clear.cgColor
    }
}

@MainActor
private final class DotView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 3.5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
    }
}
