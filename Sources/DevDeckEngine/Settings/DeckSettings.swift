import ArcKit
import DDEVKit
import DevDeckCore
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit

// What the settings window decides, in the engine: what the sidebar lists and how, and every
// operation behind a form. Adding, saving and removing accounts and projects, Detect, the checks
// behind each form's status line, and what "test the link" opens. The forms themselves, their
// layout and their labels, are a shell's until the Windows settings are designed (W-10). See
// docs/adr/0031-settings-operations-in-the-engine.md.

/// Which kind of thing a sidebar row is about.
public enum DeckSettingsKind: String, Sendable, Equatable, Codable {
    case github, gitlab, arc, ddev, project
}

/// One row of the settings sidebar.
public struct DeckSettingsItem: Sendable, Equatable, Codable {
    public let kind: DeckSettingsKind
    public let id: String
    public let title: String
    /// What tells two similar rows apart, as a tooltip.
    public let detail: String
    public let mark: DeckMark
    /// Only when the colour means something: running, starting, or a token missing.
    public let tone: DeckTone?
    /// Configured, but not on the deck.
    public let isDimmed: Bool
}

/// The sidebar's two groups, each sorted by title, kinds mixed: a project is found by its name.
public struct DeckSettingsList: Sendable, Equatable, Codable {
    public let accounts: [DeckSettingsItem]
    public let projects: [DeckSettingsItem]
}

/// What Detect found in a folder, in the words its note uses.
public struct DeckDetection: Sendable, Equatable, Codable {
    public let suggestion: ProjectSuggestion?
    public let note: String
    public let isError: Bool
}

/// What testing a form's link comes to: a page to open, or why there is none.
public enum DeckLinkTest: Sendable, Equatable {
    case open(URL, BrowserChoice)
    case note(String)
}

/// What a token check said.
public enum DeckTokenCheck: Sendable, Equatable, Codable {
    case works(String)
    case refused(String)
}

/// DDEV projects that can be added, as `ddev list` reports them.
public enum DeckDDEVCandidates: Sendable, Equatable, Codable {
    /// `ddev list` did not answer.
    case unavailable
    /// It answered with nothing.
    case none
    /// Everything it lists is already on the deck.
    case allAdded
    case some([DDEVListEntry])
}

extension DeckRuntime {
    // MARK: The sidebar

