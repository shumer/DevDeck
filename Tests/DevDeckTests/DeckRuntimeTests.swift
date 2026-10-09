import ArcKit
import DDEVKit
import DevDeckCore
import DevDeckEngine
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit
import TestHarness

// The runtime is what used to be the Mac controller. It could not be tested there, because it
// lived in the app; these are the checks it never had.

/// Answers each command fragment from its own queue; the last answer repeats.
private actor SequenceRunner: CommandRunning {
    private var queues: [(match: String, results: [CommandResult])]

    init(_ queues: [(String, [CommandResult])]) {
        self.queues = queues.map { (match: $0.0, results: $0.1) }
    }

    func run(
        _ command: String,
        in directory: URL,
        timeout: TimeInterval,
        isInteractive: Bool,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> CommandResult {
        guard let index = queues.firstIndex(where: { command.contains($0.match) }) else {
            return CommandResult(exitCode: 127, standardOutput: "", standardError: "command not found")
        }
        let results = queues[index].results
        if results.count > 1 { queues[index].results.removeFirst() }
        return results[0]
    }
}

/// Returns at once and remembers what it was asked to wait for.
private final class RecordingSleeper: Sleeper, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [TimeInterval] = []

    var requests: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    func sleep(seconds: TimeInterval) async throws {
        record(seconds)
    }

    private func record(_ seconds: TimeInterval) {
        lock.lock()
        asked.append(seconds)
        lock.unlock()
    }
}

private let dockerUp = CommandResult(exitCode: 0, standardOutput: "27.0.1", standardError: "")
private let dockerDown = CommandResult(exitCode: 1, standardOutput: "", standardError: "Cannot connect to the Docker daemon")

/// A runtime with in-memory everything, and a record of what it told the shell.
@MainActor
private final class Deck {
    let runtime: DeckRuntime
    let preferences = Preferences(backend: InMemoryPreferences())
    let clock = MutableDateProvider()
    let sleeper = RecordingSleeper()
    let http: FakeHTTPClient
    let account = GitHubAccount(id: "work", label: "Work")
    var fields: [DeckField] = []
    var effects: [DeckEffect] = []

    init(
        cards: Set<CardID>,
        http: FakeHTTPClient = FakeHTTPClient([]),
        runner: any CommandRunning = StubCommandRunner([]),
        localProjects: [LocalProject] = [],
        projectHTTP: (any HTTPClient)? = nil,
        projectFiles: ProjectRuntimeFiles = .standard(),
        gitlabAccounts: [GitLabAccount] = [],
        canStartDocker: Bool = false,
        notifications: Bool = false
    ) {
        self.http = http
        let accounts = GitHubAccountsStore(backend: InMemoryPreferences())
        accounts.save([account])
        let local = LocalProjectsStore(backend: InMemoryPreferences())
        local.save(localProjects)
        preferences.notificationsEnabled = notifications
        let gitlab = GitLabAccountsStore(backend: InMemoryPreferences())
        gitlab.save(gitlabAccounts)
        runtime = DeckRuntime(
            preferences: preferences,
            tokenStore: InMemoryTokenStore(tokens: [account.tokenKey: "token"]),
            accountsStore: accounts,
            gitlabAccountsStore: gitlab,
            projectsStore: ArcProjectsStore(backend: InMemoryPreferences()),
            ddevProjectsStore: DDEVProjectsStore(backend: InMemoryPreferences()),
            localProjectsStore: local,
            commandRunner: runner,
            canStartDocker: canStartDocker,
            localAddress: { nil },
            http: http,
            projectHTTP: projectHTTP,
            projectFiles: projectFiles,
            clock: clock,
            sleeper: sleeper
        )
        runtime.onChange = { [unowned self] in self.fields.append($0) }
        runtime.onEffect = { [unowned self] in self.effects.append($0) }
        runtime.setActiveCards(cards)
        // The loops would run passes of their own; the suite runs them by hand. Cancelled before
        // they get a turn, since nothing here has awaited yet.
        runtime.stop()
    }
}

