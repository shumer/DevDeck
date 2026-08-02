import AppKit
import ArcKit
import DevDeckCore
import GitHubKit

/// The settings window.
///
/// One window with a sidebar rather than a window per integration: GitHub and Arc share
/// nothing but the browser picker, and mixing their fields in one list is exactly what makes
/// a settings screen unreadable once there are two of anything.
@MainActor
final class SettingsWindowController: NSObject {
    enum Section: String, CaseIterable {
        case github
        case arc
        case general

        var title: String {
            switch self {
            case .github: return "GitHub accounts"
            case .arc: return "Arc projects"
            case .general: return "General"
            }
        }
    }

    private let tokenStore: any TokenStore
    private let accountsStore: GitHubAccountsStore
    private let projectsStore: ArcProjectsStore
    private let preferences: Preferences
    private let onChanged: () -> Void

    private var window: NSWindow?
    private var documentView: NSView?
    private var sidebarButtons: [Section: NSButton] = [:]
    private var addButton: NSButton?
    private var section: Section = .github

    private var accountRows: [AccountRowView] = []
    private var projectRows: [ProjectRowView] = []

    private static let width: CGFloat = 640
    private static let sidebarWidth: CGFloat = 176
    private static let rowWidth: CGFloat = 428

    init(
        tokenStore: any TokenStore,
        accountsStore: GitHubAccountsStore,
        projectsStore: ArcProjectsStore,
        preferences: Preferences,
        onChanged: @escaping () -> Void
    ) {
        self.tokenStore = tokenStore
        self.accountsStore = accountsStore
        self.projectsStore = projectsStore
        self.preferences = preferences
        self.onChanged = onChanged
    }

