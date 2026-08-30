import AppKit
import ArcKit
import DDEVKit
import DevDeckCore
import GitHubKit
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
        case arc
        case ddev
        case project
        case general

        var title: String {
            switch self {
            case .github: return "GitHub accounts"
            case .arc: return "Arc projects"
            case .ddev: return "DDEV projects"
            case .project: return "Projects"
            case .general: return "General"
            }
        }

        /// General is a page, not a list of things.
        var hasList: Bool { self != .general }
    }

    private let tokenStore: any TokenStore
    private let accountsStore: GitHubAccountsStore
    private let projectsStore: ArcProjectsStore
    private let ddevProjectsStore: DDEVProjectsStore
    private let localProjectsStore: LocalProjectsStore
    private let ddevEnvironment = DDEVEnvironment()
    private let preferences: Preferences
    private let onChanged: () -> Void

    private var window: NSWindow?
    private var sidebar: NSView?
    private var sidebarButtons: [Section: NSButton] = [:]
    private var list: SettingsListView?
    private var detailScroll: NSScrollView?
    private var detail: FlippedContainer?

    private var section: Section = .github
    /// Which item each section was last left on.
    private var selection: [Section: String] = [:]
    /// What the last health check said, per plain project, so the form can show it.
    private var localStatuses: [String: LocalProjectStatus] = [:]

    private var accountRow: AccountRowView?
    private var projectRow: ProjectRowView?
    private var ddevRow: DDEVProjectRowView?
    private var localRow: LocalProjectRowView?

    private static let sidebarWidth: CGFloat = 184
    private static let listWidth: CGFloat = 196

    init(
        tokenStore: any TokenStore,
        accountsStore: GitHubAccountsStore,
        projectsStore: ArcProjectsStore,
        ddevProjectsStore: DDEVProjectsStore,
        localProjectsStore: LocalProjectsStore,
        preferences: Preferences,
        onChanged: @escaping () -> Void
    ) {
        self.tokenStore = tokenStore
        self.accountsStore = accountsStore
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

        buildSidebar(in: content)

        let list = SettingsListView(
            frame: NSRect(
                x: Self.sidebarWidth,
                y: 0,
                width: Self.listWidth,
                height: content.bounds.height
            )
        )
        list.autoresizingMask = [.height]
        list.onSelect = { [weak self] id in
            guard let self else { return }
            self.selection[self.section] = id
            self.reloadDetail()
        }
        list.onAdd = { [weak self] in self?.addItem() }
        list.onRemove = { [weak self] in self?.removeSelected() }
        content.addSubview(list)
        self.list = list

        let scroll = NSScrollView(
            frame: NSRect(
                x: Self.sidebarWidth + Self.listWidth,
                y: 0,
                width: content.bounds.width - Self.sidebarWidth - Self.listWidth,
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

    private func buildSidebar(in content: NSView) {
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: content.bounds.height))
        sidebar.autoresizingMask = [.height]
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.underPageBackgroundColor.withAlphaComponent(0.6).cgColor
        content.addSubview(sidebar)
        self.sidebar = sidebar

        let header = NSTextField(labelWithString: "SETTINGS")
        header.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        header.textColor = NSColor.tertiaryLabelColor
        header.frame = NSRect(x: 18, y: content.bounds.height - 40, width: 120, height: 14)
        header.autoresizingMask = [.minYMargin]
        sidebar.addSubview(header)

        var y = content.bounds.height - 68
        for item in Section.allCases {
            let button = NSButton(title: "  " + item.title, target: self, action: #selector(sectionClicked(_:)))
            button.frame = NSRect(x: 10, y: y, width: Self.sidebarWidth - 20, height: 28)
            button.isBordered = false
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 13)
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.layer?.cornerCurve = .continuous
            button.autoresizingMask = [.minYMargin]
            button.identifier = NSUserInterfaceItemIdentifier(item.rawValue)
            sidebar.addSubview(button)
            sidebarButtons[item] = button
            y -= 32
        }

        let separator = NSView(frame: NSRect(x: Self.sidebarWidth - 1, y: 0, width: 1, height: content.bounds.height))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separator.autoresizingMask = [.height]
        sidebar.addSubview(separator)
    }

    func windowDidResize(_ notification: Notification) {
        // The form is laid out for a width, so it is rebuilt when the width changes. Cheap,
        // and it keeps every field stretched to the window instead of stopping short of it.
        reloadDetail()
    }

    // MARK: Sections

    @objc private func sectionClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let item = Section(rawValue: raw) else { return }
        select(item)
    }

    private func select(_ item: Section) {
        section = item

        for (candidate, button) in sidebarButtons {
            let isSelected = candidate == item
            button.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = isSelected ? .white : .labelColor
            button.attributedTitle = NSAttributedString(
                string: "  " + candidate.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
                    .foregroundColor: isSelected ? NSColor.white : NSColor.labelColor,
                ]
            )
        }

        layoutColumns()
        reloadList()
        reloadDetail()
    }

    /// General has nothing to list, so its page takes the list column's width too.
    private func layoutColumns() {
        guard let content = window?.contentView, let list, let detailScroll else { return }
        let showsList = section.hasList
        list.isHidden = !showsList

        let detailLeft = Self.sidebarWidth + (showsList ? Self.listWidth : 0)
        detailScroll.frame = NSRect(
            x: detailLeft,
            y: 0,
            width: content.bounds.width - detailLeft,
            height: content.bounds.height
        )
    }

    // MARK: The list column

    private func reloadList() {
        guard let list else { return }

        let items: [SettingsListItem]
        switch section {
        case .github:
            items = accountsStore.accounts().map { account in
                let hasToken = ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
                return SettingsListItem(
                    id: account.id,
                    title: account.label,
                    subtitle: hasToken ? "token stored" : "no token yet",
                    state: account.isEnabled ? (hasToken ? .systemGreen : .systemOrange) : .tertiaryLabelColor
                )
            }
        case .arc:
            items = projectsStore.projects().map { project in
                SettingsListItem(
                    id: project.id,
                    title: project.title,
                    subtitle: project.organization.isEmpty ? "no organisation" : project.organization,
                    state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
                )
            }
        case .ddev:
            items = ddevProjectsStore.projects().map { project in
                SettingsListItem(
                    id: project.id,
                    title: project.displayTitle,
                    subtitle: project.folderURL?.lastPathComponent ?? "no folder",
                    state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
                )
            }
        case .project:
            items = localProjectsStore.projects().map { project in
                SettingsListItem(
                    id: project.id,
                    title: project.displayTitle,
                    // The command rather than the folder: with several checkouts under one
                    // parent the folder names look alike, and the command is what differs.
                    subtitle: project.startCommand.isEmpty ? "no start command" : project.startCommand,
                    state: project.isEnabled ? .systemGreen : .tertiaryLabelColor
                )
            }
        case .general:
            items = []
        }

        let stored = selection[section]
        let valid = items.contains { $0.id == stored } ? stored : items.first?.id
        selection[section] = valid
        list.show(items, selecting: valid)
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

        let interval = NSTextField(labelWithString: "\(Int(preferences.refreshIntervalSeconds)) seconds")
        interval.font = NSFont.systemFont(ofSize: 13)
        form.row("Refresh", [(interval, nil)], height: 18)
        form.endGroup()
        form.footnote("The build number is the commit count, so it moves on every rebuild, the "
            + "quickest way to tell whether the copy in front of you is the change you just made.")

        form.header("The deck")
        form.beginGroup()

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

        form.row("Summon", [(recorder, 120), (reset, 74)], height: 26)
        form.endGroup()
        form.footnote("Hold it to raise the deck over your windows, let go and it drops back. A "
            + "tap keeps it up until the next press. At least one modifier is required, since a "
            + "bare key would be taken from every application on the machine.")

        form.footnote("Whether the deck is summoned at all, whether the screen dims while it is "
            + "up, placement, locking and start-at-login all live in the menu-bar menu.")
    }

    @objc private func resetSummonHotKey(_ sender: NSButton) {
        preferences.summonHotKey = .optionSpace
        summonRecorder?.set(.optionSpace)
        onChanged()
    }

    // MARK: Adding and removing

    private func addItem() {
        switch section {
        case .github:
            var accounts = accountsStore.accounts()
            let id = GitHubAccount.makeID(from: "account", existing: accounts.map(\.id))
            accounts.append(GitHubAccount(id: id, label: "New account"))
            accountsStore.save(accounts)
            selection[.github] = id
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
