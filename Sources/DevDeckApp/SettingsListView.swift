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

    private let footerLine = NSBox()
    private let addButton = NSPopUpButton()
    private let removeButton = NSButton()
    private let footerHeight: CGFloat = 32

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // No material of its own: this view is the window's sidebar item, and that is what draws
        // the translucency and keeps it consistent with every other sidebar on the machine.
        search.placeholderString = "Search"
        search.controlSize = .large
        search.sendsSearchStringImmediately = true
        search.delegate = self
        addSubview(search)

        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        addSubview(scroll)

        addButton.frame = NSRect(x: 12, y: 6, width: 40, height: 22)
        addButton.pullsDown = true
        addButton.isBordered = false
        addButton.autoresizingMask = [.maxXMargin]
        addButton.setAccessibilityLabel("Add")
        addButton.toolTip = "Add an account or a project"

        addSubview(addButton)

        removeButton.frame = NSRect(x: 54, y: 6, width: 24, height: 22)
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")
        removeButton.toolTip = "Remove the selected account or project"
        removeButton.isBordered = false
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.autoresizingMask = [.maxXMargin]
        addSubview(removeButton)

        footerLine.boxType = .separator
        addSubview(footerLine)

        setAccessibilityRole(.list)
        setAccessibilityLabel("Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override var isFlipped: Bool { false }

    /// Laid out against the safe area, because a sidebar item runs the full height of the window
    /// and its top is behind the title bar. The numbers are System Settings' own, measured from
    /// its window: a 28-point search field nine points below the title bar, fourteen points in.
    override func layout() {
        super.layout()
        let top = safeAreaInsets.top
        let searchHeight: CGFloat = 28
        search.frame = NSRect(x: 14, y: bounds.height - top - 9 - searchHeight, width: bounds.width - 27, height: searchHeight)
        let scrollTop = search.frame.minY - 5
        scroll.frame = NSRect(x: 0, y: footerHeight + 1, width: bounds.width, height: max(0, scrollTop - footerHeight - 1))
        footerLine.frame = NSRect(x: 0, y: footerHeight, width: bounds.width, height: 1)
        rebuild()
    }

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
            // A group with nothing in it still shows its title and says where things come from:
            // hiding it left a new deck with no sign that accounts and projects exist at all.
            guard !items.isEmpty || (query.isEmpty && section.title != nil) else { continue }

            if let title = section.title {
                // A rule across the sidebar and a small capitalised label under it: in sentence
                // case at row size the title read as one more row rather than as the start of a
                // group. The rule is what says "everything below this belongs together".
                y += 12
                let rule = HairlineView(frame: NSRect(x: 10, y: y, width: width - 20, height: 1))
                rule.autoresizingMask = [.width]
                document.addSubview(rule)
                headers.append(rule)
                y += 9

                let label = NSTextField(labelWithString: title)
                label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .kern: 0.7,
                ])
                label.frame = NSRect(x: SidebarMetrics.iconLeft, y: y, width: width - SidebarMetrics.iconLeft - 12, height: 14)
                label.autoresizingMask = [.width]
                document.addSubview(label)
                headers.append(label)
                y += 14 + 6
            }

            if items.isEmpty {
                let hint = SettingsForm.label("Add one with +", size: 12, color: .tertiaryLabelColor)
                hint.frame = NSRect(x: SidebarMetrics.textLeft, y: y + 6, width: width - SidebarMetrics.textLeft - 12, height: 16)
                hint.autoresizingMask = [.width]
                document.addSubview(hint)
                headers.append(hint)
                y += 28
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
                y += SidebarMetrics.rowHeight
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
    static var height: CGFloat { SidebarMetrics.rowHeight }

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

        selection.frame = NSRect(x: 10, y: 0, width: width - 20, height: Self.height)
        selection.autoresizingMask = [.width]
        addSubview(selection)

        var left = SidebarMetrics.iconLeft + 2
        if let icon = item.icon {
            let size = SidebarMetrics.iconSize
            let image = NSImageView(frame: NSRect(x: SidebarMetrics.iconLeft, y: (Self.height - size) / 2, width: size, height: size))
            image.image = icon
            image.alphaValue = item.isDimmed ? 0.45 : 1
            addSubview(image)
            left = SidebarMetrics.textLeft
        }

        var right: CGFloat = 20
        if let color = item.dot {
            let dot = DotView(color: color)
            dot.frame = NSRect(x: width - 28, y: (Self.height - 7) / 2, width: 7, height: 7)
            dot.autoresizingMask = [.minXMargin]
            addSubview(dot)
            right = 34
        }

        titleField.stringValue = item.title
        titleField.font = NSFont.systemFont(ofSize: SidebarMetrics.rowFontSize)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.textColor = item.isDimmed ? .tertiaryLabelColor : .labelColor
        titleField.frame = NSRect(x: left, y: (Self.height - 17) / 2, width: width - left - right, height: 17)
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

/// What a sidebar row is made of, in the size the Mac is set to show one.
///
/// System Settings follows "Sidebar icon size" under Appearance, and so does every sidebar Apple
/// ships: at Large its rows are 40 points tall with 26-point icons, and hard-coding those makes an
/// app that is bigger than the system on a Mac set to Medium.
enum SidebarMetrics {
    /// 1 small, 2 medium, 3 large. Absent means medium, which is the default.
    private static var size: Int {
        let stored = UserDefaults.standard.integer(forKey: "NSTableViewDefaultSizeMode")
        return (1...3).contains(stored) ? stored : 2
    }

    static var rowHeight: CGFloat {
        switch size {
        case 1: return 28
        case 3: return 40
        default: return 32
        }
    }

    static var iconSize: CGFloat {
        switch size {
        case 1: return 16
        case 3: return 26
        default: return 20
        }
    }

    static let iconLeft: CGFloat = 18

    static var textLeft: CGFloat { iconLeft + iconSize + 8 }

    static var rowFontSize: CGFloat { size == 3 ? 14 : 13 }

    static var headerFontSize: CGFloat { size == 3 ? 12 : 11 }
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
        layer?.cornerRadius = 8
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
