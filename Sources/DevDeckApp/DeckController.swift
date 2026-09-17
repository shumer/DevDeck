import ArcKit
import Combine
import DDEVKit
import DevDeckCore
import DevDeckUI
import Foundation
import GitHubKit
import GitLabKit
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
    @Published private(set) var mergeRequests = CardState<MergeRequestsSnapshot>()
    @Published private(set) var checkouts: [CheckoutState] = []
    @Published private(set) var checkoutsCheckedAt: Date?

    /// Cards currently showing every row they have. Not persisted: expanding is a "let me look
    /// at this now" gesture, and a deck that comes back tall the next morning is a surprise.
    @Published private(set) var expandedCards: Set<CardID> = []
    /// The last lines each open tray is showing. Only open trays have an entry: a closed tray
    /// runs no commands, which is the difference between a card that reads a log and a card
    /// that tails one.
    @Published private(set) var logTails: [CardID: LogLines] = [:]
    /// Cards folded down to one row. Read from preferences whenever the deck's card list
    /// changes, so a collapsed card comes back collapsed.
    @Published private(set) var collapsedCards: Set<CardID> = []

    /// Local stack state per Arc project id.
    @Published private(set) var stackStatuses: [String: LocalStackStatus] = [:]

    /// DDEV state per project id.
    @Published private(set) var ddevStatuses: [String: DDEVStatus] = [:]

    /// Plain project state per project id.
    @Published private(set) var localStatuses: [String: LocalProjectStatus] = [:]

    /// The container runtime every local project sits on. One answer for the whole deck.
    @Published private(set) var docker = DockerStatus(state: .unknown)

    /// What happened to the projects on this Mac between polls, for the menu and the banners.
    /// See `ProjectWatch`.
    @Published private(set) var watch = ProjectWatch()
    /// When Docker stopped answering, for the row that says so.
    private var dockerDownSince: Date?
    /// When each account started failing, keyed `service:id`. A network blip is not news, and a
    /// banner about a token is said once per episode.
    private var accountFailingSince: [String: Date] = [:]

    private let preferences: Preferences
    private let tokenStore: any TokenStore
    private let accountsStore: GitHubAccountsStore
    private let gitlabAccountsStore: GitLabAccountsStore
    private let projectsStore: ArcProjectsStore
    private let ddevProjectsStore: DDEVProjectsStore
    private let localProjectsStore: LocalProjectsStore
    private let ddevEnvironment: DDEVEnvironment
    private let dockerEnvironment: DockerEnvironment
    private let commandRunner: any CommandRunning
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

    init(
        preferences: Preferences,
        tokenStore: any TokenStore,
        accountsStore: GitHubAccountsStore,
        gitlabAccountsStore: GitLabAccountsStore,
        projectsStore: ArcProjectsStore,
        ddevProjectsStore: DDEVProjectsStore,
        localProjectsStore: LocalProjectsStore,
        commandRunner: any CommandRunning = ShellCommandRunner(),
        settings: GitHubSettings = .default
    ) {
        self.preferences = preferences
        self.tokenStore = tokenStore
        self.accountsStore = accountsStore
        self.gitlabAccountsStore = gitlabAccountsStore
        self.projectsStore = projectsStore
        self.ddevProjectsStore = ddevProjectsStore
        self.localProjectsStore = localProjectsStore
        self.ddevEnvironment = DDEVEnvironment(runner: commandRunner)
        self.dockerEnvironment = DockerEnvironment(runner: commandRunner)
        self.commandRunner = commandRunner
        self.baseSettings = settings
    }

    var refreshPolicy: RefreshPolicy {
        RefreshPolicy(interval: preferences.refreshIntervalSeconds)
    }

    func setActiveCards(_ cards: Set<CardID>) {
        activeCards = cards
        watch.keep(only: Set(watchedProjects.map(\.id)))
        collapsedCards = cards.filter { preferences.isCollapsed($0) }
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
                self.announceProjects()
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
            at: Date()
        )
    }

    /// Runs a stack command and keeps the card honest while it does.
    func perform(_ action: LocalStackAction, for project: ArcProject) {
        // Pressing a button is a decision, not a poll: whatever it leads to is shown at once.
        settler.reset("arc.\(project.id)")
        guard project.supportsLocalStack else { return }
        watch.noteAction(project.id, isStop: action == .stop || action == .teardown, at: Date())
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
                let line = result.failureLine ?? "\(action.title.lowercased()) failed"
                self.stackStatuses[project.id] = LocalStackStatus(
                    state: .stopped,
                    detail: line,
                    checkedAt: Date()
                )
                if action != .stop, action != .teardown {
                    self.watch.noteStartFailed(project.id, line: line, at: Date())
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
                    checkedAt: Date(),
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
                    self.watch.noteStartFailed(project.id, line: started.detail ?? "the engine never answered", at: Date())
                }
            case .stop, .teardown:
                // Verified rather than assumed. `fusion stop` returns before the containers are
                // down, and a stop that silently did nothing used to be repainted green by the
                // next poll as though the button had never been pressed.
                let stopped = await service.waitUntilStopped()
                self.stackStatuses[project.id] = stopped
                if stopped.isRunning {
                    self.watch.noteStopDidNotTakeEffect(project.id, at: Date())
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
                at: Date()
            )
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
        // Pressing a button is a decision, not a poll: whatever it leads to is shown at once.
        settler.reset("ddev.\(project.id)")
        guard project.folderURL != nil else { return }
        watch.noteAction(project.id, isStop: action == .stop, at: Date())
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
                if action != .stop {
                    self.watch.noteStartFailed(project.id, line: result.failureLine ?? "ddev \(action.rawValue) failed", at: Date())
                }
                await self.refreshLogsIfOpen(project.cardID)
                return
            }

            await self.refreshDDEV(finished: [project.id])
            let isRunning = self.ddevStatuses[project.id]?.isRunning == true
            if action == .stop, isRunning {
                self.watch.noteStopDidNotTakeEffect(project.id, at: Date())
            } else if action != .stop, !isRunning {
                self.watch.noteStartFailed(project.id, line: "ddev \(action.rawValue) finished, but the project is not running", at: Date())
            }
            await self.refreshLogsIfOpen(project.cardID)
        }
    }

    /// Stops every DDEV project and the router at once.
    func powerOffDDEV() {
        for project in activeDDEVProjects {
            watch.noteAction(project.id, isStop: true, at: Date())
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
           let startedAt = docker.checkedAt, Date().timeIntervalSince(startedAt) < 180 {
            return
        }
        docker = probed
        if probed.state == .notRunning || probed.state == .notInstalled {
            dockerDownSince = dockerDownSince ?? Date()
        } else if probed.isReady {
            dockerDownSince = nil
        }
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
            let probed = await service.status()
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
            at: Date()
        )
    }

    private func isLocalBusyAndFresh(_ projectID: String) -> Bool {
        guard let status = localStatuses[projectID], status.isBusy else { return false }
        guard let checkedAt = status.checkedAt else { return true }
        return Date().timeIntervalSince(checkedAt) < 900
    }

    func perform(_ action: LocalProjectAction, for project: LocalProject) {
        // Pressing a button is a decision, not a poll: whatever it leads to is shown at once.
        settler.reset("project.\(project.id)")
        guard project.supportsCommands else { return }
        watch.noteAction(project.id, isStop: action == .stop, at: Date())
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
                let line = result.failureLine ?? "\(action.title.lowercased()) failed"
                self.localStatuses[project.id] = LocalProjectStatus(
                    state: .stopped,
                    detail: line,
                    checkedAt: Date(),
                    branch: previous?.branch,
                    hasLog: true
                )
                if action != .stop {
                    self.watch.noteStartFailed(project.id, line: line, at: Date())
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
                    checkedAt: Date(),
                    branch: previous?.branch,
                    hasLog: true
                )
                let started = await service.waitUntilRunning()
                self.localStatuses[project.id] = started
                if started.isRunning {
                    self.observe(project, started)
                } else {
                    self.watch.noteStartFailed(project.id, line: started.detail ?? "the site never answered", at: Date())
                }
            case .stop:
                let stopped = await service.status()
                self.localStatuses[project.id] = stopped
                if stopped.isRunning {
                    self.watch.noteStopDidNotTakeEffect(project.id, at: Date())
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
    func markRead(_ item: InboxItem) {
        guard let account = accountsStore.accounts().first(where: { $0.id == item.accountID }),
              let snapshot = inbox.value
        else { return }

        inbox.succeed(
            InboxSnapshot(
                items: snapshot.items.filter { $0.id != item.id },
                serverPollInterval: snapshot.serverPollInterval,
                failures: snapshot.failures
            ),
            at: Date()
        )
        updateStatusItem?()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await NotificationsService(
                    client: GitHubClient.makeDefault(
                        tokenStore: self.tokenStore,
                        settings: account.settings(basedOn: self.settings),
                        tokenKey: account.tokenKey
                    ),
                    settings: self.settings,
                    accountID: account.id
                ).markRead(item.id)
            } catch {
                Log.refresh.error("Could not mark read: \(String(describing: error), privacy: .public)")
            }
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
        checkoutsCheckedAt = Date()
    }

    /// The folder a checkout row came from, whichever kind of project owns it. A row that opens
    /// nothing would be a row that lies about being clickable.
    func folder(forCheckout state: CheckoutState) -> URL? {
        projectsStore.projects().first { $0.id == state.id }?.folderURL
            ?? ddevProjectsStore.projects().first { $0.id == state.id }?.folderURL
            ?? localProjectsStore.projects().first { $0.id == state.id }?.folderURL
    }

    /// This machine's address on the wifi, for the phone button.
    ///
    /// Read once per refresh rather than per redraw: it is a syscall, it changes when a network
    /// does, and a card redraws far more often than that.
    @Published private(set) var localAddress: String? = LocalAddress.current()

    /// The site a phone on the same network can ask for, or nil when there is nothing to offer.
    ///
    /// Nil unless the project is up, which is the rule the button hangs on: a QR code pointing
    /// at a port nothing is listening on is a worse answer than no button at all.
    func phoneURL(for site: URL?, isRunning: Bool) -> URL? {
        guard isRunning, let site, let localAddress else { return nil }
        return LocalAddress.rewrite(site, to: localAddress)
    }

    /// The menu bar carries the unread count, so it has to hear about a row leaving.
    var updateStatusItem: (() -> Void)?

    // MARK: Being told

    /// Set by the app delegate, because posting a banner is AppKit's business rather than the
    /// controller's. Nil means notifications are off and nothing is even assembled.
    var onAlerts: (([DeckAlert]) -> Void)?

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
        onAlerts?(fresh)
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
            now: Date()
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
        let now = Date()
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
        noteUserResize(card)
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
    func takeUserResizes() -> Set<CardID> {
        defer { userResized = [] }
        return userResized
    }

    /// Whether this card has ever had real data.
    ///
    /// A card that has not yet heard back computes the height of an empty card, which is up to
    /// 106 points shorter than the one on screen. Resizing to that and back is what used to walk
    /// the whole column up the screen and then down again, leaving it somewhere else.
    func hasLoaded(_ card: CardID) -> Bool {
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

    func isCollapsed(_ card: CardID) -> Bool {
        collapsedCards.contains(card)
    }

    /// Folds a card down, or opens it back up. A collapsed card keeps no tray: six lines of log
    /// under a one-line card is not a card, it is a log window with a hat on.
    func toggleCollapsed(_ card: CardID) {
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

    func toggleExpanded(_ card: CardID) {
        noteUserResize(card)
        if expandedCards.contains(card) {
            expandedCards.remove(card)
        } else {
            expandedCards.insert(card)
        }
    }

    /// GitLab account id to label, for the per-row chips on the merge requests card. Same rule
    /// as the GitHub one: chips only appear when there is more than one instance to tell apart.
    var gitlabAccountLabels: [String: String] {
        Dictionary(
            gitlabAccountsStore.enabledAccounts().map { ($0.id, $0.label) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Where a GitLab row opens. An unknown id falls back to the system default.
    func gitlabBrowser(for accountID: String) -> BrowserChoice {
        gitlabAccountsStore.accounts().first { $0.id == accountID }?.browser ?? .systemDefault
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
        GitLabWorkspace(accounts: gitlabAccountsStore.enabledAccounts(), tokenStore: tokenStore)
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
    /// The remote cards go through `RefreshCycle`, which owns the shared failure counter and
    /// the backoff; what is left here is the local work that follows them.
    private func refreshOnce() async -> TimeInterval {
        let pass = await cycle.run(remoteSources, active: activeCards, policy: refreshPolicy, now: Date())

        trackAccounts()

        // After the projects, because a tray reads what the state it just reported came from.
        await refreshOpenLogs()
        await refreshCheckouts()

        // A laptop moves between networks more often than it moves between refreshes.
        let address = LocalAddress.current()
        if address != localAddress { localAddress = address }

        if let failure = pass.failures.first {
            Log.refresh.error("Refresh failed: \(failure.error.displayMessage, privacy: .public)")
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
                let snapshot = try await self.fetch(into: \.inbox) { try await self.workspace.inbox() }
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
        into keyPath: ReferenceWritableKeyPath<DeckController, CardState<Value>>,
        _ load: () async throws -> Value
    ) async throws -> Value {
        self[keyPath: keyPath].beginRefresh()
        do {
            let value = try await load()
            self[keyPath: keyPath].succeed(value, at: Date())
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
    var workingCardTitle: String? {
        for project in activeProjects where stackStatuses[project.id]?.isBusy == true { return project.title }
        for project in activeDDEVProjects where ddevStatuses[project.id]?.isBusy == true { return project.displayTitle }
        for project in activeLocalProjects where localStatuses[project.id]?.isBusy == true { return project.displayTitle }
        return nil
    }

    // MARK: Attention

    /// Labels by account id, only when there is more than one account to tell apart: with one,
    /// naming it on every row is noise.
    var githubLabels: [String: String] {
        accountLabels.count > 1 ? accountLabels : [:]
    }

    var gitlabLabels: [String: String] {
        gitlabAccountLabels.count > 1 ? gitlabAccountLabels : [:]
    }

    /// The projects on the deck, in the words the attention rows name them with.
    var watchedProjects: [WatchedProject] {
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
                kind: $0.subtitle.isEmpty ? "Project" : $0.subtitle,
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
    func attention(update: AttentionItem?) -> AttentionDigest {
        DeckAttention.digest(attentionInput(update: update), now: Date())
    }

    /// When the deck last heard from anything, for the calm menu's "Checked at".
    var lastCheckedAt: Date? {
        [pullRequests.updatedAt, inbox.updatedAt, actions.updatedAt, mergeRequests.updatedAt, checkoutsCheckedAt, docker.checkedAt]
            .compactMap { $0 }
            .max()
    }

    /// Where "Open pull requests in browser" opens: the first account's browser.
    var firstGitHubBrowser: BrowserChoice {
        accountsStore.enabledAccounts().first?.browser ?? .systemDefault
    }

    /// ⌥ on a row: forget what was reported about a project until something new happens to it.
    func dismiss(_ item: AttentionItem) {
        let parts = item.id.split(separator: ":")
        guard parts.count >= 2, parts[0] == "project" else { return }
        watch.dismiss(String(parts[1]))
        updateStatusItem?()
    }

    /// ⌥ on an inbox row.
    func markRead(threadID: String) {
        guard let item = inbox.value?.items.first(where: { $0.id == threadID }) else { return }
        markRead(item)
    }
}
