import AppKit
import DevDeckCore

/// A page of the settings window that is not a list of things: General, Deck, Cards,
/// Notifications.
@MainActor
protocol SettingsPage: AnyObject {
    var kind: SettingsWindowController.Section { get }
    var title: String { get }
    var icon: NSImage { get }
    /// The window, set when the page is added. Pages that update themselves, like General's
    /// update row, use it to know whether they are on screen.
    var host: SettingsHost? { get set }
    func build(in container: FlippedContainer)
}

/// The settings window: a sidebar with the pages, the accounts and the projects, and the form
/// for whichever row is selected.
///
/// The window owns the sidebar and the form column and nothing about any kind of thing. What goes
/// in them is each page's and each section's.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, SettingsHost {
    /// Everything the sidebar can show, as the `--settings` launch argument names it. Raw values
    /// are what the argument takes, so they do not change.
    enum Section: String, CaseIterable {
        case general
        case deck
        case cards
        case notifications
        case github
        case gitlab
        case arc
        case ddev
        case project
    }

    private let pages: [SettingsPage]
    private let sections: [SettingsSection]
    private let onChanged: () -> Void

    private var window: NSWindow?
    private var list: SettingsListView?
    private var detailScroll: NSScrollView?

    private var current: (section: Section, id: String?) = (.general, nil)
    private var openFolds: Set<String> = []

    private static let listWidth: CGFloat = 220
    private static let defaultSize = NSSize(width: 820, height: 640)

    init(pages: [SettingsPage], sections: [SettingsSection], onChanged: @escaping () -> Void) {
        self.pages = pages
        self.sections = sections
        self.onChanged = onChanged
        super.init()
        for page in pages { page.host = self }
        for section in sections { section.host = self }
    }

    var isVisible: Bool { window?.isVisible == true }

    // MARK: Window

    /// Opens the window on a page, or on one account or project when `id` names it.
    func show(_ section: Section = .general, id: String? = nil) {
        if window == nil { makeWindow() }
        open(section, id: id ?? (section == current.section ? current.id : nil))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DevDeck Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // The form column has a fixed width, so a narrower window only cuts into it.
        window.minSize = NSSize(width: Self.defaultSize.width, height: 480)
        window.delegate = self
        window.center()
        // Remembered, because at the old fixed 880 x 580 nearly every form scrolled and nobody
        // could make it stay larger.
        window.setFrameAutosaveName("DevDeck Settings")

        let content = NSView(frame: NSRect(origin: .zero, size: Self.defaultSize))

        let list = SettingsListView(frame: NSRect(x: 0, y: 0, width: Self.listWidth, height: content.bounds.height))
        list.autoresizingMask = [.height]
        list.onSelect = { [weak self] compound in
            guard let self, let entry = Self.parse(compound) else { return }
            self.current = (entry.section, entry.id)
            self.list?.setRemovable(self.sectionObject(entry.section) != nil)
            self.reloadDetail()
        }
        list.onAdd = { [weak self] title in self?.add(title) }
        list.onRemove = { [weak self] in self?.removeSelected() }
        var addOptions = sections.filter { $0.group == .accounts }.map(\.addTitle)
        addOptions.append("")
        addOptions += sections.filter { $0.group == .projects }.map(\.addTitle)
        list.setAddOptions(addOptions)
        content.addSubview(list)
        self.list = list

        let scroll = NSScrollView(frame: NSRect(
            x: Self.listWidth,
            y: 0,
            width: content.bounds.width - Self.listWidth,
            height: content.bounds.height
        ))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)
        detailScroll = scroll

        window.contentView = content
        window.initialFirstResponder = list
        self.window = window
    }

    /// Whatever was being typed is kept: ending the edit is what commits it.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    // MARK: Identity of a row

    private static func entryID(_ section: Section, _ id: String?) -> String {
        "\(section.rawValue):\(id ?? "")"
    }

    private static func parse(_ compound: String) -> (section: Section, id: String?)? {
        guard let separator = compound.firstIndex(of: ":"),
              let section = Section(rawValue: String(compound[compound.startIndex..<separator]))
        else { return nil }
        let id = String(compound[compound.index(after: separator)...])
        return (section, id.isEmpty ? nil : id)
    }

    private func sectionObject(_ kind: Section) -> SettingsSection? {
        sections.first { $0.kind == kind }
    }

    private func page(_ kind: Section) -> SettingsPage? {
        pages.first { $0.kind == kind }
    }

    // MARK: SettingsHost

    func reloadList() {
        guard let list else { return }

        var listSections = [SettingsListSection(title: nil, items: pages.map { page in
            SettingsListItem(id: Self.entryID(page.kind, nil), title: page.title, icon: page.icon)
        })]

        for (group, title) in [(SettingsListGroup.accounts, "Accounts"), (.projects, "Projects")] {
            let items = sections
                .filter { $0.group == group }
                .flatMap { section in
                    section.listItems().map { item in
                        SettingsListItem(
                            id: Self.entryID(section.kind, item.id),
                            title: item.title,
                            detail: item.detail,
                            icon: item.icon,
                            dot: item.dot,
                            isDimmed: item.isDimmed
                        )
                    }
                }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            listSections.append(SettingsListSection(title: title, items: items))
        }

        // The remembered row if it still exists, otherwise the first of its kind, otherwise the
        // page it belongs under: removing the last project should land somewhere that makes sense.
        let ids = listSections.flatMap { $0.items.map(\.id) }
        var wanted = Self.entryID(current.section, current.id)
        if !ids.contains(wanted) {
            wanted = ids.first { Self.parse($0)?.section == current.section } ?? Self.entryID(.general, nil)
            current = Self.parse(wanted) ?? (.general, nil)
        }
        list.show(listSections, selecting: wanted)
        list.setRemovable(sectionObject(current.section) != nil)
    }

    func reloadDetail() {
        guard let detailScroll else { return }
        // Ends an edit in the form being replaced, so what was typed is saved rather than lost.
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: detailScroll) {
            window?.makeFirstResponder(list)
        }

        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: detailScroll.contentSize.width, height: 10))
        container.autoresizingMask = [.width]

        if let page = page(current.section) {
            page.build(in: container)
        } else if let section = sectionObject(current.section), let id = current.id {
            if !section.buildForm(for: id, in: container) {
                emptyState("Nothing is selected.", in: container)
            }
        } else {
            emptyState("Nothing here yet. Press + below the list to add one.", in: container)
        }

        let needed = (container.subviews.map(\.frame.maxY).max() ?? 0) + 28
        container.frame.size.height = max(needed, detailScroll.contentSize.height)
        detailScroll.hasVerticalScroller = needed > detailScroll.contentSize.height
        detailScroll.documentView = container
        container.scroll(.zero)
    }

    private func open(_ kind: Section, id: String?) {
        current = (kind, id)
        reloadList()
        reloadDetail()
    }

    func select(_ kind: Section, id: String) {
        open(kind, id: id)
    }

    func isShowing(_ kind: Section, id: String) -> Bool {
        isVisible && current.section == kind && current.id == id
    }

    /// Rebuilds a page only when it is the one on screen, for a page that changes by itself.
    func reloadIfShowing(_ kind: Section) {
        guard isVisible, current.section == kind else { return }
        reloadDetail()
    }

    func isOpen(_ fold: String) -> Bool {
        openFolds.contains(fold)
    }

    func toggle(_ fold: String) {
        if openFolds.contains(fold) { openFolds.remove(fold) } else { openFolds.insert(fold) }
        reloadDetail()
    }

    func changed() {
        onChanged()
    }

    private func emptyState(_ text: String, in container: FlippedContainer) {
        let label = SettingsForm.label(text, size: 13, color: .secondaryLabelColor)
        label.frame = NSRect(x: SettingsForm.sideInset, y: 24, width: container.bounds.width - 56, height: 18)
        container.addSubview(label)
    }

    // MARK: Adding and removing

    private func add(_ title: String) {
        guard let section = sections.first(where: { $0.addTitle == title }) else { return }
        // Nil means either nothing was added or the section selects the result itself once it
        // has asked what it needs to ask.
        guard let id = section.add() else { return }
        select(section.kind, id: id)
    }

    private func removeSelected() {
        guard let section = sectionObject(current.section),
              let id = current.id,
              section.remove(id)
        else { return }
        current = (current.section, nil)
        reloadList()
        reloadDetail()
        onChanged()
    }
}
