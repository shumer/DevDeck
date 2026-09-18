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
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate, SettingsHost {
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
    private var splitController: NSSplitViewController?
    private var list: SettingsListView?
    private var detailScroll: NSScrollView?

    /// How tall the form built for the current page is, so a resize can keep the document at
    /// least as tall as the window without building it again.
    private var detailHeight: CGFloat = 0
    private var current: (section: Section, id: String?) = (.general, nil)
    private var openFolds: Set<String> = []

    /// What System Settings uses, measured from its own window: a sidebar wide enough for a
    /// project name and its mark.
    private static let listWidth: CGFloat = 268
    /// The window is exactly as wide as the sidebar and the widest the form column goes, and that
    /// width is fixed: System Settings does not let its window be reshaped either, and a form
    /// column that can be dragged to any width is a column nobody has laid out. The height is the
    /// one System Settings opens at, and that one can be changed.
    /// The sidebar item is inset eight points from the window's edge, and those eight are the
    /// window's, not the sidebar's.
    private static let windowWidth: CGFloat = listWidth + 8 + SettingsForm.sideInset * 2 + SettingsForm.columnWidth
    private static let defaultSize = NSSize(width: windowWidth, height: 679)

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
        // Asking for a window that is already up is not a second window, and the Dock icon is
        // counted, not flagged.
        let wasVisible = window?.isVisible ?? false
        if window == nil { makeWindow() }
        open(section, id: id ?? (section == current.section ? current.id : nil))
        // In the Dock while this window is open, and out of it again when it closes. An agent app
        // has no Dock icon, so a minimised window sat there as a nameless blank page with no way
        // to tell whose it was; with the app itself in the Dock, macOS puts its icon on the tile
        // and the window can be brought back the ordinary way.
        if !wasVisible { WindowPresence.retain() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            // Full-size content, so the sidebar's material runs up behind the window buttons the
            // way every sidebar on the machine does. What that costs is the top inset, which the
            // two panes then apply themselves: see `SettingsChrome`.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings.window.title")
        // What the Dock shows under a minimised window, where the app's name is the only clue to
        // whose window it is.
        window.miniwindowTitle = L("settings.window.title")
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // The form column has a fixed width, so a narrower window only cuts into it.
        window.minSize = NSSize(width: Self.windowWidth, height: 420)
        window.maxSize = NSSize(width: Self.windowWidth, height: 100_000)
        window.delegate = self

        let list = SettingsListView(frame: NSRect(x: 0, y: 0, width: Self.listWidth, height: Self.defaultSize.height))
        list.autoresizingMask = [.width, .height]
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
        self.list = list

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        detailScroll = scroll

        // A real sidebar item rather than a view on the left: that is what makes the sidebar
        // translucent, keeps its content clear of the title bar, and gives the window the
        // full-height title bar System Settings has, with the window buttons at their usual size.
        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: Pane(view: list))
        sidebar.minimumThickness = Self.listWidth
        sidebar.maximumThickness = Self.listWidth
        sidebar.canCollapse = false
        sidebar.allowsFullHeightLayout = true
        sidebar.titlebarSeparatorStyle = .none
        split.addSplitViewItem(sidebar)

        // The scroll view goes inside a plain container: a split item takes its view's fitting
        // size as a minimum, and a scroll view's fitting size is its document's, so the form's own
        // width became a floor the window could never be narrowed past.
        let detailPane = NSView(frame: NSRect(x: 0, y: 0, width: Self.defaultSize.width - Self.listWidth, height: Self.defaultSize.height))
        scroll.frame = detailPane.bounds
        detailPane.addSubview(scroll)

        let detail = NSSplitViewItem(viewController: Pane(view: detailPane))
        detail.titlebarSeparatorStyle = .none
        // Said outright, because a split item otherwise takes the form's own width as its
        // minimum, and the window could then only ever be made wider.
        detail.minimumThickness = SettingsForm.minimumColumnWidth + SettingsForm.sideInset * 2
        split.addSplitViewItem(detail)
        self.splitController = split

        // An empty toolbar, for its height and for the divider that runs up into the title bar.
        // Without one the window gets the compact title bar, whose buttons are two points smaller
        // than every other window's on screen.
        let toolbar = NSToolbar(identifier: "settings")
        toolbar.delegate = self
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        // Unified, not compact: this is the title bar AppKit gives a window with a toolbar, and
        // it puts the window buttons exactly where every other window has them. System Settings'
        // bar is fourteen points shorter because it is a Catalyst app, which is not a look an
        // AppKit window can ask for.
        window.toolbarStyle = .unified
        // No rule under the title bar until something scrolls beneath it, the way System Settings
        // does it.
        window.titlebarSeparatorStyle = .automatic

        window.contentViewController = split
        // After the content, which sizes the window to itself: the remembered frame has to be the
        // last word, or a window somebody made narrower opens at whatever the panes add up to.
        window.center()
        // Remembered, because at the old fixed 880 x 580 nearly every form scrolled and nobody
        // could make it stay larger.
        window.setFrameAutosaveName("DevDeck Settings")
        window.initialFirstResponder = list
        self.window = window
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier == .sidebarTrackingSeparator, let split = splitController else { return nil }
        return NSTrackingSeparatorToolbarItem(
            identifier: identifier,
            splitView: split.splitView,
            dividerIndex: 0
        )
    }

    /// The form follows the window's width. Its rows carry the autoresizing masks that say what
    /// stretches, but the document view they sit in is a clip view's subview, and that one has to
    /// be resized by hand: without this the groups kept the width they were built at and their
    /// trailing buttons went off the edge of a narrowed window.
    func windowDidResize(_ notification: Notification) {
        guard let detailScroll, let container = detailScroll.documentView else { return }
        let size = detailScroll.contentSize
        container.frame.size = NSSize(width: size.width, height: max(detailHeight, size.height))
        detailScroll.hasVerticalScroller = detailHeight > size.height
    }

    /// Whatever was being typed is kept: ending the edit is what commits it. The Dock icon goes
    /// with the window: this is an agent app again once there is nothing to show.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        WindowPresence.release()
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

        for (group, title) in [(SettingsListGroup.accounts, L("settings.sidebar.accounts")), (.projects, L("settings.sidebar.projects"))] {
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
        // Named in the Dock and in the Window menu by what is on screen, the way a document
        // window is.
        window?.title = listSections
            .flatMap(\.items)
            .first { $0.id == wanted }
            .map { L("settings.window.titleFor", $0.title) } ?? L("settings.window.title")
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
                emptyState(L("settings.empty.nothingSelected"), in: container)
            }
        } else {
            emptyState(L("settings.empty.nothingYet"), in: container)
        }

        let needed = (container.subviews.map(\.frame.maxY).max() ?? 0) + 28
        detailHeight = needed
        container.frame.size.height = max(needed, detailScroll.contentSize.height)
        detailScroll.hasVerticalScroller = needed > detailScroll.contentSize.height
        detailScroll.documentView = container
        // To the top of the form, not to the top of the clip view: with the title bar's inset
        // those are different points, and the difference is the page header hidden behind the bar.
        detailScroll.contentView.scroll(to: NSPoint(x: 0, y: -detailScroll.contentInsets.top))
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
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

    /// Centred, the way an empty view is on a Mac, rather than a grey line in the top corner.
    private func emptyState(_ text: String, in container: FlippedContainer) {
        let label = SettingsForm.label(text, size: 13, color: .secondaryLabelColor)
        label.alignment = .center
        label.frame = NSRect(
            x: SettingsForm.sideInset,
            y: max(60, (detailScroll?.contentSize.height ?? 400) / 2 - 40),
            width: container.bounds.width - SettingsForm.sideInset * 2,
            height: 18
        )
        label.autoresizingMask = [.width]
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

/// One side of the split, holding a view that lays itself out. The split view controller needs
/// view controllers; nothing else here does.
@MainActor
final class Pane: NSViewController {
    private let pane: NSView

    init(view: NSView) {
        self.pane = view
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used, this view is built in code")
    }

    override func loadView() {
        view = pane
    }

}