    public func settingsList() -> DeckSettingsList {
        let accounts = accountsStore.accounts().map { account -> DeckSettingsItem in
            let hasToken = hasToken(account.tokenKey)
            return DeckSettingsItem(
                kind: .github,
                id: account.id,
                title: account.label,
                detail: hasToken ? "GitHub" : L("settings.list.noToken", "GitHub"),
                mark: .github,
                tone: hasToken ? nil : .attention,
                isDimmed: !account.isEnabled
            )
        } + gitlabAccountsStore.accounts().map { account -> DeckSettingsItem in
            let hasToken = hasToken(account.tokenKey)
            return DeckSettingsItem(
                kind: .gitlab,
                id: account.id,
                title: account.label,
                detail: hasToken ? account.displayHost : L("settings.list.noToken", account.displayHost),
                mark: .gitlab,
                tone: hasToken ? nil : .attention,
                isDimmed: !account.isEnabled
            )
        }

        let arc = projectsStore.projects().map { project -> DeckSettingsItem in
            let live = stackStatus(for: project).state
            return DeckSettingsItem(
                kind: .arc,
                id: project.id,
                title: project.title,
                detail: project.organization.isEmpty ? "Arc XP" : "Arc XP · \(project.organization)",
                mark: .arc,
                tone: live == .running ? .good : (live == .working ? .attention : nil),
                isDimmed: !project.isEnabled
            )
        }
        let ddev = ddevProjectsStore.projects().map { project -> DeckSettingsItem in
            let live = ddevStatus(for: project).state
            return DeckSettingsItem(
                kind: .ddev,
                id: project.id,
                title: project.displayTitle,
                detail: "DDEV · \(project.name)",
                mark: .ddev,
                tone: live == .running ? .good : (live == .working ? .attention : nil),
                isDimmed: !project.isEnabled
            )
        }
        let local = localProjectsStore.projects().map { project -> DeckSettingsItem in
            let live = localStatus(for: project).state
            return DeckSettingsItem(
                kind: .project,
                id: project.id,
                title: project.displayTitle,
                // The command rather than the folder: with several checkouts under one parent the
                // folder names look alike, and the command is what differs.
                detail: project.startCommand.isEmpty ? L("project.list.noStart") : project.startCommand,
                mark: DeckProjectCardModel.brand(of: project.kind),
                tone: live == .running ? .good : (live == .starting || live == .working ? .attention : nil),
                isDimmed: !project.isEnabled
            )
        }

        func sorted(_ items: [DeckSettingsItem]) -> [DeckSettingsItem] {
            items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return DeckSettingsList(accounts: sorted(accounts), projects: sorted(arc + ddev + local))
    }

    /// Whether an account has a token, without reading what it is.
    public func hasToken(_ key: TokenKey) -> Bool {
        ((try? tokenStore.token(for: key)) ?? nil) != nil
    }

    // MARK: Plain projects

    /// Adds a project from a folder, filling in what the folder says about itself. Applied on
    /// creation only: from then on the fields belong to the user, and Detect is how they ask
    /// for a guess.
    public func addLocalProject(folder: URL) -> String {
        var projects = localProjectsStore.projects()
        let name = folder.lastPathComponent
        let id = LocalProject.makeID(from: name, existing: projects.map(\.id))
        var project = LocalProject(id: id, title: name, folder: folder.path)
        if let suggestion = ProjectProbe.suggestion(for: folder) {
            project.subtitle = suggestion.subtitle
            project.startCommand = suggestion.startCommand
            project.stopCommand = suggestion.stopCommand
            project.holdsProcess = suggestion.holdsProcess
            project.requiresDocker = suggestion.requiresDocker
            project.healthURL = suggestion.healthURL
        }
        projects.append(project)
        localProjectsStore.save(projects)
        return id
    }

    /// Saves a project's form. True when the edit asks its status line a new question: a new
    /// address, folder or command, whose old answer is not its answer.
    @discardableResult
    public func saveLocalProject(_ project: LocalProject) -> Bool {
        var projects = localProjectsStore.projects()
        let before = projects.first { $0.id == project.id }
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        localProjectsStore.save(projects)
        return before?.healthURL != project.healthURL || before?.folder != project.folder || before?.startCommand != project.startCommand
    }

    public func removeLocalProject(_ id: String) {
        localProjectsStore.save(localProjectsStore.projects().filter { $0.id != id })
    }

    /// What a folder says about the project in it.
    public func detect(folder: URL?) -> DeckDetection {
        guard let folder else {
            return DeckDetection(suggestion: nil, note: L("project.detect.noFolder"), isError: true)
        }
        guard let suggestion = ProjectProbe.suggestion(for: folder) else {
            return DeckDetection(suggestion: nil, note: L("project.detect.nothing"), isError: true)
        }
        let found = [suggestion.subtitle, suggestion.requiresDocker ? L("project.detect.needsDocker") : ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return DeckDetection(
            suggestion: suggestion,
            note: L("project.detect.found", found.isEmpty ? suggestion.startCommand : found),
            isError: false
        )
    }

    /// The project's status, asked the way the deck asks it, for the form's status line.
    public func checkLocalProject(_ project: LocalProject) async -> LocalProjectStatus {
        await localService(for: project).status()
    }

    /// The first link worth opening, in the project's own browser.
    public func testLink(_ project: LocalProject) -> DeckLinkTest {
        guard let link = project.environmentLinks().first ?? project.toolLinks().first else {
            return .note(L("project.link.nothingToOpen"))
        }
        return .open(link.url, project.browser)
    }

    // MARK: Arc projects

    public func addArcProject() -> String {
        var projects = projectsStore.projects()
        let id = ArcProject.makeID(from: "project", existing: projects.map(\.id))
        projects.append(ArcProject(id: id, title: L("project.new.title"), organization: ""))
        projectsStore.save(projects)
        return id
    }

    /// Saves an Arc project's form. True when the stack check has a new question to answer.
    @discardableResult
    public func saveArcProject(_ project: ArcProject) -> Bool {
        var projects = projectsStore.projects()
        let before = projects.first { $0.id == project.id }
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        projectsStore.save(projects)
        guard let before else { return false }
        return Self.stackAddress(of: before) != Self.stackAddress(of: project) && project.supportsLocalStack
    }

    /// Replaces a project whose links were added or removed, which only an existing one can have.
    public func restructureArcProject(_ project: ArcProject) {
        var projects = projectsStore.projects()
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        projectsStore.save(projects)
    }

    public func removeArcProject(_ id: String) {
        projectsStore.save(projectsStore.projects().filter { $0.id != id })
    }

    /// What the stack check asks about: the folder and the address it resolves to.
    public static func stackAddress(of project: ArcProject) -> String {
        "\(project.folder ?? "")|\(project.effectiveLocalURL)|\(project.healthPath)"
    }

    /// The stack's status, asked the way the deck asks it. Nil for a project with no local stack.
    public func checkArcStack(_ project: ArcProject) async -> LocalStackStatus? {
        guard project.supportsLocalStack else { return nil }
        return await LocalStackService(project: project, runner: commandRunner, neighbours: arcCheckouts).status()
    }

    /// What the stack line says before a project has a folder to check.
    public static var stackNotConfigured: CheckSummary {
        CheckSummary(tone: .idle, state: L("project.notConfigured"), detail: L("project.notConfigured.detail"))
    }

    public func testLink(_ project: ArcProject) -> DeckLinkTest {
        guard let link = project.resolvedLinks.first else {
            return .note(L("project.link.noneEnabled"))
        }
        return .open(link.url, project.browser)
    }

    // MARK: DDEV projects

    /// What can be added, from `ddev list`.
    public func ddevCandidates() async -> DeckDDEVCandidates {
        guard let entries = await ddevEnvironment.list() else { return .unavailable }
        guard !entries.isEmpty else { return .none }
        let known = Set(ddevProjectsStore.projects().map(\.name))
        let fresh = entries.filter { !known.contains($0.name) }
        return fresh.isEmpty ? .allAdded : .some(fresh)
    }

    public func addDDEVProject(_ entry: DDEVListEntry) -> String {
        var projects = ddevProjectsStore.projects()
        let id = DDEVProject.makeID(from: entry.name, existing: projects.map(\.id))
        projects.append(DDEVProject(id: id, name: entry.name, folder: entry.approot))
        ddevProjectsStore.save(projects)
        return id
    }

    public func saveDDEVProject(_ project: DDEVProject) {
        var projects = ddevProjectsStore.projects()
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        ddevProjectsStore.save(projects)
    }

    public func removeDDEVProject(_ id: String) {
        ddevProjectsStore.save(ddevProjectsStore.projects().filter { $0.id != id })
    }

    /// The note a chosen folder earns: none for a DDEV project, a warning for anything else. It
    /// warns rather than refuses, because `ddev config` may simply not have run yet.
    public func ddevFolderNote(_ folder: URL) -> String? {
        DDEVConfig.isProject(folder) ? nil : L("ddev.noConfig")
    }

    /// The project's first link, which only `ddev list` knows.
    public func testLink(_ project: DDEVProject) async -> DeckLinkTest {
        let entries = await ddevEnvironment.list()
        let status = ddevEnvironment.status(for: project, entries: entries)
        guard let link = project.links(status: status).first else { return .note(L("ddev.noURL")) }
        return .open(link.url, project.browser)
    }

    // MARK: Accounts

    public func addGitHubAccount() -> String {
        var accounts = accountsStore.accounts()
        let id = GitHubAccount.makeID(from: "account", existing: accounts.map(\.id))
        accounts.append(GitHubAccount(id: id, label: L("account.new.label")))
        accountsStore.save(accounts)
        return id
    }

    /// Adds a GitLab instance and turns the GitLab card on: the card is off by default, and
    /// adding an instance is the moment it becomes worth having.
    public func addGitLabAccount() -> String {
        var accounts = gitlabAccountsStore.accounts()
        let id = GitLabAccount.makeID(from: "gitlab", existing: accounts.map(\.id))
        accounts.append(GitLabAccount(id: id, label: "GitLab"))
        gitlabAccountsStore.save(accounts)
        cards.setEnabled(true, for: .gitlabMergeRequests)
        return id
    }

    public func saveGitHubAccount(_ account: GitHubAccount) {
        var accounts = accountsStore.accounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accountsStore.save(accounts)
    }

    public func saveGitLabAccount(_ account: GitLabAccount) {
        var accounts = gitlabAccountsStore.accounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        gitlabAccountsStore.save(accounts)
    }

    /// Removes an account and its token with it.
    public func removeGitHubAccount(_ id: String) {
        if let account = accountsStore.accounts().first(where: { $0.id == id }) {
            try? tokenStore.setToken(nil, for: account.tokenKey)
        }
        accountsStore.save(accountsStore.accounts().filter { $0.id != id })
    }

    public func removeGitLabAccount(_ id: String) {
        if let account = gitlabAccountsStore.accounts().first(where: { $0.id == id }) {
            try? tokenStore.setToken(nil, for: account.tokenKey)
        }
        gitlabAccountsStore.save(gitlabAccountsStore.accounts().filter { $0.id != id })
    }

    /// The account's own pull requests on the web, in its own browser.
    public func testLink(_ account: GitHubAccount) -> DeckLinkTest {
        .open(URL(string: "https://github.com/pulls")!, account.browser)
    }

    /// The instance's merge requests dashboard, in the account's own browser.
    public func testLink(_ account: GitLabAccount) -> DeckLinkTest {
        .open(account.host.appendingPathComponent("dashboard").appendingPathComponent("merge_requests"), account.browser)
    }

    /// Checks a GitHub token, the one typed or the one stored, and stores a typed one only once
    /// it works: a rejected token in the store turns into a card that fails for reasons nobody
    /// can see.
    public func checkGitHubToken(for account: GitHubAccount, typed: String) async -> DeckTokenCheck {
        let probe: any TokenStore = typed.isEmpty ? tokenStore : InMemoryTokenStore(tokens: [account.tokenKey: typed])
        let settings = account.settings(basedOn: .default)
        let client = http.map {
            GitHubClient(transport: APITransport(client: $0), tokenStore: probe, settings: settings, tokenKey: account.tokenKey)
        } ?? GitHubClient.makeDefault(tokenStore: probe, settings: settings, tokenKey: account.tokenKey)
        do {
            let snapshot = try await PullRequestsService(client: client, settings: settings, accountID: account.id).fetch()
            if !typed.isEmpty { try tokenStore.setToken(typed, for: account.tokenKey) }
            return .works(LN("token.works.pulls", snapshot.totalCount))
        } catch let error as APIError {
            return .refused(typed.isEmpty && !hasToken(account.tokenKey) ? L("token.needed") : error.displayMessage)
        } catch {
            return .refused(error.localizedDescription)
        }
    }

    /// The same for a GitLab instance.
    public func checkGitLabToken(for account: GitLabAccount, typed: String) async -> DeckTokenCheck {
        let probe: any TokenStore = typed.isEmpty ? tokenStore : InMemoryTokenStore(tokens: [account.tokenKey: typed])
        let client = http.map {
            GitLabClient(transport: APITransport(client: $0), tokenStore: probe, account: account)
        } ?? GitLabClient.makeDefault(account: account, tokenStore: probe)
        do {
            let snapshot = try await MergeRequestsService(client: client, accountID: account.id).fetch()
            if !typed.isEmpty { try tokenStore.setToken(typed, for: account.tokenKey) }
            return .works(LN("token.works.merges", snapshot.totalCount))
        } catch let error as APIError {
            // Said the way GitHub's says it: no token anywhere is a different problem from one
            // that was refused.
            return .refused(typed.isEmpty && !hasToken(account.tokenKey) ? L("token.needed") : error.displayMessage)
        } catch {
            return .refused(error.localizedDescription)
        }
    }
}
