import AppKit
import ArcKit
import DDEVKit
import DevDeckCore
import GitHubKit
import GitLabKit
import ProjectKit

/// The settings window: sections, then the things in a section, then the form for one of them.
///
/// Three columns rather than one long page. With every project's fields stacked under each
/// other it was impossible to see where one ended and the next began, and the form column is
/// what absorbs the window's width instead of leaving dead space down the right.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
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

        /// What the `+` calls this kind, and the order it offers them in.
        var addTitle: String {
            switch self {
            case .github: return "GitHub account"
            case .gitlab: return "GitLab instance"
            case .arc: return "Arc project"
            case .ddev: return "DDEV project"
            case .project: return "Project"
            case .general: return ""
            }
        }

        /// General is a page rather than a list of things, so nothing can be added to it.
        static var addable: [Section] { allCases.filter { $0 != .general } }
    }

    private let tokenStore: any TokenStore
    private let accountsStore: GitHubAccountsStore
    private let gitlabAccountsStore: GitLabAccountsStore
    private let projectsStore: ArcProjectsStore
    private let ddevProjectsStore: DDEVProjectsStore
    private let localProjectsStore: LocalProjectsStore
    private let ddevEnvironment = DDEVEnvironment()
    private let preferences: Preferences
    private let onChanged: () -> Void
    /// Asks the app delegate to put the permission question to macOS.
    var onRequestNotifications: (@escaping (Bool) -> Void) -> Void = { $0(false) }
    /// Posts one banner now, so the chain can be checked without waiting for a review request.
    var onTestNotification: () -> Void = {}

    private var window: NSWindow?
    private var list: SettingsListView?
    private var detailScroll: NSScrollView?
    private var detail: FlippedContainer?

    private var section: Section = .github
    /// Which item each section was last left on.
    private var selection: [Section: String] = [:]
    /// What the last health check said, per plain project, so the form can show it.
    private var localStatuses: [String: LocalProjectStatus] = [:]

    private var accountRow: AccountRowView?
    private var gitlabRow: GitLabAccountRowView?
    private var projectRow: ProjectRowView?
    private var ddevRow: DDEVProjectRowView?
    private var localRow: LocalProjectRowView?

    /// One list column instead of a sidebar and a list. Six buttons in a column of their own
    /// was 184 points spent on a choice a heading makes just as well, in an app with about
    /// thirty settings in it, and the forms wanted those points more. It also puts every page
    /// over the width where the label gutter used to change under them.
    private static let listWidth: CGFloat = 232

    init(
        tokenStore: any TokenStore,
        accountsStore: GitHubAccountsStore,
        gitlabAccountsStore: GitLabAccountsStore,
        projectsStore: ArcProjectsStore,
        ddevProjectsStore: DDEVProjectsStore,
        localProjectsStore: LocalProjectsStore,
        preferences: Preferences,
        onChanged: @escaping () -> Void
    ) {
        self.tokenStore = tokenStore
        self.accountsStore = accountsStore
        self.gitlabAccountsStore = gitlabAccountsStore
        self.projectsStore = projectsStore
        self.ddevProjectsStore = ddevProjectsStore
        self.localProjectsStore = localProjectsStore
        self.preferences = preferences
        self.onChanged = onChanged
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
            frame: NSRect(
                x: 0,
                y: 0,
                width: Self.listWidth,
                height: content.bounds.height
            )
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
        list.setAddOptions(Section.addable.map(\.addTitle))
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

    // MARK: Sections

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

    // MARK: The list column

    private func reloadList() {
        guard let list else { return }

        // Every kind at once, because the list is the sections now. General is pinned at the
        // top as a row of its own: it is a page rather than a list, and putting it anywhere
        // else would leave it as the one thing you reach differently from everything else.
        var sections: [SettingsListSection] = [
            SettingsListSection(
                title: "Deck",
                items: [SettingsListItem(
                    id: Self.entryID(.general, "general"),
                    title: "General",
                    subtitle: "The deck, notifications, the shortcut",
                    state: nil
                )],
                isAddable: false
            ),
        ]

        sections.append(SettingsListSection(title: Section.github.title, items: accountsStore.accounts().map { account in
            let hasToken = ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
            return SettingsListItem(
                id: Self.entryID(.github, account.id),
                title: account.label,
                subtitle: hasToken ? "token stored" : "no token yet",
                state: account.isEnabled ? (hasToken ? .systemGreen : .systemOrange) : .tertiaryLabelColor
            )
        }))

        sections.append(SettingsListSection(title: Section.gitlab.title, items: gitlabAccountsStore.accounts().map { account in
            let hasToken = ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
            return SettingsListItem(
                id: Self.entryID(.gitlab, account.id),
                title: account.label,
                subtitle: hasToken ? account.displayHost : "no token yet",
                state: account.isEnabled ? (hasToken ? .systemGreen : .systemOrange) : .tertiaryLabelColor
            )
        }))

        sections.append(SettingsListSection(title: Section.arc.title, items: projectsStore.projects().map { project in
            SettingsListItem(
                id: Self.entryID(.arc, project.id),
                title: project.title,
                subtitle: project.organization.isEmpty ? "no organisation" : project.organization,
                state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
            )
        }))

        sections.append(SettingsListSection(title: Section.ddev.title, items: ddevProjectsStore.projects().map { project in
            SettingsListItem(
                id: Self.entryID(.ddev, project.id),
                title: project.displayTitle,
                subtitle: project.name,
                state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
            )
        }))

        sections.append(SettingsListSection(title: Section.project.title, items: localProjectsStore.projects().map { project in
            SettingsListItem(
                id: Self.entryID(.project, project.id),
                title: project.displayTitle,
                // The command rather than the folder: with several checkouts under one parent
                // the folder names look alike, and the command is what differs.
                subtitle: project.startCommand.isEmpty ? "no start command" : project.startCommand,
                state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
            )
        }))

        let wanted = section == .general
            ? Self.entryID(.general, "general")
            : selection[section].map { Self.entryID(section, $0) }
        let ids = sections.flatMap { $0.items.map(\.id) }
        let valid = ids.contains(where: { $0 == wanted }) ? wanted : ids.first
        if let valid, let entry = Self.parse(valid) {
            section = entry.section
            if entry.section != .general { selection[entry.section] = entry.id }
        }
        list.show(sections, selecting: valid)
    }

    // MARK: The form column

    private func reloadDetail() {
        guard let detailScroll else { return }

        accountRow = nil
        projectRow = nil
        ddevRow = nil
        localRow = nil

        let width = max(detailScroll.contentSize.width, 320)
        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        detail = container

        switch section {
        case .github:
            buildAccountForm(in: container, width: width)
        case .gitlab:
            buildGitLabForm(in: container, width: width)
        case .arc:
            buildArcForm(in: container, width: width)
        case .ddev:
            buildDDEVForm(in: container, width: width)
        case .project:
            buildLocalProjectForm(in: container, width: width)
        case .general:
            buildGeneralForm(in: container, width: width)
        }

        container.frame.size.height = max(
            container.subviews.map { $0.frame.maxY }.max() ?? 0,
            detailScroll.contentSize.height
        )
        detailScroll.documentView = container
    }

    private func place(_ row: NSView, in container: FlippedContainer) {
        row.frame.origin = .zero
        container.addSubview(row)
    }

    private func emptyState(_ text: String, in container: FlippedContainer, width: CGFloat) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.secondaryLabelColor
        label.frame = NSRect(x: 20, y: 20, width: width - 40, height: 40)
        container.addSubview(label)
    }

    private func buildAccountForm(in container: FlippedContainer, width: CGFloat) {
        guard let id = selection[.github],
              let account = accountsStore.accounts().first(where: { $0.id == id })
        else {
            emptyState("No accounts yet. Press + below the list.", in: container, width: width)
            return
        }

        let hasToken = ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
        let row = AccountRowView(account: account, hasToken: hasToken, width: width)
        row.onChange = { [weak self] in self?.applyAccountEdits($0) }
        row.onSave = { [weak self] in self?.saveAccount($0) }
        row.onTestLink = { [weak self] in self?.testAccountLink($0) }
        place(row, in: container)
        accountRow = row
    }

    private func buildGitLabForm(in container: FlippedContainer, width: CGFloat) {
        guard let id = selection[.gitlab],
              let account = gitlabAccountsStore.accounts().first(where: { $0.id == id })
        else {
            emptyState(
                "No GitLab instances yet. Press + below the list, then paste a token with read_api.",
                in: container,
                width: width
            )
            return
        }

        let hasToken = ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
        let row = GitLabAccountRowView(account: account, hasToken: hasToken, width: width)
        row.onChange = { [weak self] in self?.applyGitLabEdits($0) }
        row.onSave = { [weak self] in self?.saveGitLabAccount($0) }
        row.onTestLink = { [weak self] in self?.testGitLabLink($0) }
        place(row, in: container)
        gitlabRow = row
    }

    private func buildArcForm(in container: FlippedContainer, width: CGFloat) {
        guard let id = selection[.arc],
              let project = projectsStore.projects().first(where: { $0.id == id })
        else {
            emptyState("No Arc projects yet. Press + below the list.", in: container, width: width)
            return
        }

        let row = ProjectRowView(project: project, width: width)
        row.onChange = { [weak self] in self?.applyProjectEdits($0) }
        row.onTestLink = { [weak self] in self?.testProjectLink($0) }
        row.onChooseFolder = { [weak self] in self?.chooseFolder($0) }
        row.onStructureChange = { [weak self] _, project in
            guard let self else { return }
            var projects = self.projectsStore.projects()
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
                self.projectsStore.save(projects)
            }
            self.onChanged()
            // Rebuilt rather than reloaded: a link was added or removed, so the form has a
            // different number of rows than the one on screen.
            self.reloadDetail()
        }
        place(row, in: container)
        projectRow = row
    }

    private func buildDDEVForm(in container: FlippedContainer, width: CGFloat) {
        guard let id = selection[.ddev],
              let project = ddevProjectsStore.projects().first(where: { $0.id == id })
        else {
            emptyState(
                "No DDEV projects yet. Press + below the list and pick one ddev already knows.",
                in: container,
                width: width
            )
            return
        }

        let row = DDEVProjectRowView(project: project, width: width)
        row.onChange = { [weak self] in self?.applyDDEVEdits($0) }
        row.onTestLink = { [weak self] in self?.testDDEVLink($0) }
        row.onChooseFolder = { [weak self] in self?.chooseDDEVFolder($0) }
        place(row, in: container)
        ddevRow = row
    }

    private func buildLocalProjectForm(in container: FlippedContainer, width: CGFloat) {
        guard let id = selection[.project],
              let project = localProjectsStore.projects().first(where: { $0.id == id })
        else {
            emptyState(
                "No projects yet. Press + below the list and pick a folder. Anything with a "
                    + "folder and a command belongs here: docker compose, a dev server, a Makefile.",
                in: container,
                width: width
            )
            return
        }

        let row = LocalProjectRowView(
            project: project,
            status: localStatuses[project.id] ?? .unavailable,
            width: width
        )
        row.onChange = { [weak self] in self?.applyLocalProjectEdits($0) }
        row.onTestLink = { [weak self] in self?.testLocalProjectLink($0) }
        row.onChooseFolder = { [weak self] in self?.chooseLocalProjectFolder($0) }
        row.onDetect = { [weak self] in self?.detectLocalProject($0) }
        row.onCheckHealth = { [weak self] in self?.checkLocalProjectHealth($0.editedProject) }
        row.onOpenLink = { [weak self] row, index in
            guard let url = row.linkURL(at: index) else { return }
            self?.applyLocalProjectEdits(row)
            LinkOpener.open(url, using: row.editedProject.browser)
        }
        place(row, in: container)
        localRow = row

        // The form is where someone lands when a card is misconfigured, and until now it said
        // nothing about whether the settings actually work. Checked on arrival rather than on
        // demand, because the answer is the point of the group it sits in.
        if localStatuses[project.id] == nil {
            checkLocalProjectHealth(project)
        }
    }

    /// Kept so the Default button can put the field back without rebuilding the page.
    private weak var summonRecorder: HotKeyRecorderView?
    private let actionsField = NSTextField()

    /// The intervals worth offering. Below a minute is polling, and above ten the deck stops
    /// being something you glance at.
    private static let refreshChoices: [(title: String, seconds: Int)] = [
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300),
        ("10 minutes", 600),
    ]

    private func buildGeneralForm(in container: FlippedContainer, width: CGFloat) {
        let form = FormLayout(in: container)
        form.header("About")
        form.beginGroup()

        let version = NSTextField(labelWithString: AppVersion.summary)
        version.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        form.row("Version", [(version, nil)], height: 18)

        let location = NSTextField(labelWithString: AppVersion.location)
        location.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        location.lineBreakMode = .byTruncatingMiddle
        location.textColor = NSColor.secondaryLabelColor
        form.row("Running from", [(location, nil)], height: 18)

        form.endGroup()

        form.header("Fetching")
        form.beginGroup()

        let interval = NSPopUpButton()
        for choice in Self.refreshChoices {
            interval.addItem(withTitle: choice.title)
            interval.lastItem?.representedObject = choice.seconds
        }
        interval.selectItem(at: Self.refreshChoices.firstIndex { $0.seconds == Int(preferences.refreshIntervalSeconds) } ?? 1)
        interval.target = self
        interval.action = #selector(refreshIntervalChanged(_:))
        form.row("Refresh every", [(interval, 160)], height: 24)

        actionsField.stringValue = preferences.actionsRepositories.joined(separator: ", ")
        actionsField.placeholderString = "owner/name, owner/name"
        actionsField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        actionsField.delegate = self
        form.row("Actions", [(actionsField, nil)])
        form.endGroup()
        form.footnote("An empty Actions list follows the repositories your open pull requests are "
            + "in, up to five per account, which is the right default for one person's deck. The "
            + "refresh interval is a floor: GitHub says how often it wants to be polled for "
            + "notifications, and that is honoured when it asks for less.")
        form.footnote("The build number is the commit count, so it moves on every rebuild, the "
            + "quickest way to tell whether the copy in front of you is the change you just made.")

        form.header("Where the panels sit")
        form.beginGroup()

        let placement = NSPopUpButton()
        for mode in DisplayMode.allCases {
            placement.addItem(withTitle: mode.settingsTitle)
            placement.lastItem?.representedObject = mode.rawValue
        }
        placement.selectItem(at: DisplayMode.allCases.firstIndex(of: preferences.displayMode) ?? 0)
        placement.target = self
        placement.action = #selector(placementChanged(_:))
        form.row("Panels", [(placement, 240)], height: 24)

        form.toggleRow(
            deckSwitch(preferences.isLocked, action: #selector(lockChanged(_:))),
            title: "Lock position",
            subtitle: "Stops a stray drag moving a panel. It does not stop the deck packing a column."
        )
        form.toggleRow(
            deckSwitch(preferences.packsColumns, action: #selector(packingChanged(_:))),
            title: "Keep the column packed",
            subtitle: "Closes the gaps when a card changes height, so a gap left on purpose will not survive."
        )
        form.endGroup()
        form.footnote("Tidy, which sorts the deck and wraps it into columns, stays in the menu-bar "
            + "menu: it is something you do rather than something you set.")

        form.header("Summoning")
        form.beginGroup()

        form.toggleRow(
            deckSwitch(preferences.summonEnabled, action: #selector(summonChanged(_:))),
            title: "Raise the deck while the shortcut is held",
            subtitle: "Let go and it drops back. A tap keeps it up until the next press."
        )
        form.toggleRow(
            deckSwitch(preferences.summonDims, action: #selector(summonDimChanged(_:))),
            title: "Dim the screen while it is up",
            subtitle: "Dark glass over a white editor is close to unreadable without it."
        )

        let recorder = HotKeyRecorderView(combo: preferences.summonHotKey)
        recorder.onChange = { [weak self] combo in
            guard let self else { return }
            self.preferences.summonHotKey = combo
            // The app delegate re-registers on this: a shortcut saved but not registered is a
            // setting that lies until the next launch.
            self.onChanged()
        }

        let reset = NSButton(title: "Default", target: nil, action: nil)
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.target = self
        reset.action = #selector(resetSummonHotKey(_:))
        summonRecorder = recorder

        form.row("Shortcut", [(recorder, 120), (reset, 74)], height: 26)
        form.endGroup()
        form.footnote("At least one modifier is required: a bare key would be taken from every "
            + "application on the machine, so pressing it in an editor would raise the deck "
            + "instead of typing.")

        form.header("Notifications")
        form.beginGroup()
        form.toggleRow(
            deckSwitch(preferences.notificationsEnabled, action: #selector(notificationsChanged(_:))),
            title: "Let DevDeck notify me",
            subtitle: "The master switch. What you are told about is set per account."
        )
        let test = NSButton(title: "Send a test", target: self, action: #selector(sendTestNotification))
        test.bezelStyle = .rounded
        test.controlSize = .small
        form.row("Check it", [(test, 96)], height: 24)
        form.endGroup()
        form.footnote("Switching it on is what asks macOS for permission. Which accounts may "
            + "interrupt you, and about what, lives in each account's own form under GitHub "
            + "accounts and GitLab instances. Nothing is announced on the first answer after a "
            + "launch, since that is the state you left things in.")

        form.header("System")
        form.beginGroup()
        form.toggleRow(
            deckSwitch(LoginItem.isEnabled, action: #selector(loginItemChanged(_:))),
            title: "Start at login",
            subtitle: "Read from macOS itself, so removing it in System Settings shows here too."
        )
        form.endGroup()
    }

    /// The switches in this section all look the same and all do the same two things: write one
    /// preference, then let the deck act on it.
    private func deckSwitch(_ isOn: Bool, action: Selector) -> NSButton {
        let button = NSButton()
        button.setButtonType(.switch)
        button.title = ""
        button.state = isOn ? .on : .off
        button.target = self
        button.action = action
        return button
    }

    @objc private func refreshIntervalChanged(_ sender: NSPopUpButton) {
        guard let seconds = sender.selectedItem?.representedObject as? Int else { return }
        preferences.refreshIntervalSeconds = TimeInterval(seconds)
        onChanged()
    }

    @objc private func placementChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = DisplayMode(rawValue: raw)
        else { return }
        preferences.displayMode = mode
        onChanged()
    }

    @objc private func lockChanged(_ sender: NSButton) {
        preferences.isLocked = sender.state == .on
        onChanged()
    }

    @objc private func packingChanged(_ sender: NSButton) {
        preferences.packsColumns = sender.state == .on
        onChanged()
    }

    @objc private func summonChanged(_ sender: NSButton) {
        preferences.summonEnabled = sender.state == .on
        onChanged()
    }

    @objc private func summonDimChanged(_ sender: NSButton) {
        preferences.summonDims = sender.state == .on
        onChanged()
    }

    @objc private func sendTestNotification() {
        onTestNotification()
    }

    /// Turning it on asks macOS for permission, and the switch goes back if the answer is no: a
    /// switch that says "on" while nothing can be delivered is a setting that lies.
    @objc private func notificationsChanged(_ sender: NSButton) {
        guard sender.state == .on else {
            preferences.notificationsEnabled = false
            return
        }
        onRequestNotifications { [weak self] granted in
            self?.preferences.notificationsEnabled = granted
            sender.state = granted ? .on : .off
            if !granted {
                let alert = NSAlert()
                alert.messageText = "macOS is not allowing DevDeck to notify you"
                alert.informativeText = "Turn it on under System Settings, Notifications, DevDeck."
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    @objc private func loginItemChanged(_ sender: NSButton) {
        // Put back to whatever macOS ended up doing rather than to what was asked for: the
        // registration can fail, and a switch that stays on while the login item is not is a
        // setting that lies.
        sender.state = LoginItem.set(sender.state == .on) ? .on : .off
    }

    @objc private func resetSummonHotKey(_ sender: NSButton) {
        preferences.summonHotKey = .optionSpace
        summonRecorder?.set(.optionSpace)
        onChanged()
    }

    // MARK: Adding and removing

    private func addItem(forMenuTitle title: String) {
        guard let kind = Section.addable.first(where: { $0.addTitle == title }) else { return }
        section = kind
        addItem()
    }

    private func addItem() {
        switch section {
        case .github:
            var accounts = accountsStore.accounts()
            let id = GitHubAccount.makeID(from: "account", existing: accounts.map(\.id))
            accounts.append(GitHubAccount(id: id, label: "New account"))
            accountsStore.save(accounts)
            selection[.github] = id
        case .gitlab:
            var accounts = gitlabAccountsStore.accounts()
            let id = GitLabAccount.makeID(from: "gitlab", existing: accounts.map(\.id))
            accounts.append(GitLabAccount(id: id, label: "GitLab"))
            gitlabAccountsStore.save(accounts)
            selection[.gitlab] = id
            // The card is off by default, and adding an instance is the moment it becomes worth
            // having. Turning it on by hand afterwards is a step nobody would guess at.
            var layout = preferences.cardLayout
            layout.setEnabled(true, for: .gitlabMergeRequests)
            preferences.cardLayout = layout
            onChanged()
        case .arc:
            var projects = projectsStore.projects()
            let id = ArcProject.makeID(from: "project", existing: projects.map(\.id))
            projects.append(ArcProject(id: id, title: "New project", organization: ""))
            projectsStore.save(projects)
            selection[.arc] = id
            onChanged()
        case .ddev:
            // DDEV knows its own projects, so the sensible "add" is a list to pick from rather
            // than a folder to go hunting for.
            addDDEVProject()
            return
        case .project:
            // Nothing knows about these projects, so the folder is the one thing that has to be
            // asked for - and once it is known, the folder itself answers most of the rest.
            addLocalProject()
            return
        case .general:
            return
        }
        reloadList()
        reloadDetail()
    }

    private func removeSelected() {
        switch section {
        case .github:
            guard let id = selection[.github],
                  let account = accountsStore.accounts().first(where: { $0.id == id }),
                  confirm("Remove \(account.label)?", detail: "Its token is deleted from the Keychain as well.")
            else { return }
            try? tokenStore.setToken(nil, for: account.tokenKey)
            accountsStore.save(accountsStore.accounts().filter { $0.id != id })
        case .gitlab:
            guard let id = selection[.gitlab],
                  let account = gitlabAccountsStore.accounts().first(where: { $0.id == id }),
                  confirm("Remove \(account.label)?", detail: "Its token is deleted from the Keychain as well.")
            else { return }
            try? tokenStore.setToken(nil, for: account.tokenKey)
            gitlabAccountsStore.save(gitlabAccountsStore.accounts().filter { $0.id != id })
        case .arc:
            guard let id = selection[.arc],
                  let project = projectsStore.projects().first(where: { $0.id == id }),
                  confirm("Remove \(project.title)?", detail: "The card disappears from the deck.")
            else { return }
            projectsStore.save(projectsStore.projects().filter { $0.id != id })
        case .ddev:
            guard let id = selection[.ddev],
                  let project = ddevProjectsStore.projects().first(where: { $0.id == id }),
                  confirm(
                      "Remove \(project.displayTitle)?",
                      detail: "The card disappears from the deck. The project itself is untouched."
                  )
            else { return }
            ddevProjectsStore.save(ddevProjectsStore.projects().filter { $0.id != id })
        case .project:
            guard let id = selection[.project],
                  let project = localProjectsStore.projects().first(where: { $0.id == id }),
                  confirm(
                      "Remove \(project.displayTitle)?",
                      detail: "The card disappears from the deck. Anything it started keeps running."
                  )
            else { return }
            localProjectsStore.save(localProjectsStore.projects().filter { $0.id != id })
        case .general:
            return
        }

        selection[section] = nil
        reloadList()
        reloadDetail()
        onChanged()
    }

    // MARK: GitHub accounts

    private func applyAccountEdits(_ row: AccountRowView) {
        let edited = row.editedAccount
        persist(edited)
        row.apply(edited)
        row.setStatus(Self.browserSummary(browser: edited.browser))
        reloadList()
        onChanged()
    }

    private func testAccountLink(_ row: AccountRowView) {
        applyAccountEdits(row)
        guard let url = URL(string: "https://github.com/pulls") else { return }
        LinkOpener.open(url, using: row.editedAccount.browser)
    }

    private func applyGitLabEdits(_ row: GitLabAccountRowView) {
        let edited = row.editedAccount
        persistGitLab(edited)
        row.apply(edited)
        row.setStatus(Self.browserSummary(browser: edited.browser))
        reloadList()
        onChanged()
    }

    private func testGitLabLink(_ row: GitLabAccountRowView) {
        applyGitLabEdits(row)
        let account = row.editedAccount
        LinkOpener.open(
            account.host.appendingPathComponent("dashboard").appendingPathComponent("merge_requests"),
            using: account.browser
        )
    }

    private func persistGitLab(_ account: GitLabAccount) {
        var accounts = gitlabAccountsStore.accounts()
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        gitlabAccountsStore.save(accounts)
    }

    /// Verified before it is stored, the same as a GitHub token: a rejected token that lands in
    /// the Keychain anyway turns into a card that fails for reasons nobody can see.
    private func saveGitLabAccount(_ row: GitLabAccountRowView) {
        let edited = row.editedAccount
        let token = row.enteredToken

        guard !token.isEmpty else {
            persistGitLab(edited)
            row.apply(edited)
            verifyStoredGitLabToken(for: edited, row: row)
            onChanged()
            return
        }

        row.setStatus("Checking…")
        Task { [weak self] in
            guard let self else { return }
            let probe = GitLabClient.makeDefault(
                account: edited,
                tokenStore: InMemoryTokenStore(tokens: [edited.tokenKey: token])
            )
            do {
                let snapshot = try await MergeRequestsService(client: probe, accountID: edited.id).fetch()
                try self.tokenStore.setToken(token, for: edited.tokenKey)
                self.persistGitLab(edited)
                row.apply(edited)
                row.clearTokenField()
                row.setStatus("Saved. \(snapshot.totalCount) open merge requests on \(edited.displayHost).")
                self.reloadList()
                self.onChanged()
            } catch let error as APIError {
                row.setStatus("Rejected: \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Rejected: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func verifyStoredGitLabToken(for account: GitLabAccount, row: GitLabAccountRowView) {
        guard ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil else {
            row.setStatus("No token yet. Paste one above.", isError: true)
            return
        }
        row.setStatus("Checking the stored token…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await MergeRequestsService(
                    client: GitLabClient.makeDefault(account: account, tokenStore: self.tokenStore),
                    accountID: account.id
                ).fetch()
                row.setStatus("Token works. \(snapshot.totalCount) open merge requests.")
            } catch let error as APIError {
                row.setStatus("Stored token: \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Stored token: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private static func browserSummary(browser: BrowserChoice) -> String {
        guard let identifier = browser.bundleIdentifier else {
            return "Saved. Links open in the default browser."
        }
        let name = BrowserCatalog.browser(withIdentifier: identifier)?.name ?? identifier
        guard let profile = browser.profileDirectory else { return "Saved. Links open in \(name)." }
        return "Saved. Links open in \(name) · \(profile)."
    }

    private func saveAccount(_ row: AccountRowView) {
        let edited = row.editedAccount
        let token = row.enteredToken

        guard !token.isEmpty else {
            persist(edited)
            row.apply(edited)
            verifyStoredToken(for: edited, row: row)
            onChanged()
            return
        }

        row.setStatus("Checking…")
        Task { [weak self] in
            guard let self else { return }
            // Verify before storing: a rejected token that silently lands in the Keychain turns
            // into a card that fails for reasons nobody can see.
            let probe = GitHubClient.makeDefault(
                tokenStore: InMemoryTokenStore(tokens: [edited.tokenKey: token]),
                settings: edited.settings(basedOn: .default),
                tokenKey: edited.tokenKey
            )
            do {
                let snapshot = try await PullRequestsService(
                    client: probe,
                    settings: edited.settings(basedOn: .default),
                    accountID: edited.id
                ).fetch()
                try self.tokenStore.setToken(token, for: edited.tokenKey)
                self.persist(edited)
                row.apply(edited)
                row.clearTokenField()
                row.setStatus("Saved. \(snapshot.totalCount) open pull requests.")
                self.reloadList()
                self.onChanged()
            } catch let error as APIError {
                row.setStatus("Rejected: \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Rejected: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func verifyStoredToken(for account: GitHubAccount, row: AccountRowView) {
        guard ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil else {
            row.setStatus("No token yet. Paste one above.", isError: true)
            return
        }
        row.setStatus("Checking the stored token…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await PullRequestsService(
                    client: GitHubClient.makeDefault(
                        tokenStore: self.tokenStore,
                        settings: account.settings(basedOn: .default),
                        tokenKey: account.tokenKey
                    ),
                    settings: account.settings(basedOn: .default),
                    accountID: account.id
                ).fetch()
                row.setStatus("Token works. \(snapshot.totalCount) open pull requests.")
            } catch let error as APIError {
                row.setStatus("Stored token: \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Stored token: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func persist(_ account: GitHubAccount) {
        var accounts = accountsStore.accounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accountsStore.save(accounts)
    }

    // MARK: Arc projects

    private func applyProjectEdits(_ row: ProjectRowView) {
        let edited = row.editedProject
        var projects = projectsStore.projects()
        if let index = projects.firstIndex(where: { $0.id == edited.id }) {
            projects[index] = edited
        } else {
            projects.append(edited)
        }
        projectsStore.save(projects)
        row.apply(edited)
        row.setStatus(Self.browserSummary(browser: edited.browser))
        reloadList()
        onChanged()
    }

    private func testProjectLink(_ row: ProjectRowView) {
        applyProjectEdits(row)
        let project = row.editedProject
        guard let link = project.resolvedLinks.first else {
            row.setStatus("No enabled link to test.", isError: true)
            return
        }
        row.setStatus("Opening \(link.url.absoluteString)")
        LinkOpener.open(link.url, using: project.browser)
    }

    private func chooseFolder(_ row: ProjectRowView) {
        guard let url = chooseDirectory(message: "Pick the project checkout: the folder the fusion commands run in.")
        else { return }
        row.setFolder(url.path)
    }

    // MARK: DDEV projects

    /// Offers what `ddev list` found rather than making the user go looking for a folder.
    private func addDDEVProject() {
        Task { [weak self] in
            guard let self else { return }
            guard let entries = await self.ddevEnvironment.list() else {
                self.presentDDEVUnavailable()
                return
            }

            let known = Set(self.ddevProjectsStore.projects().map(\.name))
            let candidates = entries.filter { !known.contains($0.name) }

            guard !candidates.isEmpty else {
                let alert = NSAlert()
                alert.messageText = entries.isEmpty
                    ? "ddev has no projects"
                    : "Every DDEV project is already on the deck"
                alert.informativeText = entries.isEmpty
                    ? "Run ddev config in a project folder first."
                    : "Nothing left to add."
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            let alert = NSAlert()
            alert.messageText = "Add a DDEV project"
            alert.informativeText = "Found by ddev list."
            let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
            for candidate in candidates {
                popUp.addItem(withTitle: "\(candidate.name) (\(candidate.state.rawValue))")
            }
            alert.accessoryView = popUp
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let index = max(0, min(popUp.indexOfSelectedItem, candidates.count - 1))
            let chosen = candidates[index]
            var projects = self.ddevProjectsStore.projects()
            let id = DDEVProject.makeID(from: chosen.name, existing: projects.map(\.id))
            projects.append(DDEVProject(id: id, name: chosen.name, folder: chosen.approot))
            self.ddevProjectsStore.save(projects)
            self.selection[.ddev] = id
            self.reloadList()
            self.reloadDetail()
            self.onChanged()
        }
    }

    private func presentDDEVUnavailable() {
        let alert = NSAlert()
        alert.messageText = "ddev did not answer"
        alert.informativeText = "Either DDEV is not installed, or it is not on the PATH a login "
            + "shell sees. Running ddev list in a terminal will say which."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func applyDDEVEdits(_ row: DDEVProjectRowView) {
        let edited = row.editedProject
        var projects = ddevProjectsStore.projects()
        if let index = projects.firstIndex(where: { $0.id == edited.id }) {
            projects[index] = edited
        } else {
            projects.append(edited)
        }
        ddevProjectsStore.save(projects)
        row.apply(edited)
        row.setStatus(Self.browserSummary(browser: edited.browser))
        reloadList()
        onChanged()
    }

    private func testDDEVLink(_ row: DDEVProjectRowView) {
        applyDDEVEdits(row)
        let project = row.editedProject

        Task { [weak self] in
            guard let self else { return }
            let entries = await self.ddevEnvironment.list()
            let status = self.ddevEnvironment.status(for: project, entries: entries)
            guard let link = project.links(status: status).first else {
                row.setStatus("ddev has no URL for this project yet.", isError: true)
                return
            }
            row.setStatus("Opening \(link.url.absoluteString)")
            LinkOpener.open(link.url, using: project.browser)
        }
    }

    private func chooseDDEVFolder(_ row: DDEVProjectRowView) {
        guard let url = chooseDirectory(message: "Pick the project checkout: the folder holding .ddev.")
        else { return }
        // Said plainly rather than refused: the folder may be right and the project not set up
        // yet, and that is the user's business.
        if !DDEVConfig.isProject(url) {
            row.setStatus("No .ddev/config.yaml in that folder.", isError: true)
        }
        row.setFolder(url.path)
    }

    // MARK: Plain projects

    /// Adds a project from a folder, filling in what the folder already says about itself.
    private func addLocalProject() {
        guard let url = chooseDirectory(
            message: "Pick the project folder: the one its start command runs in."
        ) else { return }

        var projects = localProjectsStore.projects()
        let name = url.lastPathComponent
        let id = LocalProject.makeID(from: name, existing: projects.map(\.id))
        var project = LocalProject(id: id, title: name, folder: url.path)

        // Applied on creation only. From here on the fields belong to the user, and a later
        // guess must never quietly replace what they typed - the Detect button is how they ask
        // for one.
        if let suggestion = ProjectProbe.suggestion(for: url) {
            project.subtitle = suggestion.subtitle
            project.startCommand = suggestion.startCommand
            project.stopCommand = suggestion.stopCommand
            project.holdsProcess = suggestion.holdsProcess
            project.requiresDocker = suggestion.requiresDocker
            project.healthURL = suggestion.healthURL
        }

        projects.append(project)
        localProjectsStore.save(projects)
        selection[.project] = id
        reloadList()
        reloadDetail()
        onChanged()
    }

    private func applyLocalProjectEdits(_ row: LocalProjectRowView) {
        let edited = row.editedProject
        var projects = localProjectsStore.projects()
        if let index = projects.firstIndex(where: { $0.id == edited.id }) {
            projects[index] = edited
        } else {
            projects.append(edited)
        }
        localProjectsStore.save(projects)
        row.apply(edited)
        row.setStatus(Self.browserSummary(browser: edited.browser))
        reloadList()
        onChanged()
    }

    private func testLocalProjectLink(_ row: LocalProjectRowView) {
        applyLocalProjectEdits(row)
        let project = row.editedProject
        guard let link = project.environmentLinks().first ?? project.toolLinks().first else {
            row.setStatus("No link to test. Set a health URL or an environment.", isError: true)
            return
        }
        row.setStatus("Opening \(link.url.absoluteString)")
        LinkOpener.open(link.url, using: project.browser)
    }

    private func chooseLocalProjectFolder(_ row: LocalProjectRowView) {
        guard let url = chooseDirectory(
            message: "Pick the project folder: the one its start command runs in."
        ) else { return }
        row.setFolder(url.path)
    }

    /// Asks the project's health URL and redraws the form with the answer.
    private func checkLocalProjectHealth(_ project: LocalProject) {
        Task { [weak self] in
            guard let self else { return }
            let status = await LocalProjectService(project: project).status()
            self.localStatuses[project.id] = status
            // Only if the user is still looking at this project - the check takes a moment and
            // they may have moved on.
            guard self.section == .project, self.selection[.project] == project.id else { return }
            self.reloadDetail()
        }
    }

    private func detectLocalProject(_ row: LocalProjectRowView) {
        guard let folder = row.editedProject.folderURL else {
            row.setStatus("Set a folder first.", isError: true)
            return
        }
        guard let suggestion = ProjectProbe.suggestion(for: folder) else {
            row.setStatus(
                "Nothing recognisable in that folder: no compose file, package.json script or Makefile target.",
                isError: true
            )
            return
        }
        row.applySuggestion(suggestion)
        row.setStatus("Filled in from the folder: \(suggestion.startCommand)")
    }

    // MARK: Shared

    private func chooseDirectory(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func confirm(_ message: String, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}


extension SettingsWindowController: NSTextFieldDelegate {
    /// Text commits when the field is left, the same as everywhere else in this window.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSTextField) === actionsField else { return }
        preferences.actionsRepositories = actionsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onChanged()
    }
}