    func show(_ section: Section = .github) {
        if let window {
            select(section)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DevDeck — Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: Self.width, height: 380)
        window.center()

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))

        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: content.bounds.height))
        sidebar.autoresizingMask = [.height]
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        content.addSubview(sidebar)

        var y = content.bounds.height - 46
        for item in Section.allCases {
            let button = NSButton(title: item.title, target: self, action: #selector(sectionClicked(_:)))
            button.frame = NSRect(x: 10, y: y, width: Self.sidebarWidth - 20, height: 26)
            button.isBordered = false
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 12.5)
            button.autoresizingMask = [.minYMargin]
            button.identifier = NSUserInterfaceItemIdentifier(item.rawValue)
            sidebar.addSubview(button)
            sidebarButtons[item] = button
            y -= 30
        }

        let add = NSButton(title: "Add", target: self, action: #selector(addItem))
        add.frame = NSRect(x: 12, y: 14, width: Self.sidebarWidth - 24, height: 28)
        add.bezelStyle = .rounded
        sidebar.addSubview(add)
        addButton = add

        let scroll = NSScrollView(
            frame: NSRect(
                x: Self.sidebarWidth,
                y: 0,
                width: content.bounds.width - Self.sidebarWidth,
                height: content.bounds.height
            )
        )
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)

        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: Self.rowWidth + 24, height: 0))
        scroll.documentView = document
        documentView = document

        window.contentView = content
        self.window = window

        select(section)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
            button.contentTintColor = isSelected ? .controlAccentColor : .labelColor
            button.font = NSFont.systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .regular)
        }
        addButton?.title = item == .arc ? "Add project" : "Add account"
        addButton?.isHidden = item == .general
        reload()
    }

    @objc private func addItem() {
        switch section {
        case .github:
            var accounts = accountsStore.accounts()
            let id = GitHubAccount.makeID(from: "account", existing: accounts.map(\.id))
            accounts.append(GitHubAccount(id: id, label: "New account"))
            accountsStore.save(accounts)
        case .arc:
            var projects = projectsStore.projects()
            let id = ArcProject.makeID(from: "project", existing: projects.map(\.id))
            projects.append(ArcProject(id: id, title: "New project", organization: ""))
            projectsStore.save(projects)
            onChanged()
        case .general:
            return
        }
        reload()
    }

    private func reload() {
        guard let documentView else { return }
        for view in documentView.subviews { view.removeFromSuperview() }
        accountRows = []
        projectRows = []

        var y: CGFloat = 12
        switch section {
        case .github:
            y = layoutHint(
                "One account per token. A fine-grained token must be approved by each "
                    + "organisation, and the inbox card also needs the account-level notifications "
                    + "permission.",
                at: y,
                in: documentView
            )
            for account in accountsStore.accounts() {
                let hasToken = ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil
                let row = AccountRowView(account: account, hasToken: hasToken, width: Self.rowWidth)
                row.frame.origin = NSPoint(x: 12, y: y)
                row.onSave = { [weak self] in self?.saveAccount($0) }
                row.onRemove = { [weak self] in self?.removeAccount($0) }
                row.onChange = { [weak self] in self?.applyAccountEdits($0) }
                row.onTestLink = { [weak self] in self?.testAccountLink($0) }
                documentView.addSubview(row)
                accountRows.append(row)
                y += AccountRowView.height + 10
            }

        case .arc:
            y = layoutHint(
                "One card per project. Link templates are editable because Arc URLs differ "
                    + "between organisations — press Test to see where one lands.",
                at: y,
                in: documentView
            )
            for project in projectsStore.projects() {
                let row = ProjectRowView(project: project, width: Self.rowWidth)
                row.frame.origin = NSPoint(x: 12, y: y)
                row.onChange = { [weak self] in self?.applyProjectEdits($0) }
                row.onRemove = { [weak self] in self?.removeProject($0) }
                row.onTestLink = { [weak self] in self?.testProjectLink($0) }
                row.onChooseFolder = { [weak self] in self?.chooseFolder($0) }
                documentView.addSubview(row)
                projectRows.append(row)
                y += ProjectRowView.height(for: project) + 10
            }
            if projectsStore.projects().isEmpty {
                y = layoutHint("No projects yet — press Add project.", at: y, in: documentView)
            }

        case .general:
            y = layoutHint(AppVersion.summary, at: y, in: documentView, bold: true)
            y = layoutHint("Running from \(AppVersion.location)", at: y, in: documentView)
            y = layoutHint(
                "Panels refresh every \(Int(preferences.refreshIntervalSeconds)) seconds. "
                    + "Placement, locking and start-at-login live in the menu-bar menu.",
                at: y,
                in: documentView
            )
        }

        documentView.frame = NSRect(x: 0, y: 0, width: Self.rowWidth + 24, height: max(y, 1))
    }

    @discardableResult
    private func layoutHint(
        _ text: String,
        at y: CGFloat,
        in parent: NSView,
        bold: Bool = false
    ) -> CGFloat {
        let hint = NSTextField(wrappingLabelWithString: text)
        hint.frame = NSRect(x: 12, y: y, width: Self.rowWidth, height: bold ? 20 : 46)
        hint.font = NSFont.systemFont(ofSize: bold ? 13 : 11, weight: bold ? .semibold : .regular)
        hint.textColor = bold ? NSColor.labelColor : NSColor.secondaryLabelColor
        hint.isEditable = false
        hint.isSelectable = true
        hint.drawsBackground = false
        parent.addSubview(hint)
        return y + (bold ? 26 : 54)
    }

    // MARK: GitHub accounts

    private func applyAccountEdits(_ row: AccountRowView) {
        let edited = row.editedAccount
        persist(edited)
        row.apply(edited)
        row.setStatus(Self.browserSummary(browser: edited.browser))
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

    private func removeAccount(_ row: AccountRowView) {
        guard confirm(
            "Remove \(row.account.label)?",
            detail: "Its token is deleted from the Keychain as well."
        ) else { return }
        try? tokenStore.setToken(nil, for: row.account.tokenKey)
        accountsStore.save(accountsStore.accounts().filter { $0.id != row.account.id })
        reload()
        onChanged()
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
            // Verify before storing: a rejected token that silently lands in the Keychain
            // turns into a card that fails for reasons nobody can see.
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
                row.setStatus("Saved — \(snapshot.totalCount) open pull requests.")
                self.onChanged()
            } catch let error as APIError {
                row.setStatus("Rejected — \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Rejected — \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func verifyStoredToken(for account: GitHubAccount, row: AccountRowView) {
        guard ((try? tokenStore.token(for: account.tokenKey)) ?? nil) != nil else {
            row.setStatus("No token yet — paste one above.", isError: true)
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
                row.setStatus("Token works — \(snapshot.totalCount) open pull requests.")
            } catch let error as APIError {
                row.setStatus("Stored token — \(error.displayMessage)", isError: true)
            } catch {
                row.setStatus("Stored token — \(error.localizedDescription)", isError: true)
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
        onChanged()
    }

    private func testProjectLink(_ row: ProjectRowView) {
        applyProjectEdits(row)
        let project = row.editedProject
        // The first enabled link is the one the card shows first, so it is the honest thing
        // to test with.
        guard let link = project.resolvedLinks.first else {
            row.setStatus("No enabled link to test.", isError: true)
            return
        }
        row.setStatus("Opening \(link.url.absoluteString)")
        LinkOpener.open(link.url, using: project.browser)
    }

    private func removeProject(_ row: ProjectRowView) {
        guard confirm("Remove \(row.project.title)?", detail: "The card disappears from the deck.") else {
            return
        }
        projectsStore.save(projectsStore.projects().filter { $0.id != row.project.id })
        reload()
        onChanged()
    }

    private func chooseFolder(_ row: ProjectRowView) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick the project checkout — the folder the fusion commands run in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        row.setFolder(url.path)
    }

    // MARK: Shared

    private func confirm(_ message: String, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Rows are laid out from the top, which is the opposite of AppKit's default.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