/// A plain project answering on localhost, with its runtime files in a folder of its own so no
/// test reads or leaves a pid under Application Support.
private func plainSite(holdsProcess: Bool) throws -> (project: LocalProject, files: ProjectRuntimeFiles) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-runtime-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let project = LocalProject(
        id: "site-\(UUID().uuidString)",
        title: "Site",
        folder: directory.path,
        startCommand: holdsProcess ? "npm run dev" : "docker compose up -d",
        holdsProcess: holdsProcess,
        healthURL: "http://localhost:5173"
    )
    return (project, ProjectRuntimeFiles(directory: directory))
}

@MainActor
func runDeckRuntimeTests(_ run: TestRun) async {
    run.section("Deck runtime - the remote cards")

    await run.test("a pass fills the cards it asks, and one failing card leaves the others alone") {
        let deck = Deck(cards: [.githubPullRequests, .githubInbox], http: FakeHTTPClient(routes: [
            ("graphql", .success(.status(401))),
            ("/notifications", .success(.json(Fixtures.notifications))),
        ]))
        _ = await deck.runtime.refreshOnce()
        try expect(deck.runtime.pullRequests.failure != nil, "the pull requests card should carry its failure")
        let inbox = try expectNotNil(deck.runtime.inbox.value, "inbox")
        try expect(!inbox.items.isEmpty)
    }

    await run.test("a hidden card is never asked") {
        let deck = Deck(cards: [.githubInbox], http: FakeHTTPClient(routes: [
            ("/notifications", .success(.json(Fixtures.notifications))),
        ]))
        _ = await deck.runtime.refreshOnce()
        try expectNil(await deck.http.request(matching: "graphql"), "the pull requests card is hidden")
        try expectNil(deck.runtime.pullRequests.value)
    }

    await run.test("the wait doubles while every pass fails and drops back after one that works") {
        let deck = Deck(cards: [.githubPullRequests], http: FakeHTTPClient([
            .success(.status(401)),
            .success(.status(401)),
            .success(.json(Fixtures.pullRequestSearch)),
        ]))
        let policy = deck.runtime.refreshPolicy
        try expectEqual(await deck.runtime.refreshOnce(), policy.nextDelay(consecutiveFailures: 1))
        try expectEqual(await deck.runtime.refreshOnce(), policy.nextDelay(consecutiveFailures: 2))
        try expectEqual(await deck.runtime.refreshOnce(), policy.nextDelay(consecutiveFailures: 0))
        try expect(deck.runtime.pullRequests.value != nil)
    }

    run.section("Deck runtime - the inbox")

    await run.test("a poll in the middle of marking does not put back what is being marked") {
        let deck = Deck(cards: [.githubInbox], http: FakeHTTPClient(routes: [
            ("/notifications/threads", .success(.status(205))),
            ("/notifications", .success(.json(Fixtures.notifications))),
        ]))
        _ = await deck.runtime.refreshOnce()
        try expect(deck.runtime.inbox.value?.items.contains { $0.id == "2" } == true, "thread 2 is not for you")

        deck.runtime.markRestRead()
        try expectEqual(deck.runtime.inboxProgress, .gathering)
        try expect(deck.runtime.inbox.value?.items.contains { $0.id == "2" } == false, "taken off at once")

        // GitHub still lists it, as it does for a while after a read.
        _ = await deck.runtime.refreshOnce()
        try expect(deck.runtime.inbox.value?.items.contains { $0.id == "2" } == false, "the poll put it back")

        await deck.runtime.settle()
        try expect(await deck.http.request(matching: "/notifications/threads/2") != nil, "thread 2 was never marked")
        try expect(await deck.http.request(matching: "/notifications/threads/1") == nil, "a review request was marked")
        try expect(deck.sleeper.requests.contains(5), "the footer's word should stay for five seconds")
        try expectNil(deck.runtime.inboxProgress, "the footer clears itself")
    }

    await run.test("a refusal is said in the footer, and what was refused comes back") {
        let deck = Deck(cards: [.githubInbox], http: FakeHTTPClient(routes: [
            ("/notifications/threads", .success(.status(403))),
            ("/notifications", .success(.json(Fixtures.notifications))),
        ]))
        _ = await deck.runtime.refreshOnce()
        deck.runtime.markRestRead()
        await deck.runtime.settle()
        try expect(deck.sleeper.requests.contains(12), "a failure stays on screen longer")
        try expect(deck.runtime.inbox.value?.items.contains { $0.id == "2" } == true, "the refused thread should be back")
    }

    await run.test("a row marked read leaves the card at once, and the menu is told") {
        let deck = Deck(cards: [.githubInbox], http: FakeHTTPClient(routes: [
            ("/notifications/threads", .success(.status(205))),
            ("/notifications", .success(.json(Fixtures.notifications))),
        ]))
        _ = await deck.runtime.refreshOnce()
        deck.runtime.markRead(threadID: "3")
        try expect(deck.runtime.inbox.value?.items.contains { $0.id == "3" } == false)
        try expect(deck.effects.contains(.attentionChanged))
        await deck.runtime.settle()
        try expect(await deck.http.request(matching: "/notifications/threads/3") != nil)
    }

    run.section("Deck runtime - Docker and projects")

    await run.test("Docker is not called down on one missed probe") {
        let runner = SequenceRunner([(DockerEnvironment.probeCommand, [dockerUp, dockerDown, dockerDown])])
        let deck = Deck(cards: [], runner: runner)
        await deck.runtime.refreshLocalOnce()
        try expectEqual(deck.runtime.docker.state, .running)
        await deck.runtime.refreshLocalOnce()
        try expectEqual(deck.runtime.docker.state, .running, "one miss is a hiccup")
        await deck.runtime.refreshLocalOnce()
        try expectEqual(deck.runtime.docker.state, .notRunning, "two in a row is news")
    }

    await run.test("starting Docker is shown for up to three minutes, and the shell launches it") {
        let runner = SequenceRunner([(DockerEnvironment.probeCommand, [dockerDown])])
        let deck = Deck(cards: [], runner: runner, canStartDocker: true)
        deck.runtime.startDockerRuntime()
        try expectEqual(deck.runtime.docker.state, .starting)
        try expectEqual(deck.effects, [.launchDocker])
        deck.clock.advance(by: 170)
        await deck.runtime.refreshLocalOnce()
        try expectEqual(deck.runtime.docker.state, .starting, "still within the window")
        deck.clock.advance(by: 20)
        await deck.runtime.refreshLocalOnce()
        try expectEqual(deck.runtime.docker.state, .notRunning)
    }

    await run.test("a machine with nothing to launch launches nothing") {
        let deck = Deck(cards: [], canStartDocker: false)
        deck.runtime.startDockerRuntime()
        try expectEqual(deck.runtime.docker.state, .unknown)
        try expect(deck.effects.isEmpty)
    }

    await run.test("a failed start stays on the card with its reason") {
        let project = LocalProject(
            id: "runtime-test-\(UUID().uuidString)",
            title: "Demo",
            folder: FileManager.default.temporaryDirectory.path,
            startCommand: "npm run dev"
        )
        let deck = Deck(cards: [project.cardID], localProjects: [project])
        deck.runtime.perform(.start, for: project)
        try expectEqual(deck.runtime.localStatus(for: project).state, .working, "a press shows at once")
        await deck.runtime.settle()
        let status = deck.runtime.localStatus(for: project)
        try expectEqual(status.state, .stopped)
        try expectEqual(status.detail, "command not found")
    }

    await run.test("a project started outside DevDeck is never stopped from here") {
        let site = try plainSite(holdsProcess: true)
        let runner = StubCommandRunner([(DockerEnvironment.probeCommand, dockerUp)])
        let deck = Deck(
            cards: [site.project.cardID],
            runner: runner,
            localProjects: [site.project],
            projectHTTP: FakeHTTPClient(routes: [("localhost", .success(HTTPResponse(statusCode: 200)))]),
            projectFiles: site.files
        )
        await deck.runtime.refreshLocalOnce()
        let running = deck.runtime.localStatus(for: site.project)
        try expect(running.isRunning)
        try expectNil(running.pid)
        try expectEqual(running.stopBlock, .startedElsewhere)

        deck.runtime.perform(.stop, for: site.project)
        deck.runtime.perform(.restart, for: site.project)
        await deck.runtime.settle()
        let commands = await runner.commands
        try expectEqual(commands.filter { !$0.contains(DockerEnvironment.probeCommand) }, [], "nothing is killed, by pid, port or name")
        try expect(deck.runtime.localStatus(for: site.project).isRunning, "the card stays as it was")
        try expectEqual(deck.runtime.watch.problems(for: site.project.id, now: deck.clock.now),
                        [.cannotStop(.startedElsewhere, at: deck.clock.now)], "not a stop that did not take")
        let row = try expectNotNil(deck.runtime.attention(update: nil).items.first, "a row")
        try expectEqual(row.title, "DevDeck can't stop Site")
        try expectEqual(row.subtitle, "Started outside DevDeck · stop it where you started it")
        try expectEqual(row.tier, .goodToKnow)
    }

    await run.test("a project whose start returns has nothing to stop without a stop command") {
        let site = try plainSite(holdsProcess: false)
        let deck = Deck(
            cards: [site.project.cardID],
            localProjects: [site.project],
            projectHTTP: FakeHTTPClient(routes: [("localhost", .success(HTTPResponse(statusCode: 200)))]),
            projectFiles: site.files
        )
        await deck.runtime.refreshLocalOnce()
        try expectEqual(deck.runtime.localStatus(for: site.project).stopBlock, .noStopCommand)
        deck.runtime.perform(.stop, for: site.project)
        try expectEqual(deck.runtime.attention(update: nil).items.first?.subtitle, "No stop command set · add one in Settings")
    }

    await run.test("a stop command is tried, and a stop that then did not take still says so") {
        var site = try plainSite(holdsProcess: true)
        site.project.stopCommand = "docker compose down"
        let runner = StubCommandRunner([
            (DockerEnvironment.probeCommand, dockerUp),
            ("docker compose down", CommandResult(exitCode: 0, standardOutput: "", standardError: "")),
        ])
        let deck = Deck(
            cards: [site.project.cardID],
            runner: runner,
            localProjects: [site.project],
            projectHTTP: FakeHTTPClient(routes: [("localhost", .success(HTTPResponse(statusCode: 200)))]),
            projectFiles: site.files
        )
        await deck.runtime.refreshLocalOnce()
        try expectNil(deck.runtime.localStatus(for: site.project).stopBlock)
        deck.runtime.perform(.stop, for: site.project)
        await deck.runtime.settle()
        try expect(await runner.commands.contains { $0.contains("docker compose down") }, "the stop command ran")
        try expectEqual(deck.runtime.watch.problems(for: site.project.id, now: deck.clock.now),
                        [.stopDidNotTakeEffect(at: deck.clock.now)])
    }

    await run.test("a process DevDeck started is stopped by its own tree, and nothing else") {
        let site = try plainSite(holdsProcess: true)
        // A pid that is certainly alive and certainly not a server: this suite. The runner is a
        // stub, so the kill is only recorded.
        let pid = ProcessInfo.processInfo.processIdentifier
        try "\(pid)\n".write(to: site.files.pid(site.project.id), atomically: true, encoding: .utf8)
        let runner = StubCommandRunner([(DockerEnvironment.probeCommand, dockerUp)])
        let deck = Deck(
            cards: [site.project.cardID],
            runner: runner,
            localProjects: [site.project],
            projectHTTP: FakeHTTPClient(routes: [("localhost", .success(HTTPResponse(statusCode: 200)))]),
            projectFiles: site.files
        )
        await deck.runtime.refreshLocalOnce()
        let running = deck.runtime.localStatus(for: site.project)
        try expectEqual(running.pid, pid)
        try expectNil(running.stopBlock)
        deck.runtime.perform(.stop, for: site.project)
        await deck.runtime.settle()
        let kills = await runner.commands.filter { $0.contains("kill") }
        try expectEqual(kills, [LocalProjectService.killTreeCommand(pid: pid)])
    }

    await run.test("only a running project with no process and no stop command is out of reach") {
        let held = LocalProject(id: "a", title: "A", startCommand: "npm run dev", holdsProcess: true)
        let returns = LocalProject(id: "b", title: "B", startCommand: "docker compose up -d")
        var withStop = held
        withStop.stopCommand = "  pkill -f vite  "
        let running = LocalProjectStatus(state: .running)
        try expectEqual(DeckRuntime.stopBlock(for: held, status: running), .startedElsewhere)
        try expectEqual(DeckRuntime.stopBlock(for: returns, status: running), .noStopCommand)
        try expectNil(DeckRuntime.stopBlock(for: withStop, status: running))
        try expectNil(DeckRuntime.stopBlock(for: held, status: LocalProjectStatus(state: .running, pid: 42)))
        try expectNil(DeckRuntime.stopBlock(for: held, status: LocalProjectStatus(state: .stopped)))
        try expectNil(DeckRuntime.stopBlock(for: held, status: LocalProjectStatus(state: .starting, pid: 42)))
    }

    run.section("Deck runtime - folding, parking and being told")

    await run.test("a folded card is remembered, an expanded one and a parked one are not") {
        let deck = Deck(cards: [.githubPullRequests, .githubInbox])
        deck.runtime.toggleCollapsed(.githubPullRequests)
        try expect(deck.runtime.isCollapsed(.githubPullRequests))
        try expect(deck.preferences.isCollapsed(.githubPullRequests), "folding is a choice worth keeping")

        deck.runtime.toggleExpanded(.githubInbox)
        try expect(deck.runtime.isExpanded(.githubInbox))

        deck.runtime.setParked([.githubInbox])
        try expect(deck.runtime.isCollapsed(.githubInbox))
        try expect(!deck.runtime.isCollapsedByChoice(.githubInbox))
        try expect(!deck.preferences.isCollapsed(.githubInbox), "parking is not a choice")

        try expectEqual(deck.runtime.takeUserResizes(), [.githubPullRequests, .githubInbox])
        try expectEqual(deck.runtime.takeUserResizes(), [], "handed over once")
    }

    await run.test("every assignment is reported, even one that changes nothing") {
        let runner = SequenceRunner([(DockerEnvironment.probeCommand, [dockerUp])])
        let deck = Deck(cards: [], runner: runner)
        await deck.runtime.refreshLocalOnce()
        await deck.runtime.refreshLocalOnce()
        try expectEqual(deck.fields.filter { $0 == .docker }.count, 2, "the menu redraws off each probe")
    }

    await run.test("a field is reported after it holds its new value") {
        let deck = Deck(cards: [.githubInbox])
        var seen: Bool?
        deck.runtime.onChange = { [unowned deck] field in
            if field == .expandedCards { seen = deck.runtime.isExpanded(.githubInbox) }
        }
        deck.runtime.toggleExpanded(.githubInbox)
        try expectEqual(seen, true)
    }

    await run.test("the log button asks the shell to open the window, and to close it again") {
        let project = LocalProject(id: "logs", title: "Logs", folder: "/tmp", startCommand: "npm run dev")
        let deck = Deck(cards: [project.cardID], localProjects: [project])
        deck.runtime.toggleLogs(for: project.cardID)
        try expectEqual(deck.effects, [.openLogs(project.cardID)])
        deck.runtime.logWindowOpened(project.cardID)
        deck.runtime.toggleLogs(for: project.cardID)
        try expectEqual(deck.effects.last, .closeLogs(project.cardID))
    }

    run.section("Deck runtime - what a card's click asks for")

    await run.test("a row opens in the browser of the account it came from") {
        let deck = Deck(cards: [.githubPullRequests])
        let url = URL(string: "https://github.com/acme/site/pull/1")!
        deck.runtime.perform(.openLink(url, account: deck.account.id, service: .github))
        try expectEqual(deck.effects, [.openURL(url, deck.account.browser)])
    }

    await run.test("the card's own page is the runtime's to know, and opens in the first account's browser") {
        let deck = Deck(cards: [.githubPullRequests])
        deck.runtime.perform(.openDashboard(.githubPullRequests))
        try expectEqual(deck.effects, [.openURL(URL(string: "https://github.com/pulls")!, deck.account.browser)])
    }

    await run.test("the expander's click expands, and the model says so") {
        let deck = Deck(cards: [.githubPullRequests])
        deck.runtime.perform(.toggleExpanded(.githubPullRequests))
        guard case .reviewList(let model)? = deck.runtime.model(for: .githubPullRequests) else {
            throw TestFailure(message: "no pull requests model", file: #filePath, line: #line)
        }
        try expect(model.isExpanded)
    }

    await run.test("the GitLab card's own page opens in the GitLab account's browser") {
        let firefox = BrowserChoice(bundleIdentifier: "org.mozilla.firefox")
        let deck = Deck(cards: [.gitlabMergeRequests], gitlabAccounts: [GitLabAccount(id: "lab", label: "Lab", browser: firefox)])
        deck.runtime.perform(.openDashboard(.gitlabMergeRequests))
        try expectEqual(deck.effects, [.openURL(URL(string: "https://gitlab.com/dashboard/merge_requests")!, firefox)])
    }

    await run.test("a card that points at a setting asks the shell to open it") {
        let deck = Deck(cards: [.githubActions])
        deck.runtime.perform(.openSetting(.actionsRepositories))
        try expectEqual(deck.effects, [.openSetting(.actionsRepositories)])
    }

    await run.test("a checkout the deck does not know opens nothing") {
        let deck = Deck(cards: [.workInFlight])
        deck.runtime.perform(.openCheckout(id: "nowhere"))
        try expect(deck.effects.isEmpty)
    }

    await run.test("a project's links open in that project's browser, and its buttons reach it") {
        let chrome = BrowserChoice(bundleIdentifier: "com.google.Chrome", profileDirectory: "Profile 2")
        var project = LocalProject(id: "links-\(UUID().uuidString)", title: "Links", folder: FileManager.default.temporaryDirectory.path, startCommand: "npm run dev")
        project.browser = chrome
        // Runtime files in a folder of its own, so a start leaves nothing under Application Support.
        let files = ProjectRuntimeFiles(directory: FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-links-\(UUID().uuidString)"))
        let deck = Deck(cards: [project.cardID], localProjects: [project], projectFiles: files)
        let site = URL(string: "http://localhost:3000")!
        deck.runtime.perform(.openProjectLink(project.cardID, site))
        deck.runtime.perform(.revealFolder(project.cardID))
        deck.runtime.perform(.openTerminal(project.cardID))
        try expectEqual(deck.effects, [
            .openURL(site, chrome),
            .revealFolder(try expectNotNil(project.folderURL, "folder")),
            .openTerminal(try expectNotNil(project.folderURL, "folder")),
        ])
        deck.runtime.perform(.project(project.cardID, .start))
        try expectEqual(deck.runtime.localStatus(for: project).state, .working, "Start reached the project")
        await deck.runtime.settle()
    }

    await run.test("the card's Start Docker is the runtime's own") {
        let deck = Deck(cards: [], canStartDocker: true)
        deck.runtime.perform(.startDocker)
        try expectEqual(deck.runtime.docker.state, .starting)
    }

    run.section("Deck runtime - banners")

    await run.test("the first pass is quiet, a repeat is not news, and something new is") {
        let deck = Deck(cards: [.githubPullRequests], http: FakeHTTPClient([
            .success(.json(Fixtures.pullRequestSearch)),
            .success(.json(Fixtures.pullRequestSearch)),
            // The same deck, with one review request that was not there before.
            .success(.json(Fixtures.pullRequestSearch.replacingOccurrences(of: "PR_review", with: "PR_review_new"))),
        ]), notifications: true)
        _ = await deck.runtime.refreshOnce()
        _ = await deck.runtime.refreshOnce()
        try expect(deck.effects.isEmpty, "got \(deck.effects)")
        _ = await deck.runtime.refreshOnce()
        guard case .announce(let alerts)? = deck.effects.last else {
            throw TestFailure(message: "nothing was announced", file: #filePath, line: #line)
        }
        try expectEqual(alerts.map(\.kind), [.reviewRequest])
    }

    await run.test("with banners off nothing is gathered or remembered") {
        let deck = Deck(cards: [.githubPullRequests], http: FakeHTTPClient([
            .success(.json(Fixtures.pullRequestSearch)),
            .success(.json(Fixtures.pullRequestSearch.replacingOccurrences(of: "PR_review", with: "PR_review_new"))),
        ]), notifications: false)
        _ = await deck.runtime.refreshOnce()
        _ = await deck.runtime.refreshOnce()
        try expect(deck.effects.isEmpty)
        try expect(deck.preferences.announcedAlerts.isEmpty)
    }
}
