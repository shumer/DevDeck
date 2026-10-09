import ArcKit
import DDEVKit
import DevDeckCore
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit

/// One stored field of the runtime, named when it is assigned. See `DeckRuntime.onChange`.
public enum DeckField: String, CaseIterable, Sendable {
    case pullRequests, inbox, actions, mergeRequests, checkouts, checkoutsCheckedAt
    case expandedCards, logTails, logWindowCards, inboxProgress, collapsedCards, parkedCards
    case stackStatuses, ddevStatuses, localStatuses, docker, watch, localAddress
}

/// Something only the platform can do, decided here and carried out by the shell.
public enum DeckEffect: Sendable, Equatable {
    /// Banners for what is new since the last pass.
    case announce([DeckAlert])
    /// A card's log window should open, or close.
    case openLogs(CardID)
    case closeLogs(CardID)
    /// Launch the container runtime's own app. The cards already say it is starting.
    case launchDocker
    /// What the menu-bar item counts changed without a field being assigned for it.
    case attentionChanged
    /// Open a page in this browser, and in this profile of it when there is one.
    case openURL(URL, BrowserChoice)
    /// Open Settings on one field.
    case openSetting(DeckSetting)
    /// Open a terminal in this folder.
    case openTerminal(URL)
    /// Show this folder.
    case revealFolder(URL)
    /// The cards on the deck changed: panels come and go.
    case cardsChanged
    /// The lock changed: panels can or cannot be moved.
    case lockChanged
    case tidy
    case openSettings
    case openCardSettings(CardID)
    case openAccountSettings(AttentionService, account: String?)
    case showCard(CardID)
    case installUpdate
    case openReleaseNotes
    case quit
    /// A saved arrangement changed the cards, their folds and their placements: open the panels
    /// and put them where the placements say.
    case arrangementApplied
    /// A newer build is out: one banner, in these words, whose click installs it.
    case offerUpdate(title: String, body: String, version: String)
}

/// A card's model, whichever card it is. See `DeckRuntime.model(for:)`.
public enum DeckCardModel: Sendable, Equatable {
    case reviewList(ReviewListCardModel)
    case inbox(InboxCardModel)
    case actions(ActionsCardModel)
    case workInFlight(WorkInFlightCardModel)
    case project(DeckProjectCardModel)
}

/// Owns the data every card renders and the loops that keep it fresh, on every platform.
///
/// One runtime for the whole deck rather than one per card: the refresh cadence, the
/// token and the backoff after a failure are deck-wide concerns, and a card that is switched
/// off must not keep polling.
///
/// It lives on the main actor, as the Mac controller it came from did, so a shell that folds a
/// card reads the folded state on the next line. See docs/adr/0025-the-deck-runtime-on-the-main-actor.md.
/// It decides and remembers; it never draws, opens a window or posts a banner. What only the
/// platform can do leaves through `onEffect`.
@MainActor
public final class DeckRuntime {
    /// Told about every assignment to a stored field, including one that leaves it equal. That
    /// is what `@Published` did, and what the Mac shell's subscriptions were written against:
    /// the menu redraws its time-dependent rows off a Docker probe that changed nothing.
    public var onChange: ((DeckField) -> Void)?

    /// Carries out what only the platform can do. See `DeckEffect`.
    public var onEffect: ((DeckEffect) -> Void)?

    private func changed(_ field: DeckField) {
        onChange?(field)
    }

    func effect(_ effect: DeckEffect) {
        onEffect?(effect)
    }

    /// Work a button started, which outlives the call that started it. Kept so `settle()` can
    /// wait for it; the loops are not in here, since they never end.
    private var work: [UUID: Task<Void, Never>] = [:]

    private func spawn(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        work[id] = Task { [weak self] in
            await operation()
            self?.work[id] = nil
        }
    }

    /// Waits until every action that is under way, and anything it started, has finished. For
    /// the suite and the protocol host, which both need to know when a button's work is done.
    public func settle() async {
        while let next = work.values.first {
            await next.value
        }
    }

    public private(set) var pullRequests = CardState<PullRequestsSnapshot>() {
        didSet { changed(.pullRequests) }
    }
    public private(set) var inbox = CardState<InboxSnapshot>() {
        didSet { changed(.inbox) }
    }
    public private(set) var actions = CardState<ActionsSnapshot>() {
        didSet { changed(.actions) }
    }
    public private(set) var mergeRequests = CardState<MergeRequestsSnapshot>() {
        didSet { changed(.mergeRequests) }
    }
    public private(set) var checkouts: [CheckoutState] = [] {
        didSet { changed(.checkouts) }
    }
    public private(set) var checkoutsCheckedAt: Date? {
        didSet { changed(.checkoutsCheckedAt) }
    }

    /// Cards currently showing every row they have. Not persisted: expanding is a "let me look
    /// at this now" gesture, and a deck that comes back tall the next morning is a surprise.
    public private(set) var expandedCards: Set<CardID> = [] {
        didSet { changed(.expandedCards) }
    }
    /// The last lines each open log window is showing. Only open windows have an entry: a
    /// window that is closed runs no commands, which is the difference between reading a log and
    /// tailing one.
    public private(set) var logTails: [CardID: LogLines] = [:] {
        didSet { changed(.logTails) }
    }
    /// The cards whose log window is open. Not persisted: a log open at midnight is not a
    /// request to have it open again in the morning.
    public private(set) var logWindowCards: Set<CardID> = [] {
        didSet { changed(.logWindowCards) }
    }
    /// A mark-as-read under way on the inbox, for its footer.
    public private(set) var inboxProgress: InboxProgress? {
        didSet { changed(.inboxProgress) }
    }
    /// Threads being marked read. The poll that lands in the middle of the job is filtered by
    /// them, or it would put back what the job has not reached yet.
    private var pendingRead: Set<String> = []

    /// Whether the Actions card picks its repositories from the open pull requests, because no
    /// list was given in Settings.
    public var actionsFollowPullRequests: Bool {
        preferences.actionsRepositories.isEmpty
    }
    /// Cards folded down to one row. Read from preferences whenever the deck's card list
    /// changes, so a collapsed card comes back collapsed.
    public private(set) var collapsedCards: Set<CardID> = [] {
        didSet { changed(.collapsedCards) }
    }
    /// Cards folded by the deck because the display they belong to is unplugged. Not a choice
    /// and not remembered: the card stands up again the moment its display returns.
    public private(set) var parkedCards: Set<CardID> = [] {
        didSet { changed(.parkedCards) }
    }

    /// Local stack state per Arc project id.
    public private(set) var stackStatuses: [String: LocalStackStatus] = [:] {
        didSet { changed(.stackStatuses) }
    }

    /// DDEV state per project id.
    public private(set) var ddevStatuses: [String: DDEVStatus] = [:] {
        didSet { changed(.ddevStatuses) }
    }

    /// Plain project state per project id.
    public private(set) var localStatuses: [String: LocalProjectStatus] = [:] {
        didSet { changed(.localStatuses) }
    }

    /// The container runtime every local project sits on. One answer for the whole deck.
    public private(set) var docker = DockerStatus(state: .unknown) {
        didSet { changed(.docker) }
    }

    /// What happened to the projects on this Mac between polls, for the menu and the banners.
    /// See `ProjectWatch`.
    public private(set) var watch = ProjectWatch() {
        didSet { changed(.watch) }
    }
    /// When Docker stopped answering, for the row that says so.
    private var dockerDownSince: Date?
    /// When each account started failing, keyed `service:id`. A network blip is not news, and a
    /// banner about a token is said once per episode.
    private var accountFailingSince: [String: Date] = [:]

    let preferences: Preferences
    let tokenStore: any TokenStore
    let accountsStore: GitHubAccountsStore
    let gitlabAccountsStore: GitLabAccountsStore
    let projectsStore: ArcProjectsStore
    let ddevProjectsStore: DDEVProjectsStore
    let localProjectsStore: LocalProjectsStore
    let ddevEnvironment: DDEVEnvironment
    private let dockerEnvironment: DockerEnvironment
    let commandRunner: any CommandRunning
    let http: (any HTTPClient)?
    let projectHTTP: (any HTTPClient)?
    let projectFiles: ProjectRuntimeFiles
    private let clock: any DateProvider
    private let sleeper: any Sleeper
    private let currentAddress: @MainActor () -> String?
    private var baseSettings: GitHubSettings
    private var loop: Task<Void, Never>?
    /// A separate, faster loop: a stack that has just come up should show up in seconds, not
    /// on the API refresh cadence.
    private var stackLoop: Task<Void, Never>?
    /// Runs the remote cards and owns the backoff. See `RefreshCycle`.
    private let cycle = RefreshCycle()
    /// Keeps a card from flipping to bad news on one unlucky poll. See `StateSettler`.
    private var settler = StateSettler()

