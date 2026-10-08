import DevDeckCore
import Foundation
import GitHubKit
import ProjectKit

public actor DevDeckEngine {
    private let configuration: EngineConfiguration
    private struct ProjectState {
        let configuration: EngineConfiguration.Project
        let service: LocalProjectService
        var status = LocalProjectStatus(state: .stopped)
        var busy = false
        var refreshTask: Task<Void, Never>?
        var actionTask: Task<Void, Never>?
    }
    private var projects: [String: ProjectState]
    private let httpClient: any HTTPClient
    private let clock: any DateProvider
    private let timeZone: TimeZone
    private let sleeper: any Sleeper
    private let localizationRoot: URL
    private let output: @Sendable (Data) -> Void
    private let tokenStore = InMemoryTokenStore()
    private let pollingEnabled: Bool
    private var githubClient: GitHubClient?
    private var revision = 0
    private var generation = 0
    private var sessionStarted = false
    private var pullsExpanded = false
    private var displays: [EngineIntent.Display] = []
    private var cardSizes: [String: [Double]] = [:]
    private var pullState = CardState<PullRequestsSnapshot>()
    private var stateSettler = StateSettler()
    private var pullRefreshTask: Task<Void, Never>?

    public init(
        configuration: EngineConfiguration, runner: any CommandRunning,
        projectRunners: [String: any CommandRunning] = [:],
        http: any HTTPClient = URLSessionHTTPClient.makeDefault(),
        projectHTTP: (any HTTPClient)? = nil,
        clock: any DateProvider = SystemDateProvider(), sleeper: any Sleeper = TaskSleeper(),
        runtimeFiles: ProjectRuntimeFiles = .standard(),
        timeZone: TimeZone = .autoupdatingCurrent,
        localizationRoot: URL, pollingEnabled: Bool = true,
        output: @escaping @Sendable (Data) -> Void
    ) {
        self.timeZone = timeZone
        self.configuration = configuration
        self.httpClient = http
        self.clock = clock
        self.sleeper = sleeper
        self.localizationRoot = localizationRoot
        self.output = output
        self.pollingEnabled = pollingEnabled
        projects = Dictionary(
            uniqueKeysWithValues: configuration.projects.map { project in
                (
                    "project." + project.id,
                    ProjectState(
                        configuration: project,
                        service: LocalProjectService(
                            project: project.model, runner: projectRunners[project.id] ?? runner,
                            httpClient: projectHTTP ?? http, clock: clock, sleeper: sleeper,
                            files: runtimeFiles))
                )
            })
    }

    public func handle(_ intent: EngineIntent) {
        switch intent.intent {
        case "session.start":
            guard !sessionStarted,
                let language = AppLanguage(rawValue: intent.language ?? configuration.language),
                language == .english || language == .russian,
                let displays = intent.displays, !displays.isEmpty,
                displays.allSatisfy({
                    !$0.id.isEmpty && $0.visibleFrame.count == 4 && $0.visibleFrame.allSatisfy(\.isFinite)
                        && $0.visibleFrame[2] > 0 && $0.visibleFrame[3] > 0 && $0.scale.isFinite
                        && $0.scale > 0
                })
            else {
                reject(intent)
                return
            }
            sessionStarted = true
            self.displays = displays
            Strings.use(language, lookingIn: localizationRoot)
            pullState.fail(.missingToken(configuration.github.label))
            renderPulls(id: intent.id)
            for card in projectIDs {
                renderProject(card, id: intent.id)
                projects[card]?.refreshTask = Task { await self.pollProject(card) }
            }
        case "credentials.set":
            guard sessionStarted, intent.account == configuration.github.account, let token = intent.token,
                !token.isEmpty
            else {
                reject(intent)
                return
            }
            generation += 1
            pullRefreshTask?.cancel()
            try? tokenStore.setToken(token, for: TokenKey(account: configuration.github.account))
            githubClient = GitHubClient(
                transport: APITransport(client: httpClient, sleeper: sleeper), tokenStore: tokenStore,
                tokenKey: TokenKey(account: configuration.github.account))
            pullState = CardState()
            renderPulls(id: intent.id)
            let current = generation
            pullRefreshTask = Task { await self.pollPulls(generation: current) }
        case "card.measured":
            guard sessionStarted, let card = intent.card, cardIDs.contains(card), let size = intent.size,
                size.count == 2, size.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 })
            else {
                reject(intent)
                return
            }
            cardSizes[card] = size
            layout(id: intent.id)
        case "card.setExpanded":
            guard sessionStarted, intent.card == "github.pullRequests", let pullsExpanded = intent.isExpanded
            else {
                reject(intent)
                return
            }
            self.pullsExpanded = pullsExpanded
            renderPulls(id: intent.id)
        case "card.invoke":
            guard sessionStarted, let card = intent.card, let action = intent.action else {
                reject(intent)
                return
            }
            if card == "github.pullRequests", action.hasPrefix("pull."),
                let pull = pullState.value?.pullRequests.first(where: { "pull." + $0.id == action })
            {
                effect(url: pull.url, id: intent.id)
            } else if let project = projects[card], action == "site", project.status.isRunning,
                let url = project.configuration.model.siteURL
            {
                effect(url: url, id: intent.id)
            } else if let project = projects[card], !project.busy,
                let action = LocalProjectAction(rawValue: action),
                (action == .start && !project.status.isRunning && project.status.state != .starting)
                    || (action == .stop && (project.status.isRunning || project.status.state == .starting))
            {
                // A refresh must not replace the transition while a project action is still running.
                projects[card]?.busy = true
                stateSettler.reset(card)
                projects[card]?.status = LocalProjectStatus(
                    state: action == .start ? .starting : .working, checkedAt: clock.now)
                renderProject(card, id: intent.id)
                projects[card]?.actionTask = Task { await self.perform(action, card: card, id: intent.id) }
            } else {
                reject(intent)
            }
        default: reject(intent)
        }
    }

    public func shutdown() async {
        generation += 1
        pullRefreshTask?.cancel()
        let tasks = projects.values.flatMap { [$0.refreshTask, $0.actionTask].compactMap { $0 } }
        for task in tasks { task.cancel() }
        await pullRefreshTask?.value
        for task in tasks { await task.value }
        try? tokenStore.setToken(nil, for: TokenKey(account: configuration.github.account))
    }

    public func waitForSingleRefresh() async {
        guard !pollingEnabled else { return }
        await pullRefreshTask?.value
        for card in projectIDs {
            await projects[card]?.refreshTask?.value
            await projects[card]?.actionTask?.value
        }
    }

    private var projectIDs: [String] { configuration.projects.map { "project." + $0.id } }
    private var cardIDs: [String] { ["github.pullRequests"] + projectIDs }

    private func pollPulls(generation: Int) async {
        var failures = 0
        var delay: TimeInterval = 60
        let policy = RefreshPolicy()
        while !Task.isCancelled, generation == self.generation, let githubClient {
            do {
                let snapshot = try await PullRequestsService(
                    client: githubClient, accountID: configuration.github.account
                )
                .fetch()
                guard !Task.isCancelled, generation == self.generation else { return }
                pullState.succeed(snapshot, at: clock.now)
                failures = 0
                delay = policy.nextDelay(consecutiveFailures: 0)
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                let error = error as? APIError ?? .transport("")
                pullState.fail(error)
                failures += 1
                delay = policy.nextDelay(after: error, consecutiveFailures: failures, now: clock.now)
            }
            renderPulls()
            guard pollingEnabled else { return }
            do {
                try await sleeper.sleep(seconds: delay)
            } catch {
                return
            }
        }
    }

    private func pollProject(_ card: String) async {
        guard let service = projects[card]?.service else { return }
        repeat {
            if projects[card]?.busy == false {
                let observed = await service.status()
                guard !Task.isCancelled else { return }
                if projects[card]?.busy == false,
                    stateSettler.shouldApply(
                        isGood: observed.isRunning, wasGood: projects[card]?.status.isRunning == true,
                        for: card)
                {
                    projects[card]?.status = observed
                    renderProject(card)
                }
            }
            guard pollingEnabled else { return }
            do {
                try await sleeper.sleep(seconds: 5)
            } catch {
                return
            }
        } while !Task.isCancelled
    }

    private func perform(_ action: LocalProjectAction, card: String, id: String) async {
        guard let service = projects[card]?.service else { return }
        let result = await service.perform(action)
        guard !Task.isCancelled else {
            if action == .start { await Task.detached { _ = await service.perform(.stop) }.value }
            projects[card]?.busy = false
            return
        }
        let observed =
            action == .start && result?.succeeded == true
            ? await service.waitUntilRunning(timeout: 30, pollInterval: 0.2)
            : await service.status()
        if action == .start, Task.isCancelled || !observed.isRunning {
            await Task.detached { _ = await service.perform(.stop) }.value
        }
        projects[card]?.busy = false
        guard !Task.isCancelled else { return }
        projects[card]?.status = observed
        if result?.succeeded != true {
            projects[card]?.status.detail = L("project.didNotStayUp")
        }
        renderProject(card, id: id)
    }

    private func renderPulls(id: String? = nil) {
        emit(
            "card.updated",
            card: .list(CardModels.pulls(pullState, expanded: pullsExpanded, timeZone: timeZone)),
            id: id)
    }
    private func renderProject(_ card: String, id: String? = nil) {
        guard let project = projects[card] else { return }
        emit(
            "card.updated",
            card: .project(
                CardModels.project(
                    project.configuration.model, status: project.status, busy: project.busy,
                    timeZone: timeZone)
            ),
            id: id)
    }
    private func layout(id: String) {
        guard let display = displays.first else { return }
        var top = display.visibleFrame[1] + 24
        var placements: [CardPlacement] = []
        for card in cardIDs {
            guard let size = cardSizes[card] else { break }
            placements.append(
                CardPlacement(card: card, display: display.id, topLeft: [display.visibleFrame[0] + 24, top]))
            top += size[1] + 12
        }
        emit("layout.updated", cards: placements, id: id)
    }
    private func effect(url: URL, id: String) {
        emit(
            "effect", effect: OpenURLEffect(kind: "openURL", url: url.absoluteString, browser: "default"),
            id: id)
    }
    private func reject(_ intent: EngineIntent) {
        emit("intent.rejected", reason: "invalidIntent", id: intent.id)
    }
    private func emit(
        _ event: String,
        card: CardModel? = nil,
        cards: [CardPlacement]? = nil,
        effect: OpenURLEffect? = nil,
        reason: String? = nil,
        id: String? = nil
    ) {
        revision += 1
        let envelope = EngineEvent(
            protocolVersion: 2, revision: revision, event: event, id: id,
            card: card, cards: cards, effect: effect, reason: reason)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(envelope), data.count <= 1_048_576 else {
            FileHandle.standardError.write(Data("Could not encode engine event.\n".utf8))
            return
        }
        output(data + Data([10]))
    }
}
