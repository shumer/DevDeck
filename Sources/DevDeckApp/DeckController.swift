import ArcKit
import Combine
import DDEVKit
import DevDeckCore
import Foundation
import GitHubKit
import ProjectKit

/// Owns the data every panel renders and the loop that keeps it fresh.
///
/// One controller for the whole deck rather than one per card: the refresh cadence, the
/// token and the backoff after a failure are deck-wide concerns, and a card that is switched
/// off must not keep polling.
@MainActor
final class DeckController: ObservableObject {
    @Published private(set) var pullRequests = CardState<PullRequestsSnapshot>()
    @Published private(set) var inbox = CardState<InboxSnapshot>()
    @Published private(set) var actions = CardState<ActionsSnapshot>()

    /// Cards currently showing every row they have. Not persisted: expanding is a "let me look
    /// at this now" gesture, and a deck that comes back tall the next morning is a surprise.
    @Published private(set) var expandedCards: Set<CardID> = []
    /// The last lines each open tray is showing. Only open trays have an entry: a closed tray
    /// runs no commands, which is the difference between a card that reads a log and a card
    /// that tails one.
    @Published private(set) var logTails: [CardID: LogLines] = [:]

    /// Local stack state per Arc project id.
    @Published private(set) var stackStatuses: [String: LocalStackStatus] = [:]

    /// DDEV state per project id.
    @Published private(set) var ddevStatuses: [String: DDEVStatus] = [:]

    /// Plain project state per project id.
    @Published private(set) var localStatuses: [String: LocalProjectStatus] = [:]

    /// The container runtime every local project sits on. One answer for the whole deck.
    @Published private(set) var docker = DockerStatus(state: .unknown)

    private let preferences: Preferences
    private let tokenStore: any TokenStore
    private let accountsStore: GitHubAccountsStore
    private let projectsStore: ArcProjectsStore
    private let ddevProjectsStore: DDEVProjectsStore
    private let localProjectsStore: LocalProjectsStore
    private let ddevEnvironment: DDEVEnvironment
    private let dockerEnvironment: DockerEnvironment
    private let commandRunner: any CommandRunning
    private var settings: GitHubSettings
    private var loop: Task<Void, Never>?
    /// A separate, faster loop: a stack that has just come up should show up in seconds, not
    /// on the API refresh cadence.
    private var stackLoop: Task<Void, Never>?
    private var consecutiveFailures = 0

    /// Cards currently on screen. Nothing is fetched for a hidden card.
    private var activeCards: Set<CardID> = []

    init(
        preferences: Preferences,
        tokenStore: any TokenStore,
        accountsStore: GitHubAccountsStore,
        projectsStore: ArcProjectsStore,
        ddevProjectsStore: DDEVProjectsStore,
        localProjectsStore: LocalProjectsStore,
        commandRunner: any CommandRunning = ShellCommandRunner(),
        settings: GitHubSettings = .default
    ) {
        self.preferences = preferences
        self.tokenStore = tokenStore
        self.accountsStore = accountsStore
        self.projectsStore = projectsStore
        self.ddevProjectsStore = ddevProjectsStore
        self.localProjectsStore = localProjectsStore
        self.ddevEnvironment = DDEVEnvironment(runner: commandRunner)
        self.dockerEnvironment = DockerEnvironment(runner: commandRunner)
        self.commandRunner = commandRunner
        self.settings = settings
    }

    var refreshPolicy: RefreshPolicy {
        RefreshPolicy(interval: preferences.refreshIntervalSeconds)
    }

    func setActiveCards(_ cards: Set<CardID>) {
        activeCards = cards
        restart()
        restartStackLoop()
    }

    func start() {
        restart()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        stackLoop?.cancel()
        stackLoop = nil
    }

    // MARK: Arc projects

    /// Projects with a card on screen.
    private var activeProjects: [ArcProject] {
        projectsStore.enabledProjects().filter { activeCards.contains($0.cardID) }
    }

    func project(forCard card: CardID) -> ArcProject? {
        projectsStore.project(forCard: card)
    }

