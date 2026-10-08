import DevDeckCore
import Foundation
import GitHubKit
import ProjectKit

public actor DevDeckEngine {
    private let config: EngineConfiguration
    private let projectService: LocalProjectService
    private let http: any HTTPClient
    private let clock: any DateProvider
    private let sleeper: any Sleeper
    private let localizationRoot: URL
    private let output: @Sendable (Data) -> Void
    private let tokens = InMemoryTokenStore()
    private let pollingEnabled: Bool
    private var client: GitHubClient?
    private var revision = 0
    private var generation = 0
    private var started = false
    private var expanded = false
    private var displays: [EngineIntent.Display] = []
    private var sizes: [String: [Double]] = [:]
    private var pulls = CardState<PullRequestsSnapshot>()
    private var projectStatus = LocalProjectStatus(state: .stopped)
    private var projectBusy = false
    private var settler = StateSettler()
    private var pullTask: Task<Void, Never>?
    private var projectPoll: Task<Void, Never>?
    private var projectAction: Task<Void, Never>?

    public init(
        configuration: EngineConfiguration, runner: any CommandRunning,
        http: any HTTPClient = URLSessionHTTPClient.makeDefault(),
        clock: any DateProvider = SystemDateProvider(), sleeper: any Sleeper = TaskSleeper(),
        runtimeFiles: ProjectRuntimeFiles = .standard(),
        localizationRoot: URL, pollingEnabled: Bool = true,
        output: @escaping @Sendable (Data) -> Void
    ) {
        config = configuration; self.http = http; self.clock = clock; self.sleeper = sleeper
        self.localizationRoot = localizationRoot; self.output = output; self.pollingEnabled = pollingEnabled
        projectService = LocalProjectService(project: configuration.project.model, runner: runner,
                                             httpClient: http, clock: clock, sleeper: sleeper, files: runtimeFiles)
    }

    public func handle(_ intent: EngineIntent) {
        switch intent.intent {
        case "session.start":
            guard !started, let language = AppLanguage(rawValue: intent.language ?? config.language),
                  language == .english || language == .russian,
                  let displays = intent.displays, !displays.isEmpty,
                  displays.allSatisfy({ !$0.id.isEmpty && $0.visibleFrame.count == 4 && $0.visibleFrame.allSatisfy(\.isFinite) && $0.visibleFrame[2] > 0 && $0.visibleFrame[3] > 0 && $0.scale.isFinite && $0.scale > 0 }) else { reject(intent); return }
            started = true; self.displays = displays
            Strings.use(language, lookingIn: localizationRoot)
            pulls.fail(.missingToken(config.github.label))
            renderPulls(id: intent.id); renderProject(id: intent.id)
            projectPoll = Task { await self.pollProject() }
        case "credentials.set":
            guard started, intent.account == config.github.account, let token = intent.token, !token.isEmpty else { reject(intent); return }
            generation += 1; pullTask?.cancel()
            try? tokens.setToken(token, for: TokenKey(account: config.github.account))
            client = GitHubClient(transport: APITransport(client: http, sleeper: sleeper), tokenStore: tokens,
                                  tokenKey: TokenKey(account: config.github.account))
            pulls = CardState(); renderPulls(id: intent.id)
            let current = generation
            pullTask = Task { await self.pollPulls(generation: current) }
        case "card.measured":
            guard started, let card = intent.card, cardIDs.contains(card), let size = intent.size,
                  size.count == 2, size.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 }) else { reject(intent); return }
            sizes[card] = size; layout(id: intent.id)
        case "card.setExpanded":
            guard started, intent.card == "github.pullRequests", let expanded = intent.isExpanded else { reject(intent); return }
            self.expanded = expanded; renderPulls(id: intent.id)
        case "card.invoke":
            guard started, let card = intent.card, let action = intent.action else { reject(intent); return }
            if card == "github.pullRequests", action.hasPrefix("pull."),
               let pull = pulls.value?.pullRequests.first(where: { "pull." + $0.id == action }) {
                effect(url: pull.url, id: intent.id)
            } else if card == projectID, action == "site", projectStatus.isRunning,
                      let url = config.project.model.healthCheckURL {
                effect(url: url, id: intent.id)
            } else if card == projectID, !projectBusy, let action = LocalProjectAction(rawValue: action),
                      (action == .start && !projectStatus.isRunning && projectStatus.state != .starting)
                        || (action == .stop && (projectStatus.isRunning || projectStatus.state == .starting)) {
                projectBusy = true; settler.reset(projectID)
                projectStatus = LocalProjectStatus(state: action == .start ? .starting : .working, checkedAt: clock.now)
                renderProject(id: intent.id)
                projectAction = Task { await self.perform(action, id: intent.id) }
            } else { reject(intent) }
        default: reject(intent)
        }
    }

    public func shutdown() async {
        generation += 1; pullTask?.cancel(); projectPoll?.cancel(); projectAction?.cancel()
        await pullTask?.value
        await projectPoll?.value
        await projectAction?.value
        try? tokens.setToken(nil, for: TokenKey(account: config.github.account))
    }

    public func waitForSingleRefresh() async {
        guard !pollingEnabled else { return }
        await pullTask?.value
        await projectPoll?.value
        await projectAction?.value
    }

    private var projectID: String { "project." + config.project.id }
    private var cardIDs: [String] { ["github.pullRequests", projectID] }

    private func pollPulls(generation: Int) async {
        var failures = 0
        var delay: TimeInterval = 60
        let policy = RefreshPolicy()
        while !Task.isCancelled, generation == self.generation, let client {
            do {
                let snapshot = try await PullRequestsService(client: client, accountID: config.github.account).fetch()
                guard !Task.isCancelled, generation == self.generation else { return }
                pulls.succeed(snapshot, at: clock.now); failures = 0
                delay = policy.nextDelay(consecutiveFailures: 0)
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                let error = error as? APIError ?? .transport("")
                pulls.fail(error); failures += 1
                delay = policy.nextDelay(after: error, consecutiveFailures: failures, now: clock.now)
            }
            renderPulls()
            guard pollingEnabled else { return }
            do { try await sleeper.sleep(seconds: delay) } catch { return }
        }
    }

    private func pollProject() async {
        repeat {
            if !projectBusy {
                let observed = await projectService.status()
                guard !Task.isCancelled else { return }
                if !projectBusy, settler.shouldApply(isGood: observed.isRunning, wasGood: projectStatus.isRunning, for: projectID) {
                    projectStatus = observed; renderProject()
                }
            }
            guard pollingEnabled else { return }
            do { try await sleeper.sleep(seconds: 5) } catch { return }
        } while !Task.isCancelled
    }

    private func perform(_ action: LocalProjectAction, id: String) async {
        let result = await projectService.perform(action)
        guard !Task.isCancelled else { projectBusy = false; return }
        let observed = action == .start && result?.succeeded == true
            ? await projectService.waitUntilRunning(timeout: 30, pollInterval: 0.2)
            : await projectService.status()
        projectBusy = false
        guard !Task.isCancelled else { return }
        projectStatus = observed
        if result?.succeeded != true {
            projectStatus.detail = L("project.didNotStayUp")
        }
        renderProject(id: id)
    }

    private func renderPulls(id: String? = nil) {
        emit("card.updated", fields: ["card": CardModels.pulls(pulls, expanded: expanded)], id: id)
    }
    private func renderProject(id: String? = nil) {
        emit("card.updated", fields: ["card": CardModels.project(config.project.model, status: projectStatus, busy: projectBusy)], id: id)
    }
    private func layout(id: String) {
        guard let display = displays.first else { return }
        var y = display.visibleFrame[1] + 24
        var cards: [JSONValue] = []
        for card in cardIDs {
            guard let size = sizes[card] else { break }
            cards.append(["card": .string(card), "display": .string(display.id),
                          "topLeft": [.number(display.visibleFrame[0] + 24), .number(y)]])
            y += size[1] + 12
        }
        emit("layout.updated", fields: ["cards": .array(cards)], id: id)
    }
    private func effect(url: URL, id: String) {
        emit("effect", fields: ["effect": ["kind": "openURL", "url": .string(url.absoluteString), "browser": "default"]], id: id)
    }
    private func reject(_ intent: EngineIntent) {
        emit("intent.rejected", fields: ["reason": "invalidIntent"], id: intent.id)
    }
    private func emit(_ event: String, fields: [String: JSONValue], id: String? = nil) {
        var envelope = fields
        revision += 1
        envelope["protocolVersion"] = 2; envelope["revision"] = .number(Double(revision)); envelope["event"] = .string(event)
        if let id { envelope["id"] = .string(id) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(JSONValue.object(envelope)), data.count <= 1_048_576 else {
            FileHandle.standardError.write(Data("Could not encode engine event.\n".utf8)); return
        }
        output(data + Data([10]))
    }
}
