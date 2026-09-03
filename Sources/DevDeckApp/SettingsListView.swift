import AppKit

/// One kind of thing, and everything of that kind.
///
/// The list carries the sections now. There used to be a column of its own for them, 184 points
/// wide, holding six buttons in an app with about thirty settings in it: a whole column spent on
/// a choice a heading makes just as well, and 184 points the forms needed more.
struct SettingsListSection: Equatable {
    let title: String
    let items: [SettingsListItem]
    /// Sections with nothing in them still appear, because an empty one is how you find out you
    /// can add something there.
    let isAddable: Bool

    init(title: String, items: [SettingsListItem], isAddable: Bool = true) {
        self.title = title
        self.items = items
        self.isAddable = isAddable
    }
}

/// One entry in the middle column.
struct SettingsListItem: Equatable {
    let id: String
    let title: String
    /// The folder, the organisation - whatever tells two similarly named things apart.
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
    /// Section headings and "none yet" labels, kept only so they can be torn down together.
    private var headers: [NSView] = []

    private(set) var items: [SettingsListItem] = []
    private(set) var selectedID: String?

    var onSelect: ((String) -> Void)?
    /// What the `+` offers, and what each entry does.
    var onAdd: ((String) -> Void)?
    var onRemove: (() -> Void)?

    private let addButton = NSPopUpButton()

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

        // The `+` and `−` pair macOS puts under every editable list. The `+` is a pull-down
        // now: with every kind in one list, the button has to ask which kind, and a menu is
        // where that question was always going to end up.
        addButton.frame = NSRect(x: 8, y: 4, width: 34, height: 22)
        addButton.pullsDown = true
        addButton.bezelStyle = .smallSquare
        addButton.autoresizingMask = [.maxXMargin]
        addSubview(addButton)

        let remove = NSButton(title: "−", target: self, action: #selector(removeTapped))
        remove.frame = NSRect(x: 46, y: 5, width: 26, height: 20)
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

    func show(_ sections: [SettingsListSection], selecting id: String?) {
        self.items = sections.flatMap(\.items)
        self.selectedID = id ?? items.first?.id

        for row in rows { row.removeFromSuperview() }
        for header in headers { header.removeFromSuperview() }
        rows = []
        headers = []

        var y: CGFloat = 6
        let width = scroll.contentSize.width
        for section in sections {
            let header = SettingsListView.header(section.title, width: width)
            header.frame.origin = NSPoint(x: 0, y: y)
            header.autoresizingMask = [.width]
            document.addSubview(header)
            headers.append(header)
            y += Self.headerHeight

            if section.items.isEmpty {
                let empty = SettingsListView.empty(width: width)
                empty.frame.origin = NSPoint(x: 0, y: y)
                empty.autoresizingMask = [.width]
                document.addSubview(empty)
                headers.append(empty)
                y += Self.emptyHeight
            }

            for item in section.items {
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
            y += Self.sectionGap
        }

        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y + 6, scroll.contentSize.height))
    }

    static let headerHeight: CGFloat = 24
    static let emptyHeight: CGFloat = 24
    static let sectionGap: CGFloat = 10

    private static func header(_ title: String, width: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = NSColor.tertiaryLabelColor
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        label.frame = NSRect(x: 12, y: 8, width: width - 24, height: 14)
        label.autoresizingMask = [.width]
        container.addSubview(label)
        return container
    }

    /// Said in words rather than left blank: an empty section is where you learn that something
    /// can be added there at all.
    private static func empty(width: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: "none yet")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.tertiaryLabelColor
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: width, height: emptyHeight))
        label.frame = NSRect(x: 24, y: 4, width: width - 36, height: 15)
        label.autoresizingMask = [.width]
        container.addSubview(label)
        return container
    }

    /// The kinds the `+` can add, in the order the list shows them.
    func setAddOptions(_ titles: [String]) {
        addButton.removeAllItems()
        // The first item of a pull-down is its own title and is never chosen.
        addButton.addItem(withTitle: "+")
        for title in titles { addButton.addItem(withTitle: title) }
        addButton.target = self
        addButton.action = #selector(addTapped)
    }

    @objc private func addTapped() {
        guard let title = addButton.titleOfSelectedItem, title != "+" else { return }
        onAdd?(title)
    }
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