    /// Cards currently on screen. Nothing is fetched for a hidden card.
    private var activeCards: Set<CardID> = []

    /// Everything that differs by platform or by test comes in here.
    ///
    /// - `canStartDocker`: whether this machine has the container runtime's app to launch.
    /// - `http`: what the GitHub and GitLab clients talk to; nil is the real network, built the
    ///   way the cards always built it.
    /// - `localAddress`: this machine's address on the network a phone shares, asked once per pass.
    /// - `projectHTTP`: what a plain project's health check talks to; nil is the real network,
    ///   with the short timeout a local check uses.
    /// - `projectFiles`: where plain projects keep their logs and process ids.
    public init(
        preferences: Preferences,
        tokenStore: any TokenStore,
        accountsStore: GitHubAccountsStore,
        gitlabAccountsStore: GitLabAccountsStore,
        projectsStore: ArcProjectsStore,
        ddevProjectsStore: DDEVProjectsStore,
        localProjectsStore: LocalProjectsStore,
        commandRunner: any CommandRunning,
        canStartDocker: Bool,
        localAddress: @escaping @MainActor () -> String?,
        http: (any HTTPClient)? = nil,
        projectHTTP: (any HTTPClient)? = nil,
        projectFiles: ProjectRuntimeFiles = .standard(),
        clock: any DateProvider = SystemDateProvider(),
        sleeper: any Sleeper = TaskSleeper(),
        settings: GitHubSettings = .default
    ) {
        self.preferences = preferences
        self.tokenStore = tokenStore
        self.accountsStore = accountsStore
        self.gitlabAccountsStore = gitlabAccountsStore
        self.projectsStore = projectsStore
        self.ddevProjectsStore = ddevProjectsStore
        self.localProjectsStore = localProjectsStore
        // On the runtime's clock, like everything else it times: a status checked at one time
        // and drawn as checked at another is a card that disagrees with itself.
        self.ddevEnvironment = DDEVEnvironment(runner: commandRunner, clock: clock)
        self.dockerEnvironment = DockerEnvironment(runner: commandRunner, clock: clock)
        self.commandRunner = commandRunner
        self.canStartDocker = canStartDocker
        self.currentAddress = localAddress
        self.http = http
        self.projectHTTP = projectHTTP
        self.projectFiles = projectFiles
        self.clock = clock
        self.sleeper = sleeper
        self.baseSettings = settings
        self.localAddress = localAddress()
    }

    public var refreshPolicy: RefreshPolicy {
        RefreshPolicy(interval: preferences.refreshIntervalSeconds)
    }

    public func setActiveCards(_ cards: Set<CardID>) {
        activeCards = cards
        watch.keep(only: Set(watchedProjects.map(\.id)))
        collapsedCards = cards.filter { preferences.isCollapsed($0) }
        restart()
        restartStackLoop()
    }

    public func start() {
        restart()
    }

