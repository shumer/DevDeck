import AppKit
import DevDeckCore

/// The settings window: one list of everything configurable, grouped by kind, and the form for
/// whichever row is selected.
///
/// The window owns the list and the form column. What goes in them for each kind, and how one
/// of its things is added, edited and removed, is that kind's `SettingsSection`; General is a
/// page of its own, pinned at the top of the list.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, SettingsHost {
    /// The kinds, as the list and the `--settings` launch argument name them. Raw values are
    /// what the argument takes, so they do not change.
    enum Section: String, CaseIterable {
        case github
        case gitlab
        case arc
        case ddev
        case project
        case general

        var title: String {
            switch self {
            case .github: return "GitHub accounts"
            case .gitlab: return "GitLab instances"
            case .arc: return "Arc projects"
            case .ddev: return "DDEV projects"
            case .project: return "Projects"
            case .general: return "General"
            }
        }
    }

    private let sections: [SettingsSection]
    private let general: GeneralSettingsPage
    private let onChanged: () -> Void

    private var window: NSWindow?
    private var list: SettingsListView?
    private var detailScroll: NSScrollView?

    private var section: Section = .github
    /// Which item each section was last left on.
    private var selection: [Section: String] = [:]

    /// One list column instead of a sidebar and a list. Six buttons in a column of their own
    /// was 184 points spent on a choice a heading makes just as well, in an app with about
    /// thirty settings in it, and the forms wanted those points more. It also puts every page
    /// over the width where the label gutter used to change under them.
    private static let listWidth: CGFloat = 232

    private static let generalID = "general"

    /// `sections` in the order the list shows them, which is the order the `+` offers them in.
    init(sections: [SettingsSection], general: GeneralSettingsPage, onChanged: @escaping () -> Void) {
        self.sections = sections
        self.general = general
        self.onChanged = onChanged
        super.init()
        for section in sections { section.host = self }
    }

    private func sectionObject(_ kind: Section) -> SettingsSection? {
        sections.first { $0.kind == kind }
    }

    // MARK: Window

    func show(_ section: Section = .github) {
        if let window {
            select(section)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DevDeck Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 440)
        window.delegate = self
        window.center()

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let list = SettingsListView(
            frame: NSRect(x: 0, y: 0, width: Self.listWidth, height: content.bounds.height)
        )
        list.autoresizingMask = [.height]
        list.onSelect = { [weak self] compound in
            guard let self, let entry = Self.parse(compound) else { return }
            // The row says which kind it is, so choosing one is also how the section changes.
            self.section = entry.section
            self.selection[entry.section] = entry.id
            self.reloadDetail()
        }
        list.onAdd = { [weak self] title in self?.addItem(forMenuTitle: title) }
        list.setAddOptions(sections.map(\.addTitle))
        list.onRemove = { [weak self] in self?.removeSelected() }
        content.addSubview(list)
        self.list = list

        let scroll = NSScrollView(
            frame: NSRect(
                x: Self.listWidth,
                y: 0,
                width: content.bounds.width - Self.listWidth,
                height: content.bounds.height
            )
        )
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)
        detailScroll = scroll

        window.contentView = content
        self.window = window

        select(section)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidResize(_ notification: Notification) {
        // The form is laid out for a width, so it is rebuilt when the width changes. Cheap,
        // and it keeps every field stretched to the window instead of stopping short of it.
        reloadDetail()
    }

    private func select(_ item: Section) {
        section = item
        reloadList()
        reloadDetail()
    }

    /// A row's identity across the whole list: two projects of different kinds can share an id,
    /// and the list is one column now.
    private static func entryID(_ section: Section, _ id: String) -> String {
        "\(section.rawValue):\(id)"
    }

    private static func parse(_ compound: String) -> (section: Section, id: String)? {
        guard let separator = compound.firstIndex(of: ":"),
              let section = Section(rawValue: String(compound[compound.startIndex..<separator]))
        else { return nil }
        return (section, String(compound[compound.index(after: separator)...]))
    }

    // MARK: SettingsHost

    func reloadList() {
        guard let list else { return }

        // Every kind at once, because the list is the sections now. General is pinned at the
        // top as a row of its own: it is a page rather than a list, and putting it anywhere
        // else would leave it as the one thing you reach differently from everything else.
        var listSections: [SettingsListSection] = [
            SettingsListSection(
                title: "Deck",
                items: [SettingsListItem(
                    id: Self.entryID(.general, Self.generalID),
                    title: "General",
                    subtitle: "The deck, notifications, the shortcut",
                    state: nil
                )],
                isAddable: false
            ),
        ]
        for object in sections {
            listSections.append(SettingsListSection(
                title: object.kind.title,
                items: object.listItems().map { item in
                    SettingsListItem(
                        id: Self.entryID(object.kind, item.id),
                        title: item.title,
                        subtitle: item.subtitle,
                        state: item.state
                    )
                }
            ))
        }

        let wanted = section == .general
            ? Self.entryID(.general, Self.generalID)
            : selection[section].map { Self.entryID(section, $0) }
        let ids = listSections.flatMap { $0.items.map(\.id) }
        let valid = ids.contains(where: { $0 == wanted }) ? wanted : ids.first
        if let valid, let entry = Self.parse(valid) {
            section = entry.section
            if entry.section != .general { selection[entry.section] = entry.id }
        }
        list.show(listSections, selecting: valid)
    }

    func reloadDetail() {
        guard let detailScroll else { return }

        let width = max(detailScroll.contentSize.width, 320)
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        if section == .general {
            general.build(in: container, width: width)
        } else if let object = sectionObject(section) {
            let built = selection[section].map { object.buildForm(for: $0, in: container, width: width) } ?? false
            if !built {
                emptyState(object.emptyText, in: container, width: width)
            }
        }

        container.frame.size.height = max(
            container.subviews.map { $0.frame.maxY }.max() ?? 0,
            detailScroll.contentSize.height
        )
        detailScroll.documentView = container
    }

    func select(_ kind: Section, id: String) {
        section = kind
        selection[kind] = id
        reloadList()
        reloadDetail()
    }

    func isShowing(_ kind: Section, id: String) -> Bool {
        section == kind && selection[kind] == id
    }

    func changed() {
        onChanged()
    }

    private func emptyState(_ text: String, in container: FlippedContainer, width: CGFloat) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.secondaryLabelColor
        label.frame = NSRect(x: 20, y: 20, width: width - 40, height: 40)
        container.addSubview(label)
    }

    // MARK: Adding and removing

    private func addItem(forMenuTitle title: String) {
        guard let object = sections.first(where: { $0.addTitle == title }) else { return }
        section = object.kind
        // Nil means either nothing was added or the section will select the result itself once
        // it has asked whatever it needs to ask.
        guard let id = object.add() else { return }
        select(object.kind, id: id)
    }

    private func removeSelected() {
        guard section != .general,
              let object = sectionObject(section),
              let id = selection[section],
              object.remove(id)
        else { return }
        selection[section] = nil
        reloadList()
        reloadDetail()
        onChanged()
    }
}