    func stackStatus(for project: ArcProject) -> LocalStackStatus {
        stackStatuses[project.id] ?? (project.supportsLocalStack
            ? LocalStackStatus(state: .stopped)
            : .unavailable)
    }

    private func restartStackLoop() {
        stackLoop?.cancel()
        guard !activeProjects.isEmpty || !activeDDEVProjects.isEmpty || !activeLocalProjects.isEmpty else {
            stackLoop = nil
            return
        }
        stackLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Docker first: every card below it reports something different when the
                // runtime is down, and one probe answers for all of them.
                await self.refreshDocker()
                await self.refreshStacks()
                await self.refreshDDEV()
                await self.refreshLocalProjects()
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func refreshStacks() async {
        for project in activeProjects {
            // A command issued from the card owns the status until it finishes; probing over
            // the top of it would flip the card back to "stopped" mid-restart.
            if stackStatuses[project.id]?.isBusy == true { continue }
            let service = LocalStackService(project: project, runner: commandRunner)
            stackStatuses[project.id] = await service.status()
        }
    }

    /// Runs a stack command and keeps the card honest while it does.
    func perform(_ action: LocalStackAction, for project: ArcProject) {
        guard project.supportsLocalStack else { return }
        stackStatuses[project.id] = LocalStackStatus(
            state: .working,
            detail: action.progressText,
            checkedAt: Date()
        )

        Task { [weak self] in
            guard let self else { return }
            let service = LocalStackService(project: project, runner: self.commandRunner)
            // Every line the command prints lands on the card as it arrives. A Fusion start
            // takes a minute and says plenty on the way; showing none of it is what made the
            // card look asleep while it was working.
            let result = await service.perform(action) { [weak self] line in
                Task { @MainActor in self?.noteProgress(line, for: project) }
            }

            if let result, !result.succeeded {
                // Show why rather than silently flipping back to "stopped": a failed start is
                // the moment the card is most worth reading.
                self.stackStatuses[project.id] = LocalStackStatus(
                    state: .stopped,
                    detail: result.failureLine ?? "\(action.title.lowercased()) failed",
                    checkedAt: Date()
                )
                return
            }

            switch action {
            case .start, .restart:
                // The command returns as soon as the containers are up; the engine takes
                // longer to serve. Keep the card honest about waiting instead of declaring
                // failure a second after a successful start.
                self.stackStatuses[project.id] = LocalStackStatus(
                    state: .working,
                    detail: "waiting for the engine…",
                    checkedAt: Date(),
                    progressLine: self.stackStatuses[project.id]?.progressLine
                )
                // `fusion daemon` reports "ports are not available … address already in use" and
                // then exits zero, so the failure is in what it said rather than in how it
                // ended. Carried here, that line is what the card shows instead of a shrug.
                self.stackStatuses[project.id] = await service.waitUntilRunning(
                    hint: result?.failureLine
                )
            case .stop, .teardown:
                // Verified rather than assumed. `fusion stop` returns before the containers are
                // down, and a stop that silently did nothing used to be repainted green by the
                // next poll as though the button had never been pressed.
                self.stackStatuses[project.id] = await service.waitUntilStopped()
            case .rebuild:
                self.stackStatuses[project.id] = await service.status()
            }
            // A start that failed is exactly when the lines matter, and the next scheduled pass
            // is two minutes away.
            await self.refreshLogsIfOpen(project.cardID)
        }
    }

    /// Puts the newest line from a running command on the card.
    private func noteProgress(_ line: String, for project: ArcProject) {
        guard var status = stackStatuses[project.id], status.isBusy else { return }
        status.progressLine = line
        stackStatuses[project.id] = status
    }

    // MARK: DDEV projects

    private var activeDDEVProjects: [DDEVProject] {
        ddevProjectsStore.enabledProjects().filter { activeCards.contains($0.cardID) }
    }

    func ddevProject(forCard card: CardID) -> DDEVProject? {
        ddevProjectsStore.project(forCard: card)
    }

    func ddevStatus(for project: DDEVProject) -> DDEVStatus {
        ddevStatuses[project.id] ?? DDEVStatus(state: .unknown)
    }

    /// One `ddev list` answers for every card, so the cost does not grow with the deck.
    /// `finished` names projects whose command has just returned. They are refreshed even
    /// though their status still says "working" - it says that because this very call is what
    /// clears it, and skipping them left a card stuck on "starting…" over a project that had
    /// been up for minutes.
    private func refreshDDEV(finished: Set<String> = []) async {
        let projects = activeDDEVProjects
        guard !projects.isEmpty else { return }

        let entries = await ddevEnvironment.list()
        for project in projects {
            // A command from the card owns the status while it runs, or the poll would flip
            // the card back mid-restart. A stale "working" is overruled: a task that died
            // without reporting must not freeze the card for the rest of the session.
            if !finished.contains(project.id), isBusyAndFresh(project.id) { continue }
            ddevStatuses[project.id] = ddevEnvironment.status(for: project, entries: entries)
        }
    }

    /// Long enough for a first `ddev start` that pulls images, short enough that a lost task
    /// does not strand the card.
    private func isBusyAndFresh(_ projectID: String) -> Bool {
        guard let status = ddevStatuses[projectID], status.isBusy else { return false }
        guard let checkedAt = status.checkedAt else { return true }
        return Date().timeIntervalSince(checkedAt) < 900
    }

    func perform(_ action: DDEVAction, for project: DDEVProject) {
        guard project.folderURL != nil else { return }
        ddevStatuses[project.id] = DDEVStatus(
            state: .working,
            entry: ddevStatuses[project.id]?.entry,
            config: ddevStatuses[project.id]?.config ?? DDEVConfig(),
            branch: ddevStatuses[project.id]?.branch,
            detail: action.progressText,
            checkedAt: Date()
        )

        Task { [weak self] in
            guard let self else { return }
            let result = await self.ddevEnvironment.perform(action, for: project)

            if let result, !result.succeeded {
                // A failed start is the moment the card is most worth reading, so the reason
                // stays on it rather than being replaced by a bare "stopped".
                self.ddevStatuses[project.id] = DDEVStatus(
                    state: .stopped,
                    config: DDEVConfig.load(in: project.folderURL),
                    branch: GitCheckout.branch(in: project.folderURL),
                    detail: result.failureLine ?? "\(action.title.lowercased()) failed",
                    checkedAt: Date()
                )
                await self.refreshLogsIfOpen(project.cardID)
                return
            }

            await self.refreshDDEV(finished: [project.id])
            await self.refreshLogsIfOpen(project.cardID)
        }
    }

    /// Stops every DDEV project and the router at once.
    func powerOffDDEV() {
        for project in activeDDEVProjects {
            ddevStatuses[project.id] = DDEVStatus(
                state: .working,
                entry: ddevStatuses[project.id]?.entry,
                config: ddevStatuses[project.id]?.config ?? DDEVConfig(),
                branch: ddevStatuses[project.id]?.branch,
                detail: "powering off…",
                checkedAt: Date()
            )
        }

        Task { [weak self] in
            guard let self else { return }
            let powered = Set(self.activeDDEVProjects.map(\.id))
            _ = await self.ddevEnvironment.powerOff()
            // Every card was marked working a moment ago, so every card is the one this
            // refresh is clearing.
            await self.refreshDDEV(finished: powered)
        }
    }

    // MARK: Docker

    /// Whether there is a runtime to launch on this machine. Read once: an app does not appear
    /// in /Applications mid-session, and this is asked on every card draw.
    private(set) lazy var canStartDocker: Bool = DockerApp.installedURL() != nil

    /// Opens the runtime and says so on the cards until it answers.
    func startDockerRuntime() {
        guard canStartDocker else { return }
        docker = DockerStatus(state: .starting, checkedAt: Date())
        DockerApp.launch()
    }

    private func refreshDocker() async {
        let probed = await dockerEnvironment.status()
        // Docker Desktop takes the better part of a minute to come up, and flipping the cards
        // back to "not running" in between is how a button looks like it did nothing. The
        // window is bounded so a launch that silently failed cannot leave the deck waiting
        // forever.
        if docker.state == .starting, !probed.isReady,
           let startedAt = docker.checkedAt, Date().timeIntervalSince(startedAt) < 180 {
            return
        }
        docker = probed
    }

    // MARK: Plain projects

    private var activeLocalProjects: [LocalProject] {
        localProjectsStore.enabledProjects().filter { activeCards.contains($0.cardID) }
    }

    func localProject(forCard card: CardID) -> LocalProject? {
        localProjectsStore.project(forCard: card)
    }

    func localStatus(for project: LocalProject) -> LocalProjectStatus {
        localStatuses[project.id] ?? (project.supportsCommands
            ? LocalProjectStatus(state: .stopped)
            : .unavailable)
    }


    private func refreshLocalProjects(finished: Set<String> = []) async {
        for project in activeLocalProjects {
            // A command issued from the card owns the status until it finishes, or the poll
            // flips the card back to "stopped" mid-restart. A stale "working" is overruled: a
            // task that died without reporting must not freeze the card for the session.
            if !finished.contains(project.id), isLocalBusyAndFresh(project.id) { continue }
            let service = LocalProjectService(project: project, runner: commandRunner)
            localStatuses[project.id] = await service.status()
        }
    }

    private func isLocalBusyAndFresh(_ projectID: String) -> Bool {
        guard let status = localStatuses[projectID], status.isBusy else { return false }
        guard let checkedAt = status.checkedAt else { return true }
        return Date().timeIntervalSince(checkedAt) < 900
    }

    func perform(_ action: LocalProjectAction, for project: LocalProject) {
        guard project.supportsCommands else { return }
        let previous = localStatuses[project.id]
        localStatuses[project.id] = LocalProjectStatus(
            state: .working,
            detail: action.progressText,
            checkedAt: Date(),
            branch: previous?.branch,
            hasLog: previous?.hasLog ?? false
        )

        Task { [weak self] in
            guard let self else { return }
            let service = LocalProjectService(project: project, runner: self.commandRunner)
            let result = await service.perform(action)

            if let result, !result.succeeded {
                // A failed start is the moment the card is most worth reading, so the reason
                // stays on it rather than being replaced by a bare "stopped".
                self.localStatuses[project.id] = LocalProjectStatus(
                    state: .stopped,
                    detail: result.failureLine ?? "\(action.title.lowercased()) failed",
                    checkedAt: Date(),
                    branch: previous?.branch,
                    hasLog: true
                )
                return
            }

            switch action {
            case .start, .restart:
                // The command returns long before a dev server has compiled or a container has
                // opened its port. Keep the card honest about waiting instead of declaring
                // failure a second after a successful start.
                self.localStatuses[project.id] = LocalProjectStatus(
                    state: .working,
                    detail: "waiting for the site…",
                    checkedAt: Date(),
                    branch: previous?.branch,
                    hasLog: true
                )
                self.localStatuses[project.id] = await service.waitUntilRunning()
            case .stop:
                self.localStatuses[project.id] = await service.status()
            }
            await self.refreshLogsIfOpen(project.cardID)
        }
    }

    /// Cancels the pending wait and refetches immediately.
    func refreshNow() {
        restart()
    }

    // MARK: Presentation

    func isExpanded(_ card: CardID) -> Bool {
        expandedCards.contains(card)
    }

    /// What a card's tray shows, or nil when it is closed.
    ///
    /// An open tray with nothing in it yet says so rather than showing an empty box: the first
    /// read takes a moment, and `docker logs` on a stopped project takes longer.
    func logs(for card: CardID) -> LogLines? {
        guard isExpanded(card), hasLogSource(card) else { return nil }
        return logTails[card] ?? LogLines(detail: "reading…")
    }

    /// Whether this card has anything to read at all.
    func hasLogSource(_ card: CardID) -> Bool {
        project(forCard: card) != nil || ddevProject(forCard: card) != nil || localProject(forCard: card) != nil
    }

    func toggleLogs(for card: CardID) {
        toggleExpanded(card)
        guard isExpanded(card) else {
            logTails[card] = nil
            return
        }
        Task { await refreshLogs(for: card) }
    }

    /// Reads the trays that are open, and only those.
    private func refreshOpenLogs() async {
        for card in expandedCards where hasLogSource(card) {
            await refreshLogs(for: card)
        }
    }

    /// Re-reads a tray straight after an action, when it is open.
    private func refreshLogsIfOpen(_ card: CardID) async {
        guard isExpanded(card) else { return }
        await refreshLogs(for: card)
    }

    private func refreshLogs(for card: CardID) async {
        if let project = project(forCard: card) {
            logTails[card] = await LocalStackService(project: project, runner: commandRunner).logs()
        } else if let project = ddevProject(forCard: card) {
            logTails[card] = await ddevEnvironment.logs(for: project)
        } else if let project = localProject(forCard: card) {
            logTails[card] = await LocalProjectService(project: project, runner: commandRunner).logs()
        }
    }

    func toggleExpanded(_ card: CardID) {
        if expandedCards.contains(card) {
            expandedCards.remove(card)
        } else {
            expandedCards.insert(card)
        }
    }

    /// Account id to label, for the per-row chips. Cards only draw chips when there is more
    /// than one account, so this doubles as the "is this a multi-account deck" answer.
    var accountLabels: [String: String] {
        Dictionary(
            accountsStore.enabledAccounts().map { ($0.id, $0.label) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Where this account's links open. An unknown id - a row left over from an account that
    /// was just removed - falls back to the system default.
    func browser(for accountID: String) -> BrowserChoice {
        accountsStore.accounts().first { $0.id == accountID }?.browser ?? .systemDefault
    }

    private func restart() {
        loop?.cancel()
        guard !activeCards.isEmpty else {
            loop = nil
            return
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.refreshOnce()
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }

    /// Rebuilt every pass so an account added in settings is picked up on the next refresh
    /// without restarting anything.
    private var workspace: GitHubWorkspace {
        GitHubWorkspace(
            accounts: accountsStore.enabledAccounts(),
            tokenStore: tokenStore,
            settings: settings
        )
    }

    /// Runs one pass over every active card and returns how long to wait before the next one.
    ///
    /// The cards refresh concurrently but share one failure counter: when the token is bad or
    /// the network is down, everything fails together and the deck should back off as a whole
    /// rather than three times over.
    private func refreshOnce() async -> TimeInterval {
        let workspace = self.workspace
        var errors: [APIError] = []
        var serverHint: TimeInterval?

        if activeCards.contains(.githubPullRequests) {
            pullRequests.beginRefresh()
            do {
                pullRequests.succeed(try await workspace.pullRequests(), at: Date())
            } catch {
                let apiError = Self.apiError(from: error)
                pullRequests.fail(apiError)
                errors.append(apiError)
            }
        }

        if activeCards.contains(.githubInbox) {
            inbox.beginRefresh()
            do {
                let snapshot = try await workspace.inbox()
                inbox.succeed(snapshot, at: Date())
                // GitHub states how often it wants to be polled on this endpoint; ignoring it
                // is the fastest way to get a token throttled.
                serverHint = snapshot.serverPollInterval
            } catch {
                let apiError = Self.apiError(from: error)
                inbox.fail(apiError)
                errors.append(apiError)
            }
        }

        if activeCards.contains(.githubActions) {
            actions.beginRefresh()
            do {
                let snapshot = try await workspace.actions(
                    repositoriesByAccount: actionsRepositoriesByAccount
                )
                actions.succeed(snapshot, at: Date())
            } catch {
                let apiError = Self.apiError(from: error)
                actions.fail(apiError)
                errors.append(apiError)
            }
        }

        // After the projects, because a tray reads what the state it just reported came from.
        await refreshOpenLogs()

        guard let firstError = errors.first else {
            consecutiveFailures = 0
            return refreshPolicy.nextDelay(consecutiveFailures: 0, serverHint: serverHint)
        }

        consecutiveFailures += 1
        Log.refresh.error("Refresh failed: \(firstError.displayMessage, privacy: .public)")
        return refreshPolicy.nextDelay(
            after: firstError,
            consecutiveFailures: consecutiveFailures,
            now: Date()
        )
    }

    /// Repositories the Actions card watches, per account.
    ///
    /// A repository belongs to exactly one account, so the list has to be grouped rather than
    /// broadcast: asking every account about every repository would spend most of the requests
    /// on 404s. With nothing configured it follows the open pull requests, five per account,
    /// which keeps the card useful with no configuration at all.
    private var actionsRepositoriesByAccount: [String: [String]] {
        let accounts = accountsStore.enabledAccounts()

        if !settings.actionsRepositories.isEmpty {
            var grouped: [String: [String]] = [:]
            for repository in settings.actionsRepositories {
                let owner = String(repository.split(separator: "/").first ?? "")
                let account = accounts.first { $0.organizations.contains(owner) } ?? accounts.first
                guard let account else { continue }
                grouped[account.id, default: []].append(repository)
            }
            return grouped
        }

        guard let snapshot = pullRequests.value else { return [:] }
        var grouped: [String: [String]] = [:]
        for pullRequest in snapshot.prioritized() {
            var repositories = grouped[pullRequest.accountID] ?? []
            guard repositories.count < 5, !repositories.contains(pullRequest.repository) else { continue }
            repositories.append(pullRequest.repository)
            grouped[pullRequest.accountID] = repositories
        }
        return grouped
    }

    private static func apiError(from error: Error) -> APIError {
        (error as? APIError) ?? .transport(error.localizedDescription)
    }

    // MARK: Menu bar summary

    /// What the menu-bar item conveys.
    ///
    /// The icon carries the identity and one bit of state - is anything wrong. The numbers
    /// live in the tooltip: a bare count in the menu bar says nothing about which app it
    /// belongs to, which is exactly the complaint it earned.
    var statusSummary: (tooltip: String, isAlert: Bool) {
        var lines: [String] = []
        var isAlert = false

        if activeCards.contains(.githubPullRequests) {
            if let snapshot = pullRequests.value {
                var line = "\(snapshot.totalCount) open pull request\(snapshot.totalCount == 1 ? "" : "s")"
                if snapshot.blockedCount > 0 {
                    line += ", \(snapshot.blockedCount) blocked"
                    isAlert = true
                }
                if snapshot.reviewRequestCount > 0 {
                    line += ", \(snapshot.reviewRequestCount) waiting for your review"
                    isAlert = true
                }
                lines.append(line)
            } else {
                lines.append("Pull requests: not loaded yet")
            }
        }

        if activeCards.contains(.githubInbox) {
            if let snapshot = inbox.value {
                var line = "\(snapshot.unreadCount) unread"
                if snapshot.actionableCount > 0 {
                    line += ", \(snapshot.actionableCount) waiting on you"
                    isAlert = true
                }
                lines.append(line)
            }
        }

        for project in activeProjects {
            let status = stackStatus(for: project)
            lines.append("\(project.title): local stack \(status.state.rawValue)")
        }

        for project in activeLocalProjects {
            lines.append("\(project.displayTitle): \(localStatus(for: project).state.rawValue)")
        }

        // Said once, at the bottom, rather than repeated on every project line. Not an alert:
        // Docker being off is a normal state of a laptop, not something gone wrong.
        if let reason = docker.blockingReason, !activeProjects.isEmpty || !activeDDEVProjects.isEmpty
            || !activeLocalProjects.isEmpty {
            lines.append(reason)
        }

        if lines.isEmpty { lines.append("No cards on screen") }
        return (("DevDeck\n" + lines.joined(separator: "\n")), isAlert)
    }
}