    public func stop() {
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

    public func project(forCard card: CardID) -> ArcProject? {
        projectsStore.project(forCard: card)
    }

    public func stackStatus(for project: ArcProject) -> LocalStackStatus {
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
                await self.refreshLocalOnce()
                do {
                    try await self.sleeper.sleep(seconds: 10)
                } catch {
                    return
                }
            }
        }
    }

    /// One pass of the local loop: Docker, then every kind of project, then what is worth a
    /// banner. Public for the suite, which runs passes by hand instead of waiting ten seconds.
    public func refreshLocalOnce() async {
        // Docker first: every card below it reports something different when the runtime is
        // down, and one probe answers for all of them.
        await refreshDocker()
        await refreshStacks()
        await refreshDDEV()
        await refreshLocalProjects()
        announceProjects()
    }

    private func refreshStacks() async {
        for project in activeProjects {
            // A command issued from the card owns the status until it finishes; probing over
            // the top of it would flip the card back to "stopped" mid-restart.
            if stackStatuses[project.id]?.isBusy == true { continue }
            let service = LocalStackService(project: project, runner: commandRunner, neighbours: arcCheckouts)
            let probed = await service.status()
            // One failed probe is a hiccup: the engine drops a request while it reloads and the
            // card would say "stopped" about a stack that is up.
            guard settler.shouldApply(
                isGood: probed.isRunning,
                wasGood: stackStatuses[project.id]?.isRunning ?? false,
                for: "arc.\(project.id)"
            ) else { continue }
            stackStatuses[project.id] = probed
            observe(project, probed)
        }
    }

    /// An engine that answers its health URL with an error is up and unwell, not stopped.
    private func observe(_ project: ArcProject, _ status: LocalStackStatus) {
        let unwell = status.healthStatusCode != nil ? (status.detail ?? "health check failing") : nil
        watch.observe(
            project.id,
            running: status.isRunning || unwell != nil,
            notAnswering: unwell,
            dockerDown: !docker.isReady && docker.state != .unknown,
            at: clock.now
        )
    }

    /// Runs a stack command and keeps the card honest while it does.
    public func perform(_ action: LocalStackAction, for project: ArcProject) {
        // Pressing a button is a decision, not a poll: whatever it leads to is shown at once.
        settler.reset("arc.\(project.id)")
        guard project.supportsLocalStack else { return }
        watch.noteAction(project.id, isStop: action == .stop || action == .teardown, at: clock.now)
        stackStatuses[project.id] = LocalStackStatus(
            state: .working,
            detail: action.progressText,
            checkedAt: clock.now
        )

        spawn { [weak self] in
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
                let line = result.failureLine ?? "\(action.title.lowercased()) failed"
                self.stackStatuses[project.id] = LocalStackStatus(
                    state: .stopped,
                    detail: line,
                    checkedAt: clock.now
                )
                if action != .stop, action != .teardown {
                    self.watch.noteStartFailed(project.id, line: line, at: clock.now)
                }
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
                    checkedAt: clock.now,
                    progressLine: self.stackStatuses[project.id]?.progressLine
                )
                // `fusion daemon` reports "ports are not available … address already in use" and
                // then exits zero, so the failure is in what it said rather than in how it
                // ended. Carried here, that line is what the card shows instead of a shrug.
                let started = await service.waitUntilRunning(hint: result?.failureLine)
                self.stackStatuses[project.id] = started
                if started.isRunning {
                    self.observe(project, started)
                } else {
                    self.watch.noteStartFailed(project.id, line: started.detail ?? "the engine never answered", at: clock.now)
                }
            case .stop, .teardown:
                // Verified rather than assumed. `fusion stop` returns before the containers are
                // down, and a stop that silently did nothing used to be repainted green by the
                // next poll as though the button had never been pressed.
                let stopped = await service.waitUntilStopped()
                self.stackStatuses[project.id] = stopped
                if stopped.isRunning {
                    self.watch.noteStopDidNotTakeEffect(project.id, at: clock.now)
                } else {
                    self.observe(project, stopped)
                }
            case .rebuild:
                let rebuilt = await service.status()
                self.stackStatuses[project.id] = rebuilt
                self.observe(project, rebuilt)
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

    public func ddevProject(forCard card: CardID) -> DDEVProject? {
        ddevProjectsStore.project(forCard: card)
    }

    public func ddevStatus(for project: DDEVProject) -> DDEVStatus {
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
            let probed = ddevEnvironment.status(for: project, entries: entries)
            // `ddev list` answers slowly while a project is starting and occasionally not at
            // all, and the card would say "not in ddev list" about a project that is running.
            // A command that has just finished is not a poll, so it goes straight through.
            guard finished.contains(project.id) || settler.shouldApply(
                isGood: probed.isRunning,
                wasGood: ddevStatuses[project.id]?.isRunning ?? false,
                for: "ddev.\(project.id)"
            ) else { continue }
            ddevStatuses[project.id] = probed
            watch.observe(
                project.id,
                running: probed.isRunning,
                syncBroken: probed.mutagenWarning,
                dockerDown: !docker.isReady && docker.state != .unknown,
                at: clock.now
            )
        }
    }

    /// Long enough for a first `ddev start` that pulls images, short enough that a lost task
    /// does not strand the card.
    private func isBusyAndFresh(_ projectID: String) -> Bool {
        guard let status = ddevStatuses[projectID], status.isBusy else { return false }
        guard let checkedAt = status.checkedAt else { return true }
        return clock.now.timeIntervalSince(checkedAt) < 900
    }

    public func perform(_ action: DDEVAction, for project: DDEVProject) {
        // Pressing a button is a decision, not a poll: whatever it leads to is shown at once.
        settler.reset("ddev.\(project.id)")
        guard project.folderURL != nil else { return }
        watch.noteAction(project.id, isStop: action == .stop, at: clock.now)
        ddevStatuses[project.id] = DDEVStatus(
            state: .working,
            entry: ddevStatuses[project.id]?.entry,
            config: ddevStatuses[project.id]?.config ?? DDEVConfig(),
            branch: ddevStatuses[project.id]?.branch,
            detail: action.progressText,
            checkedAt: clock.now
        )

        spawn { [weak self] in
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
                    checkedAt: clock.now
                )
                if action != .stop {
                    self.watch.noteStartFailed(project.id, line: result.failureLine ?? "ddev \(action.rawValue) failed", at: clock.now)
                }
                await self.refreshLogsIfOpen(project.cardID)
                return
            }

            await self.refreshDDEV(finished: [project.id])
            let isRunning = self.ddevStatuses[project.id]?.isRunning == true
            if action == .stop, isRunning {
                self.watch.noteStopDidNotTakeEffect(project.id, at: clock.now)
            } else if action != .stop, !isRunning {
                self.watch.noteStartFailed(project.id, line: "ddev \(action.rawValue) finished, but the project is not running", at: clock.now)
            }
            await self.refreshLogsIfOpen(project.cardID)
        }
    }

    /// Stops every DDEV project and the router at once.
    public func powerOffDDEV() {
        for project in activeDDEVProjects {
            watch.noteAction(project.id, isStop: true, at: clock.now)
            ddevStatuses[project.id] = DDEVStatus(
                state: .working,
                entry: ddevStatuses[project.id]?.entry,
                config: ddevStatuses[project.id]?.config ?? DDEVConfig(),
                branch: ddevStatuses[project.id]?.branch,
                detail: "powering off…",
                checkedAt: clock.now
            )
        }

        spawn { [weak self] in
            guard let self else { return }
            let powered = Set(self.activeDDEVProjects.map(\.id))
            _ = await self.ddevEnvironment.powerOff()
            // Every card was marked working a moment ago, so every card is the one this
            // refresh is clearing.
            await self.refreshDDEV(finished: powered)
        }
    }

    // MARK: Docker

    /// Whether there is a runtime to launch on this machine. Read once by the shell: an app does
    /// not appear mid-session, and this is asked on every card draw.
    public let canStartDocker: Bool

    /// Opens the runtime and says so on the cards until it answers.
    public func startDockerRuntime() {
        guard canStartDocker else { return }
        docker = DockerStatus(state: .starting, checkedAt: clock.now)
        effect(.launchDocker)
    }

    private func refreshDocker() async {
        let probed = await dockerEnvironment.status()
        // The daemon is busy often enough to miss one `docker version`, and every card that
        // needs containers says "Docker is not running" when it does.
        guard settler.shouldApply(isGood: probed.isReady, wasGood: docker.isReady, for: "docker") else {
            return
        }
        // Docker Desktop takes the better part of a minute to come up, and flipping the cards
        // back to "not running" in between is how a button looks like it did nothing. The
        // window is bounded so a launch that silently failed cannot leave the deck waiting
        // forever.
        if docker.state == .starting, !probed.isReady,
           let startedAt = docker.checkedAt, clock.now.timeIntervalSince(startedAt) < 180 {
            return
        }
        docker = probed
        if probed.state == .notRunning || probed.state == .notInstalled {
            dockerDownSince = dockerDownSince ?? clock.now
        } else if probed.isReady {
            dockerDownSince = nil
        }
    }

    // MARK: Plain projects

    private var activeLocalProjects: [LocalProject] {
        localProjectsStore.enabledProjects().filter { activeCards.contains($0.cardID) }
    }

    public func localProject(forCard card: CardID) -> LocalProject? {
        localProjectsStore.project(forCard: card)
    }

    /// What the card draws. Whether Stop can reach the project is decided on the way out, so a
    /// stop command added in Settings counts at once rather than a poll later.
    public func localStatus(for project: LocalProject) -> LocalProjectStatus {
        var status = localStatuses[project.id] ?? (project.supportsCommands
            ? LocalProjectStatus(state: .stopped)
            : .unavailable)
        status.stopBlock = Self.stopBlock(for: project, status: status)
        return status
    }

    /// Why Stop cannot reach a running project, nil when it can.
    ///
    /// The health URL answers for a server whoever started it, so "running" alone says nothing
    /// about whether DevDeck can stop it. It can when it holds a live process from its own start
    /// or has a stop command to run. Without either there is nothing to try: never a port, never
    /// a process found by name, because that could be anybody's server.
    public nonisolated static func stopBlock(for project: LocalProject, status: LocalProjectStatus) -> ProjectStopBlock? {
        guard status.isRunning, status.pid == nil,
              project.stopCommand.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return project.holdsProcess ? .startedElsewhere : .noStopCommand
    }

    func localService(for project: LocalProject) -> LocalProjectService {
        guard let projectHTTP else {
            return LocalProjectService(project: project, runner: commandRunner, clock: clock, sleeper: sleeper, files: projectFiles)
        }
        return LocalProjectService(
            project: project,
            runner: commandRunner,
            httpClient: projectHTTP,
            clock: clock,
            sleeper: sleeper,
            files: projectFiles
        )
    }


    private func refreshLocalProjects(finished: Set<String> = []) async {
        for project in activeLocalProjects {
            // A command issued from the card owns the status until it finishes, or the poll
            // flips the card back to "stopped" mid-restart. A stale "working" is overruled: a
            // task that died without reporting must not freeze the card for the session.
            if !finished.contains(project.id), isLocalBusyAndFresh(project.id) { continue }
            let probed = await localService(for: project).status()
            // A dev server rebuilding drops requests for a second or two, and the card would
            // call that stopped.
            guard finished.contains(project.id) || settler.shouldApply(
                isGood: probed.isRunning,
                wasGood: localStatuses[project.id]?.isRunning ?? false,
                for: "project.\(project.id)"
            ) else { continue }
            localStatuses[project.id] = probed
            observe(project, probed)
        }
    }

    /// A process that is alive while its health URL is silent is up, and not answering.
    private func observe(_ project: LocalProject, _ status: LocalProjectStatus) {
        let silent = status.state == .starting ? (status.detail ?? "running, but not answering") : nil
        watch.observe(
            project.id,
            running: status.isRunning || silent != nil,
            notAnswering: silent,
            dockerDown: project.requiresDocker && !docker.isReady && docker.state != .unknown,
            at: clock.now
        )
    }

    private func isLocalBusyAndFresh(_ projectID: String) -> Bool {
        guard let status = localStatuses[projectID], status.isBusy else { return false }
        guard let checkedAt = status.checkedAt else { return true }
        return clock.now.timeIntervalSince(checkedAt) < 900
    }

    public func perform(_ action: LocalProjectAction, for project: LocalProject) {
        // Pressing a button is a decision, not a poll: whatever it leads to is shown at once.
        settler.reset("project.\(project.id)")
        guard project.supportsCommands else { return }
        if action != .start, let block = localStatus(for: project).stopBlock {
            // Nothing DevDeck holds can stop it, so nothing is run. Running the stop anyway is
            // how the menu came to say a stop "did not work" that was never tried, and a restart
            // would go on to start a second copy onto a port that is taken.
            watch.noteCannotStop(project.id, block, at: clock.now)
            return
        }
        watch.noteAction(project.id, isStop: action == .stop, at: clock.now)
        let previous = localStatuses[project.id]
        localStatuses[project.id] = LocalProjectStatus(
            state: .working,
            detail: action.progressText,
            checkedAt: clock.now,
            branch: previous?.branch,
            hasLog: previous?.hasLog ?? false
        )

        spawn { [weak self] in
            guard let self else { return }
            let service = self.localService(for: project)
            let result = await service.perform(action)

            if let result, !result.succeeded {
                // A failed start is the moment the card is most worth reading, so the reason
                // stays on it rather than being replaced by a bare "stopped".
                let line = result.failureLine ?? "\(action.title.lowercased()) failed"
                self.localStatuses[project.id] = LocalProjectStatus(
                    state: .stopped,
                    detail: line,
                    checkedAt: clock.now,
                    branch: previous?.branch,
                    hasLog: true
                )
                if action != .stop {
                    self.watch.noteStartFailed(project.id, line: line, at: clock.now)
                }
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
                    checkedAt: clock.now,
                    branch: previous?.branch,
                    hasLog: true
                )
                let started = await service.waitUntilRunning()
                self.localStatuses[project.id] = started
                if started.isRunning {
                    self.observe(project, started)
                } else {
                    self.watch.noteStartFailed(project.id, line: started.detail ?? "the site never answered", at: clock.now)
                }
            case .stop:
                let stopped = await service.status()
                self.localStatuses[project.id] = stopped
                if stopped.isRunning {
                    self.watch.noteStopDidNotTakeEffect(project.id, at: clock.now)
                } else {
                    self.observe(project, stopped)
                }
            }
            await self.refreshLogsIfOpen(project.cardID)
        }
    }

    /// Marks one inbox row read and takes it off the card at once.
    ///
    /// Optimistic on purpose. The notifications endpoint answers conditional requests, so the
    /// next poll can legitimately come back 304 for a while, and a row that is dealt with would
    /// sit there looking undone. If the call fails, the next poll puts it back.
    public func markRead(_ item: InboxItem) {
        guard let account = accountsStore.accounts().first(where: { $0.id == item.accountID }),
              let snapshot = inbox.value
        else { return }

        inbox.succeed(snapshot.removing([item.id]), at: clock.now)
        effect(.attentionChanged)

        spawn { [weak self] in
            guard let self else { return }
            do {
                try await self.notifications(for: account).markRead(item.id)
            } catch {
                #if os(Windows)
                Log.refresh.debug("Could not mark read: \(error)")
                #else
                Log.refresh.error("Could not mark read: \(String(describing: error), privacy: .public)")
                #endif
            }
        }
    }

    /// Marks everything in the inbox that is not addressed to you as read, and leaves the
    /// mentions, the review requests and the assignments where they are.
    ///
    /// Thread by thread, because GitHub has no "all except" call, and for a box bigger than the
    /// card loaded, every page of it. While that runs the footer says how far it has got, a
    /// second press does nothing, and the regular poll is not allowed to put back what is
    /// being marked: that poll landing halfway through is what made the first version look as if
    /// it had done nothing.
    public func markRestRead() {
        guard inboxProgress?.isRunning != true, let snapshot = inbox.value else { return }
        let loaded = snapshot.unreadNotForYou
        pendingRead.formUnion(loaded.map(\.id))
        inbox.succeed(snapshot.removing(pendingRead), at: clock.now)
        effect(.attentionChanged)
        inboxProgress = .gathering

        let accounts = accountsStore.accounts().filter { account in
            snapshot.cappedAccounts.contains(account.id) || loaded.contains { $0.accountID == account.id }
        }
        spawn { [weak self] in
            guard let self else { return }
            var work: [(service: NotificationsService, ids: [String])] = []
            for account in accounts {
                let service = self.notifications(for: account)
                var ids = loaded.filter { $0.accountID == account.id }.map(\.id)
                if snapshot.cappedAccounts.contains(account.id),
                   let everything = try? await service.unreadThreads() {
                    ids = everything.filter { !$0.reason.isForYou }.map(\.id)
                }
                work.append((service, ids))
            }
            let all = work.flatMap(\.ids)
            self.pendingRead.formUnion(all)
            if let current = self.inbox.value { self.inbox.succeed(current.removing(self.pendingRead), at: clock.now) }

            let total = all.count
            var finished = 0
            var failures: [String: APIError] = [:]
            self.inboxProgress = .marking(done: 0, total: total)
            for (service, ids) in work {
                let before = finished
                // The job already holds the controller for as long as it runs, so the progress
                // callback captures that constant rather than a weak variable of its own.
                let owner = self
                let refused = await service.markRead(ids) { done in
                    await MainActor.run { owner.inboxProgress = .marking(done: before + done, total: total) }
                }
                finished += ids.count
                failures.merge(refused) { first, _ in first }
            }
            await self.finishMarking(.finished(total - failures.count), refused: Set(failures.keys), reason: failures.values.first)
        }
    }

    /// Marks the whole inbox read, one request per account, up to the newest notification the
    /// card has shown. Whatever arrived after the card was drawn stays unread.
    public func markAllRead() {
        guard inboxProgress?.isRunning != true, let snapshot = inbox.value else { return }
        let newest = snapshot.newestByAccount
        pendingRead.formUnion(snapshot.items.map(\.id))
        inbox.succeed(snapshot.removing(pendingRead), at: clock.now)
        effect(.attentionChanged)
        inboxProgress = .markingAll

        let accounts = accountsStore.accounts().filter { newest[$0.id] != nil }
        let count = snapshot.isCapped ? nil : snapshot.unreadCount
        spawn { [weak self] in
            guard let self else { return }
            var refusal: APIError?
            for account in accounts {
                guard let upTo = newest[account.id] else { continue }
                do {
                    try await self.notifications(for: account).markAllRead(upTo: upTo)
                } catch {
                    refusal = refusal ?? APIError.wrapping(error)
                }
            }
            // GitHub may take a moment over a big box: a 202 means "accepted, working on it",
            // and asking straight away would show the box as it was.
            try? await self.sleeper.sleep(seconds: 2)
            // A refusal refuses the whole box, so nothing it held is read.
            await self.finishMarking(
                .finished(count),
                refused: refusal == nil ? [] : Set(snapshot.items.map(\.id)),
                reason: refusal
            )
        }
    }

    /// The end of a mark-as-read: the server's own answer on the card, and a word in the footer
    /// that clears itself.
    private func finishMarking(_ success: InboxProgress, refused: Set<String>, reason: APIError?) async {
        // What GitHub refused is not read, and comes back.
        pendingRead.subtract(refused)
        if let fresh = try? await workspace.inbox() {
            // Still filtered once: GitHub can take a moment to reflect a read, and a thread
            // that was just marked should not flicker back for one poll.
            inbox.succeed(fresh.removing(pendingRead), at: clock.now)
        } else if let current = inbox.value {
            inbox.succeed(current.removing(pendingRead), at: clock.now)
        }
        pendingRead.removeAll()
        effect(.attentionChanged)

        let outcome = reason.map { InboxProgress.failed($0.displayMessage) } ?? success
        inboxProgress = outcome
        try? await sleeper.sleep(seconds: outcome.isFailure ? 12 : 5)
        if inboxProgress == outcome { inboxProgress = nil }
    }

    private func notifications(for account: GitHubAccount) -> NotificationsService {
        let client = http.map {
            GitHubClient(
                transport: APITransport(client: $0),
                tokenStore: tokenStore,
                settings: account.settings(basedOn: settings),
                tokenKey: account.tokenKey
            )
        } ?? GitHubClient.makeDefault(
            tokenStore: tokenStore,
            settings: account.settings(basedOn: settings),
            tokenKey: account.tokenKey
        )
        return NotificationsService(client: client, settings: settings, accountID: account.id)
    }

    /// The Arc checkouts on the deck, by folder: what a card is called, for a message about a
    /// port one of them is holding.
    var arcCheckouts: [String: String] {
        projectsStore.projects().reduce(into: [:]) { result, project in
            guard let folder = project.folderURL?.standardizedFileURL.path else { return }
            result[folder] = project.title
        }
    }

    /// Every configured checkout, whatever kind of project it belongs to.
    ///
    /// One `git status` per folder, and one folder per project, deduplicated: two cards on the
    /// same checkout is a real arrangement, and it should not cost two processes or produce two
    /// rows.
    private func refreshCheckouts() async {
        guard activeCards.contains(.workInFlight) else { return }

        var folders: [(id: String, title: String, url: URL)] = []
        for project in projectsStore.projects() {
            if let url = project.folderURL { folders.append((project.id, project.title, url)) }
        }
        for project in ddevProjectsStore.projects() {
            if let url = project.folderURL { folders.append((project.id, project.displayTitle, url)) }
        }
        for project in localProjectsStore.projects() {
            if let url = project.folderURL { folders.append((project.id, project.displayTitle, url)) }
        }

        var seen = Set<String>()
        var states: [CheckoutState] = []
        for folder in folders where seen.insert(folder.url.standardizedFileURL.path).inserted {
            guard let result = try? await commandRunner.run(WorkInFlight.command, in: folder.url, timeout: 20),
                  result.succeeded,
                  var state = WorkInFlight.parse(result.standardOutput, id: folder.id, title: folder.title)
            else { continue }
            // How old the work that exists only here is, asked only where there is some: one more
            // process for the checkouts that matter, none for the clean ones.
            if state.isUrgent,
               let local = try? await commandRunner.run(WorkInFlight.localCommitsCommand, in: folder.url, timeout: 20),
               local.succeeded {
                let parsed = WorkInFlight.parseLocalCommits(local.standardOutput)
                state.localCommits = parsed.count
                state.oldestLocalCommitAt = parsed.oldest
            }
            states.append(state)
        }

        checkouts = states
        checkoutsCheckedAt = clock.now
    }

    /// The folder a checkout row came from, whichever kind of project owns it. A row that opens
    /// nothing would be a row that lies about being clickable.
    public func folder(forCheckout state: CheckoutState) -> URL? {
        projectsStore.projects().first { $0.id == state.id }?.folderURL
            ?? ddevProjectsStore.projects().first { $0.id == state.id }?.folderURL
            ?? localProjectsStore.projects().first { $0.id == state.id }?.folderURL
    }

    /// This machine's address on the wifi, for the phone button.
    ///
    /// Read once per refresh rather than per redraw: it is a syscall, it changes when a network
    /// does, and a card redraws far more often than that.
    public private(set) var localAddress: String? {
        didSet { changed(.localAddress) }
    }

    /// The site a phone on the same network can ask for, or nil when there is nothing to offer.
    ///
    /// Nil unless the project is up, which is the rule the button hangs on: a QR code pointing
    /// at a port nothing is listening on is a worse answer than no button at all.
    public func phoneURL(for site: URL?, isRunning: Bool) -> URL? {
        guard isRunning, let site, let localAddress else { return nil }
        return LocalAddress.rewrite(site, to: localAddress)
    }

    // MARK: Being told

    /// Which kinds of banner have had their first look in this run. The first answer is not news:
    /// it is the state of the world as you left it, and announcing it means every restart tells
    /// you about eight things you already knew.
    private var hasAnnouncedOnce: Set<String> = []

    /// Works out what is new since the last pass, hands it over, and writes down everything it
    /// saw so the next pass and the next launch stay quiet about it.
    private func announce(_ candidates: [DeckAlert], channel: String) {
        guard preferences.notificationsEnabled else { return }

        let isFirstPass = hasAnnouncedOnce.insert(channel).inserted
        let seen = preferences.announcedAlerts
        let fresh = NotificationDigest.newAlerts(
            from: candidates,
            seen: Set(seen),
            isFirstPass: isFirstPass
        )
        // Everything seen is remembered, not only what was announced: a first pass says nothing
        // and must still record what it saw, or the second pass announces all of it. The same
        // goes for an account whose notifications are off, which is why the filtering happens
        // before this and the remembering happens after.
        // Only written when it changed: the local loop asks every ten seconds, and nearly always
        // about things it has already seen.
        let remembered = NotificationDigest.remembering(candidates.map(\.id), in: seen)
        if remembered != seen { preferences.announcedAlerts = remembered }
        guard !fresh.isEmpty else { return }
        effect(.announce(Self.banners(for: fresh)))
    }

    /// What is new, as the banners to post. Many at once become one line: three banners stacked
    /// up the corner of the screen is a wall, and a wall gets swept away without being read.
    public static func banners(for alerts: [DeckAlert]) -> [DeckAlert] {
        guard let summary = NotificationDigest.summary(for: alerts) else { return alerts }
        let sources = Set(alerts.map(\.source))
        return [DeckAlert(
            // A hash that is the same on every run and every platform: Swift's own is seeded per
            // process, and the identifier is what a notification is replaced by.
            id: "summary.\(Self.stableHash(alerts.map(\.id).joined(separator: "\n")))",
            kind: alerts[0].kind,
            // One mark only when they share it; a mixed summary keeps the app's own icon.
            source: sources.count == 1 ? alerts[0].source : .devdeck,
            title: summary.title,
            subtitle: "",
            body: summary.body,
            subject: "",
            target: .menu,
            isQuiet: alerts.allSatisfy(\.isQuiet)
        )]
    }

    /// FNV-1a over the text's bytes, in hex.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// The alerts from one GitHub snapshot, kept to what each account asked to be told about.
    ///
    /// Per account rather than per app, and per kind rather than one switch: which of your
    /// tokens is allowed to interrupt you, and about what, is not one question.
    private func alerts(from snapshot: PullRequestsSnapshot) -> [DeckAlert] {
        let accounts = Dictionary(accountsStore.accounts().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return GitHubAttention.alerts(pullRequests: snapshot, labels: githubLabels).filter { alert in
            guard case .url(_, let accountID) = alert.target, let account = accounts[accountID] else { return false }
            return alert.kind == .reviewRequest ? account.notifiesReviewRequests : account.notifiesBlocked
        }
    }

    private func alerts(from snapshot: ActionsSnapshot) -> [DeckAlert] {
        let accounts = Dictionary(accountsStore.accounts().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return GitHubAttention.alerts(actions: snapshot, labels: githubLabels).filter { alert in
            guard case .url(_, let accountID) = alert.target else { return false }
            return accounts[accountID]?.notifiesFailedRuns == true
        }
    }

    private func alerts(from snapshot: MergeRequestsSnapshot) -> [DeckAlert] {
        let accounts = Dictionary(gitlabAccountsStore.accounts().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return GitLabAttention.alerts(mergeRequests: snapshot, labels: gitlabLabels).filter { alert in
            guard case .url(_, let accountID) = alert.target, let account = accounts[accountID] else { return false }
            return alert.kind == .reviewRequest ? account.notifiesReviewRequests : account.notifiesBlocked
        }
    }

    /// Banners for the projects on this Mac, after each pass of the local loop, kept to the
    /// projects that may interrupt you.
    private func announceProjects() {
        let quietDown = preferences.projectsQuietWhenDown
        let quietStart = preferences.projectsQuietWhenStartFails
        let projects = watchedProjects
        let candidates = ProjectAttention.alerts(
            projects: projects,
            watch: watch,
            docker: docker,
            dockerDownSince: dockerDownSince,
            source: { project in
                switch project.mark {
                case .arc: return .arc
                case .ddev: return .ddev
                default: return .project
                }
            },
            now: clock.now
        ).filter { alert in
            guard case .card(let card) = alert.target else { return true }
            let quiet = alert.kind == .startFailed ? quietStart : quietDown
            return !quiet.contains(card.rawValue)
        }
        announce(candidates, channel: "projects")
    }

    /// Notes when each account started and stopped failing, and announces a token that stopped
    /// working. Called after every pass of the remote cards.
    private func trackAccounts() {
        let input = attentionInput(update: nil)
        let github = DeckAttention.githubFailures(input)
        let gitlab = activeCards.contains(.gitlabMergeRequests)
            ? DeckAttention.failures(of: mergeRequests, snapshot: mergeRequests.value?.failures)
            : []
        let now = clock.now
        var failing: [String: Date] = [:]
        for (service, failures) in [(AttentionService.github, github), (.gitlab, gitlab)] {
            for failure in failures {
                let key = "\(service.rawValue):\(failure.accountID ?? failure.account)"
                failing[key] = accountFailingSince[key] ?? now
            }
        }
        accountFailingSince = failing

        var candidates: [DeckAlert] = []
        for (service, failures) in [(AttentionService.github, github), (.gitlab, gitlab)] {
            for failure in failures {
                let key = "\(service.rawValue):\(failure.accountID ?? failure.account)"
                if let alert = AccountAttention.alert(for: failure, service: service, since: failing[key]) {
                    candidates.append(alert)
                }
            }
        }
        announce(candidates, channel: "accounts")
    }

    /// Cancels the pending wait and refetches immediately.
    public func refreshNow() {
        restart()
    }

    // MARK: Presentation

    public func isExpanded(_ card: CardID) -> Bool {
        expandedCards.contains(card)
    }

    /// What a card's log window shows, or nil when there is no window.
    ///
    /// A window with nothing in it yet says so rather than showing an empty page: the first read
    /// takes a moment, and `docker logs` on a stopped project takes longer.
    public func logs(for card: CardID) -> LogLines? {
        guard logWindowCards.contains(card), hasLogSource(card) else { return nil }
        return logTails[card] ?? LogLines(detail: L("card.log.reading"))
    }

    /// Whether this card's log is on screen, which is what its header button shows.
    public func isShowingLogs(_ card: CardID) -> Bool {
        logWindowCards.contains(card)
    }

    /// Whether this card has anything to read at all.
    public func hasLogSource(_ card: CardID) -> Bool {
        project(forCard: card) != nil || ddevProject(forCard: card) != nil || localProject(forCard: card) != nil
    }

    public func toggleLogs(for card: CardID) {
        effect(logWindowCards.contains(card) ? .closeLogs(card) : .openLogs(card))
    }

    /// Told by the window itself, so what the deck believes and what is on screen are the same
    /// thing even when a window is closed with its own red button or with ⌘W.
    public func logWindowOpened(_ card: CardID) {
        logWindowCards.insert(card)
    }

    public func logWindowClosed(_ card: CardID) {
        logWindowCards.remove(card)
        logTails[card] = nil
    }

    /// Read now, because a window asked. The window is what sets the cadence while it is open.
    public func refreshLogsNow(for card: CardID) {
        guard hasLogSource(card) else { return }
        spawn { [weak self] in await self?.refreshLogs(for: card) }
    }

    /// Reads the logs that are on screen, and only those.
    private func refreshOpenLogs() async {
        for card in logWindowCards where hasLogSource(card) {
            await refreshLogs(for: card)
        }
    }

    /// Re-reads a log straight after an action, when its window is open.
    private func refreshLogsIfOpen(_ card: CardID) async {
        guard logWindowCards.contains(card) else { return }
        await refreshLogs(for: card)
    }

    private func refreshLogs(for card: CardID) async {
        let limit = LogTail.windowLineLimit
        if let project = project(forCard: card) {
            logTails[card] = await LocalStackService(project: project, runner: commandRunner).logs(limit: limit)
        } else if let project = ddevProject(forCard: card) {
            logTails[card] = await ddevEnvironment.logs(for: project, limit: limit)
        } else if let project = localProject(forCard: card) {
            logTails[card] = await localService(for: project).logs(limit: limit)
        }
    }

    /// Cards whose size the user has just changed, waiting for the deck to make room for them.
    ///
    /// The difference this records is the one the deck kept getting wrong: a card growing because
    /// its data arrived is the deck settling, and nothing should move for it, while a card
    /// growing because somebody pressed something is a request to make room.
    private var userResized: Set<CardID> = []

    private func noteUserResize(_ card: CardID) {
        userResized.insert(card)
    }

    /// The pending set, cleared as it is handed over. Called once per layout pass.
    public func takeUserResizes() -> Set<CardID> {
        defer { userResized = [] }
        return userResized
    }

    /// Whether this card has ever had real data.
    ///
    /// A card that has not yet heard back computes the height of an empty card, which is up to
    /// 106 points shorter than the one on screen. Resizing to that and back is what used to walk
    /// the whole column up the screen and then down again, leaving it somewhere else.
    public func hasLoaded(_ card: CardID) -> Bool {
        if card == .githubPullRequests { return pullRequests.value != nil }
        if card == .githubInbox { return inbox.value != nil }
        if card == .githubActions { return actions.value != nil }
        if card == .gitlabMergeRequests { return mergeRequests.value != nil }
        if card == .workInFlight { return checkoutsCheckedAt != nil }
        if let project = project(forCard: card) { return stackStatuses[project.id] != nil }
        if let project = ddevProject(forCard: card) { return ddevStatuses[project.id] != nil }
        if let project = localProject(forCard: card) { return localStatuses[project.id] != nil }
        return true
    }

    /// Whether the card is one row right now, by choice or because it is parked.
    public func isCollapsed(_ card: CardID) -> Bool {
        collapsedCards.contains(card) || parkedCards.contains(card)
    }

    /// Whether the card is one row because somebody folded it: what an arrangement saves.
    public func isCollapsedByChoice(_ card: CardID) -> Bool {
        collapsedCards.contains(card)
    }

    public func isParked(_ card: CardID) -> Bool {
        parkedCards.contains(card)
    }

    public func setParked(_ cards: Set<CardID>) {
        guard cards != parkedCards else { return }
        parkedCards = cards
    }

    /// Folds a card down, or opens it back up. A collapsed card keeps no tray: six lines of log
    /// under a one-line card is not a card, it is a log window with a hat on.
    public func toggleCollapsed(_ card: CardID) {
        noteUserResize(card)
        let collapsed = !isCollapsed(card)
        if collapsed {
            collapsedCards.insert(card)
            expandedCards.remove(card)
            logTails[card] = nil
        } else {
            collapsedCards.remove(card)
        }
        preferences.setCollapsed(collapsed, for: card)
    }

    public func toggleExpanded(_ card: CardID) {
        noteUserResize(card)
        if expandedCards.contains(card) {
            expandedCards.remove(card)
        } else {
            expandedCards.insert(card)
        }
    }

    /// GitLab account id to label, for the per-row chips on the merge requests card. Same rule
    /// as the GitHub one: chips only appear when there is more than one instance to tell apart.
    public var gitlabAccountLabels: [String: String] {
        Dictionary(
            gitlabAccountsStore.enabledAccounts().map { ($0.id, $0.label) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Where a GitLab row opens. An unknown id falls back to the system default.
    public func gitlabBrowser(for accountID: String) -> BrowserChoice {
        gitlabAccountsStore.accounts().first { $0.id == accountID }?.browser ?? .systemDefault
    }

    /// Account id to label, for the per-row chips. Cards only draw chips when there is more
    /// than one account, so this doubles as the "is this a multi-account deck" answer.
    public var accountLabels: [String: String] {
        Dictionary(
            accountsStore.enabledAccounts().map { ($0.id, $0.label) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Where this account's links open. An unknown id - a row left over from an account that
    /// was just removed - falls back to the system default.
    public func browser(for accountID: String) -> BrowserChoice {
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
                    try await self.sleeper.sleep(seconds: delay)
                } catch {
                    return
                }
            }
        }
    }

    /// The services' knobs, with the parts a person can change laid over them. Read fresh every
    /// pass so a repository added in settings is watched on the next refresh.
    private var settings: GitHubSettings {
        var settings = baseSettings
        settings.actionsRepositories = preferences.actionsRepositories
        return settings
    }

    /// Rebuilt every pass, the same as the GitHub one, so an instance added in settings is
    /// picked up on the next refresh without restarting anything.
    private var gitlab: GitLabWorkspace {
        guard let http else {
            return GitLabWorkspace(accounts: gitlabAccountsStore.enabledAccounts(), tokenStore: tokenStore)
        }
        let tokenStore = tokenStore
        return GitLabWorkspace(accounts: gitlabAccountsStore.enabledAccounts()) { account in
            GitLabClient(transport: APITransport(client: http), tokenStore: tokenStore, account: account)
        }
    }

    /// Rebuilt every pass so an account added in settings is picked up on the next refresh
    /// without restarting anything.
    private var workspace: GitHubWorkspace {
        guard let http else {
            return GitHubWorkspace(
                accounts: accountsStore.enabledAccounts(),
                tokenStore: tokenStore,
                settings: settings
            )
        }
        let tokenStore = tokenStore
        return GitHubWorkspace(accounts: accountsStore.enabledAccounts(), settings: settings) { account, accountSettings in
            GitHubClient(
                transport: APITransport(client: http),
                tokenStore: tokenStore,
                settings: accountSettings,
                tokenKey: account.tokenKey
            )
        }
    }

    /// Runs one pass over every active card and returns how long to wait before the next one.
    ///
    /// The remote cards go through `RefreshCycle`, which owns the shared failure counter and
    /// the backoff; what is left here is the local work that follows them. Public for the suite.
    public func refreshOnce() async -> TimeInterval {
        let pass = await cycle.run(remoteSources, active: activeCards, policy: refreshPolicy, now: clock.now)

        trackAccounts()

        // After the projects, because a tray reads what the state it just reported came from.
        await refreshOpenLogs()
        await refreshCheckouts()

        // A laptop moves between networks more often than it moves between refreshes.
        let address = currentAddress()
        if address != localAddress { localAddress = address }

        if let failure = pass.failures.first {
            #if os(Windows)
            Log.refresh.debug("Refresh failed: \(failure.error.displayMessage)")
            #else
            Log.refresh.error("Refresh failed: \(failure.error.displayMessage, privacy: .public)")
            #endif
        }
        return pass.delay
    }

    /// The remote cards, in the order they are asked. Built per pass so a workspace rebuilt
    /// from settings is the one that is asked.
    private var remoteSources: [RefreshSource] {
        [
            RefreshSource(card: .githubPullRequests) { @MainActor [weak self] in
                guard let self else { return nil }
                let snapshot = try await self.fetch(into: \.pullRequests) { try await self.workspace.pullRequests() }
                self.announce(self.alerts(from: snapshot), channel: "github.pulls")
                return nil
            },
            RefreshSource(card: .githubInbox) { @MainActor [weak self] in
                guard let self else { return nil }
                let snapshot = try await self.fetch(into: \.inbox) { try await self.workspace.inbox().removing(self.pendingRead) }
                // GitHub states how often it wants to be polled on this endpoint; ignoring it
                // is the fastest way to get a token throttled.
                return snapshot.serverPollInterval
            },
            RefreshSource(card: .gitlabMergeRequests) { @MainActor [weak self] in
                guard let self else { return nil }
                let snapshot = try await self.fetch(into: \.mergeRequests) { try await self.gitlab.mergeRequests() }
                self.announce(self.alerts(from: snapshot), channel: "gitlab")
                return nil
            },
            RefreshSource(card: .githubActions) { @MainActor [weak self] in
                guard let self else { return nil }
                let snapshot = try await self.fetch(into: \.actions) {
                    try await self.workspace.actions(repositoriesByAccount: self.actionsRepositoriesByAccount)
                }
                self.announce(self.alerts(from: snapshot), channel: "github.actions")
                return nil
            },
        ]
    }

    /// One fetch into one card's state: marks it refreshing, stores what came back or the
    /// failure, and rethrows so the cycle counts it.
    private func fetch<Value>(
        into keyPath: ReferenceWritableKeyPath<DeckRuntime, CardState<Value>>,
        _ load: () async throws -> Value
    ) async throws -> Value {
        self[keyPath: keyPath].beginRefresh()
        do {
            let value = try await load()
            self[keyPath: keyPath].succeed(value, at: clock.now)
            return value
        } catch {
            self[keyPath: keyPath].fail(APIError.wrapping(error))
            throw error
        }
    }

    /// Repositories the Actions card watches, per account. With nothing configured it follows
    /// the open pull requests.
    private var actionsRepositoriesByAccount: [String: [String]] {
        ActionsWatchList.repositoriesByAccount(
            configured: settings.actionsRepositories,
            accounts: accountsStore.enabledAccounts(),
            pullRequests: pullRequests.value
        )
    }

    /// The card whose command is still running, by title, or nil when none is.
    ///
    /// An update replaces the bundle and quits, and doing that under a running `fusion start`
    /// is how a stack is left half up with nothing on screen to say so.
    public var workingCardTitle: String? {
        for project in activeProjects where stackStatuses[project.id]?.isBusy == true { return project.title }
        for project in activeDDEVProjects where ddevStatuses[project.id]?.isBusy == true { return project.displayTitle }
        for project in activeLocalProjects where localStatuses[project.id]?.isBusy == true { return project.displayTitle }
        return nil
    }

    // MARK: Attention

    /// Labels by account id, only when there is more than one account to tell apart: with one,
    /// naming it on every row is noise.
    public var githubLabels: [String: String] {
        accountLabels.count > 1 ? accountLabels : [:]
    }

    public var gitlabLabels: [String: String] {
        gitlabAccountLabels.count > 1 ? gitlabAccountLabels : [:]
    }

    /// The projects on the deck, in the words the attention rows name them with.
    public var watchedProjects: [WatchedProject] {
        activeProjects.map {
            WatchedProject(id: $0.id, cardID: $0.cardID, title: $0.title, kind: "Arc XP", mark: .arc, needsDocker: $0.supportsLocalStack)
        }
        + activeDDEVProjects.map {
            WatchedProject(id: $0.id, cardID: $0.cardID, title: $0.displayTitle, kind: "DDEV", mark: .ddev, needsDocker: true)
        }
        + activeLocalProjects.map {
            WatchedProject(
                id: $0.id,
                cardID: $0.cardID,
                title: $0.displayTitle,
                // The caption the card wears, `bun · next + nest`, when there is one.
                kind: $0.subtitle.isEmpty ? L("project.section.project") : $0.subtitle,
                mark: .project($0.kind.rawValue),
                needsDocker: $0.requiresDocker
            )
        }
    }

    private func attentionInput(update: AttentionItem?) -> DeckAttention.Input {
        var folders: [String: URL] = [:]
        for checkout in checkouts {
            if let url = folder(forCheckout: checkout) { folders[checkout.id] = url }
        }
        return DeckAttention.Input(
            activeCards: activeCards,
            pullRequests: pullRequests,
            inbox: inbox,
            actions: actions,
            mergeRequests: mergeRequests,
            githubLabels: githubLabels,
            gitlabLabels: gitlabLabels,
            accountFailingSince: accountFailingSince,
            projects: watchedProjects,
            watch: watch,
            docker: docker,
            dockerDownSince: dockerDownSince,
            checkouts: checkouts,
            checkoutFolders: folders,
            update: update
        )
    }

    /// Everything the deck wants attention for, with the update row the updater supplies.
    public func attention(update: AttentionItem?) -> AttentionDigest {
        DeckAttention.digest(attentionInput(update: update), now: clock.now)
    }

    /// When the deck last heard from anything, for the calm menu's "Checked at".
    public var lastCheckedAt: Date? {
        [pullRequests.updatedAt, inbox.updatedAt, actions.updatedAt, mergeRequests.updatedAt, checkoutsCheckedAt, docker.checkedAt]
            .compactMap { $0 }
            .max()
    }

    /// Where "Open pull requests in browser" opens: the first account's browser.
    public var firstGitHubBrowser: BrowserChoice {
        accountsStore.enabledAccounts().first?.browser ?? .systemDefault
    }

    /// ⌥ on a row: forget what was reported about a project until something new happens to it.
    public func dismiss(_ item: AttentionItem) {
        dismissAttention(id: item.id)
    }

    /// ⌥ on a row, by the row's id.
    public func dismissAttention(id: String) {
        let parts = id.split(separator: ":")
        guard parts.count >= 2, parts[0] == "project" else { return }
        watch.dismiss(String(parts[1]))
        effect(.attentionChanged)
    }

    // MARK: The cards on the deck

    /// Every card the deck can show, and which of them are on.
    public var cards: DeckCardList {
        DeckCardList(
            preferences: preferences,
            arcProjects: projectsStore.projects(),
            ddevProjects: ddevProjectsStore.projects(),
            localProjects: localProjectsStore.projects()
        )
    }

    /// Whether the panels stay where they are, which both menus offer as a checkmark.
    public var isLocked: Bool {
        preferences.isLocked
    }

    /// The runtime's clock, for what it builds outside this file.
    var now: Date {
        clock.now
    }

    // MARK: Updates

    /// Whether a newer build is out, once a shell has said which version it runs. See
    /// `DeckUpdates`.
    public private(set) var updates: DeckUpdates?

    /// Starts watching for updates for the copy that is running: its version, nil where there is
    /// none, and whether this shell can put a new copy in place.
    public func watchForUpdates(currentVersion: String?, canInstall: Bool, http: any HTTPClient) -> DeckUpdates {
        let made = DeckUpdates(
            runtime: self,
            preferences: preferences,
            http: http,
            clock: clock,
            sleeper: sleeper,
            currentVersion: currentVersion,
            canInstall: canInstall
        )
        updates = made
        return made
    }

    // MARK: Placement

    /// Where the panels are, once a shell has panels. See `DeckPlacement`.
    public private(set) var placement: DeckPlacement?

    /// Gives the deck its panels: the shell says how to measure a card and which displays there
    /// are, and gets back the placement it will apply.
    public func placePanels(
        measure: @escaping (CardID) -> CGSize,
        displays: @escaping () -> DeckDisplays
    ) -> DeckPlacement {
        let made = DeckPlacement(runtime: self, preferences: preferences, measure: measure, displays: displays)
        placement = made
        return made
    }

    func savedPlacement(for card: CardID) -> PanelPlacement? {
        preferences.placement(for: card)
    }

    func savePlacement(_ placement: PanelPlacement, for card: CardID) {
        preferences.setPlacement(placement, for: card)
    }

    var savedArrangements: [DeckArrangement] {
        get { preferences.arrangements }
        set { preferences.arrangements = newValue }
    }

    // MARK: Card models and what their clicks ask for

    /// The card as it should be drawn now, or nil for a card that has no model yet.
    public func model(for card: CardID) -> DeckCardModel? {
        switch card {
        case .githubPullRequests:
            return .reviewList(.pullRequests(
                state: pullRequests,
                accountLabels: accountLabels,
                isExpanded: isExpanded(card),
                isCollapsed: isCollapsed(card),
                now: clock.now
            ))
        case .gitlabMergeRequests:
            return .reviewList(.mergeRequests(
                state: mergeRequests,
                accountLabels: gitlabAccountLabels,
                isExpanded: isExpanded(card),
                isCollapsed: isCollapsed(card),
                now: clock.now
            ))
        case .githubInbox:
            return .inbox(.build(
                state: inbox,
                accountLabels: accountLabels,
                isExpanded: isExpanded(card),
                isCollapsed: isCollapsed(card),
                progress: inboxProgress,
                now: clock.now
            ))
        case .githubActions:
            return .actions(.build(
                state: actions,
                followsPullRequests: actionsFollowPullRequests,
                isCollapsed: isCollapsed(card),
                now: clock.now
            ))
        case .workInFlight:
            return .workInFlight(.build(
                states: checkouts,
                checkedAt: checkoutsCheckedAt,
                isExpanded: isExpanded(card),
                isCollapsed: isCollapsed(card)
            ))
        default:
            return projectModel(for: card)
        }
    }

    /// An Arc, DDEV or plain project's card, whichever kind owns this card.
    private func projectModel(for card: CardID) -> DeckCardModel? {
        if let project = project(forCard: card) {
            let status = stackStatus(for: project)
            return .project(.arc(
                project, status: status, docker: docker, canStartDocker: canStartDocker,
                isShowingLogs: isShowingLogs(card), isCollapsed: isCollapsed(card),
                // Where the site is served is read from the checkout's `.env`, and the stack says
                // whether it is up.
                phoneURL: phoneURL(for: status.siteURL ?? project.localSiteURL, isRunning: status.isRunning)
            ))
        }
        if let project = ddevProject(forCard: card) {
            let status = ddevStatus(for: project)
            return .project(.ddev(
                project, status: status, docker: docker, canStartDocker: canStartDocker,
                isShowingLogs: isShowingLogs(card), isCollapsed: isCollapsed(card),
                // DDEV knows where it serves; `ddev list` says so.
                phoneURL: phoneURL(for: status.entry?.primaryURL, isRunning: status.isRunning)
            ))
        }
        if let project = localProject(forCard: card) {
            let status = localStatus(for: project)
            return .project(.local(
                project, status: status, docker: docker, canStartDocker: canStartDocker,
                isShowingLogs: isShowingLogs(card), isCollapsed: isCollapsed(card),
                // A plain project was told where it serves; nothing can find out for it.
                phoneURL: phoneURL(for: project.siteURL ?? project.healthCheckURL, isRunning: status.isRunning)
            ))
        }
        return nil
    }

    /// The folder and the browser of whichever project owns a card.
    private func projectPlace(for card: CardID) -> (folder: URL?, browser: BrowserChoice)? {
        if let project = project(forCard: card) { return (project.folderURL, project.browser) }
        if let project = ddevProject(forCard: card) { return (project.folderURL, project.browser) }
        if let project = localProject(forCard: card) { return (project.folderURL, project.browser) }
        return nil
    }

    /// Carries out a click from a card.
    public func perform(_ command: DeckCommand) {
        switch command {
        case .openLink(let url, let account, let service):
            effect(.openURL(url, service == .github ? browser(for: account) : gitlabBrowser(for: account)))
        case .openDashboard(let card):
            guard let url = dashboardURL(for: card) else { return }
            // The dashboard belongs to whichever account is first; there is no row to ask. A
            // GitLab card's first account is a GitLab one, in that account's browser.
            if card == .gitlabMergeRequests {
                effect(.openURL(url, gitlabBrowser(for: gitlabAccountLabels.keys.sorted().first ?? "")))
            } else {
                effect(.openURL(url, browser(for: accountLabels.keys.sorted().first ?? "")))
            }
        case .toggleExpanded(let card):
            toggleExpanded(card)
        case .markRead(let threadID):
            markRead(threadID: threadID)
        case .markRestRead:
            markRestRead()
        case .markAllRead:
            markAllRead()
        case .openSetting(let setting):
            effect(.openSetting(setting))
        case .openCheckout(let id):
            guard let state = checkouts.first(where: { $0.id == id }), let folder = folder(forCheckout: state) else { return }
            effect(.openTerminal(folder))
        case .openProjectLink(let card, let url):
            guard let place = projectPlace(for: card) else { return }
            effect(.openURL(url, place.browser))
        case .project(let card, let action):
            if let project = project(forCard: card) {
                perform(LocalStackAction(rawValue: action.rawValue) ?? .start, for: project)
            } else if let project = ddevProject(forCard: card) {
                perform(DDEVAction(rawValue: action.rawValue) ?? .start, for: project)
            } else if let project = localProject(forCard: card) {
                perform(LocalProjectAction(rawValue: action.rawValue) ?? .start, for: project)
            }
        case .revealFolder(let card):
            guard let folder = projectPlace(for: card)?.folder else { return }
            effect(.revealFolder(folder))
        case .openTerminal(let card):
            guard let folder = projectPlace(for: card)?.folder else { return }
            effect(.openTerminal(folder))
        case .startDocker:
            startDockerRuntime()
        case .toggleLogs(let card):
            toggleLogs(for: card)
        case .toggleCard(let card):
            let list = cards
            list.setEnabled(!list.isEnabled(card), for: card)
            effect(.cardsChanged)
        case .toggleCollapsed(let card):
            toggleCollapsed(card)
        case .toggleLock:
            preferences.isLocked.toggle()
            effect(.lockChanged)
        case .tidy:
            effect(.tidy)
        case .refreshNow:
            refreshNow()
        case .openSettings:
            effect(.openSettings)
        case .openCardSettings(let card):
            effect(.openCardSettings(card))
        case .openAccountSettings(let service, let account):
            effect(.openAccountSettings(service, account: account))
        case .showCard(let card):
            effect(.showCard(card))
        case .dismissAttention(let id):
            dismissAttention(id: id)
        case .installUpdate:
            effect(.installUpdate)
        case .openReleaseNotes:
            effect(.openReleaseNotes)
        case .quit:
            effect(.quit)
        case .powerOffDDEV:
            powerOffDDEV()
        case .openTerminalAt(let folder):
            effect(.openTerminal(folder))
        case .applyArrangement(let name):
            applyArrangement(named: name)
        case .forgetArrangement(let name):
            forgetArrangement(named: name)
        case .saveArrangement(let name):
            saveArrangement(named: name)
        case .openPullRequestsPage:
            // Through the first account's browser, like every other GitHub link on the deck.
            guard let url = dashboardURL(for: .githubPullRequests) else { return }
            effect(.openURL(url, firstGitHubBrowser))
        }
    }

    /// A card's own page on the web, for the cards that have one.
    public func dashboardURL(for card: CardID) -> URL? {
        switch card {
        case .githubPullRequests: return URL(string: "https://github.com/pulls")
        case .githubInbox: return URL(string: "https://github.com/notifications")
        // Actions has no cross-repository page; the closest thing is the dashboard.
        case .githubActions: return URL(string: "https://github.com")
        // The instance is per account, so this is only the nearest thing to a constant; the
        // card's own rows carry absolute URLs.
        case .gitlabMergeRequests: return URL(string: "https://gitlab.com/dashboard/merge_requests")
        default: return nil
        }
    }

    /// ⌥ on an inbox row.
    public func markRead(threadID: String) {
        guard let item = inbox.value?.items.first(where: { $0.id == threadID }) else { return }
        markRead(item)
    }
}
