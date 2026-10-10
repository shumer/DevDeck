import ArcKit
import DDEVKit
import DevDeckCore
import DevDeckEngine
import DevDeckLocalization
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit
import TestHarness

// Golden transcripts of the deck runtime: every card's model, folded and expanded, both menus,
// the menu-bar status, the banners and placement through an unplugged monitor, in English and
// Russian. Each scenario writes one JSON object per line; the same scenario must give the same
// bytes on the Mac and on Windows, which is what keeps the two shells drawing the same deck.

enum RuntimeFixture {
    static let now = Date(timeIntervalSince1970: 1_791_000_000)

    static let pulls = """
    {"data":{"viewer":{"login":"demo"},
     "mine":{"issueCount":3,"nodes":[
      {"id":"blocked","number":12,"title":"DEMO-12 - Fix the feed","url":"https://example.invalid/pull/12","isDraft":false,"updatedAt":"2026-10-08T12:00:00Z","repository":{"nameWithOwner":"demo/site","owner":{"login":"demo"}},"reviewDecision":"CHANGES_REQUESTED","reviewThreads":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}},
      {"id":"ready","number":13,"title":"DEMO-13 - Ship the menu","url":"https://example.invalid/pull/13","isDraft":false,"updatedAt":"2026-10-08T11:00:00Z","repository":{"nameWithOwner":"demo/site","owner":{"login":"demo"}},"reviewDecision":"APPROVED","reviewThreads":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}},
      {"id":"waiting","number":14,"title":"Tidy the docs","url":"https://example.invalid/pull/14","isDraft":false,"updatedAt":"2026-10-08T10:00:00Z","repository":{"nameWithOwner":"demo/docs","owner":{"login":"demo"}},"reviewDecision":"REVIEW_REQUIRED","reviewThreads":{"nodes":[{"isResolved":false}]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING"}}}]}}
     ]},
     "reviewing":{"issueCount":1,"nodes":[
      {"id":"review","number":90,"title":"DEMO-90 - Review the parser","url":"https://example.invalid/pull/90","isDraft":false,"updatedAt":"2026-10-08T09:00:00Z","repository":{"nameWithOwner":"demo/site","owner":{"login":"demo"}},"reviewDecision":"REVIEW_REQUIRED","author":{"login":"sam"},"mergeable":"MERGEABLE","timelineItems":{"nodes":[{"createdAt":"2026-10-08T08:00:00Z","actor":{"login":"sam"},"requestedReviewer":{"login":"demo"}}]},"reviewThreads":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}
     ]}}}
    """

    static let notifications = """
    [
     {"id":"1","unread":true,"reason":"review_requested","updated_at":"2026-10-08T12:00:00Z","subject":{"title":"Review the parser","url":"https://api.github.com/repos/demo/site/pulls/90","type":"PullRequest"},"repository":{"full_name":"demo/site"}},
     {"id":"2","unread":true,"reason":"ci_activity","updated_at":"2026-10-08T11:00:00Z","subject":{"title":"main failed","url":null,"type":"CheckSuite"},"repository":{"full_name":"demo/site"}},
     {"id":"3","unread":true,"reason":"mention","updated_at":"2026-10-08T10:00:00Z","subject":{"title":"A question about the feed","url":"https://api.github.com/repos/demo/docs/issues/7","type":"Issue"},"repository":{"full_name":"demo/docs"}},
     {"id":"4","unread":false,"reason":"comment","updated_at":"2026-10-07T10:00:00Z","subject":{"title":"Old thread","url":"https://api.github.com/repos/demo/docs/issues/3","type":"Issue"},"repository":{"full_name":"demo/docs"}}
    ]
    """

    static let runs = """
    {"total_count":3,"workflow_runs":[
     {"id":1,"name":"ci","head_branch":"main","status":"completed","conclusion":"success","created_at":"2026-10-08T10:00:00Z","run_started_at":"2026-10-08T10:00:00Z","updated_at":"2026-10-08T10:06:00Z","html_url":"https://example.invalid/runs/1"},
     {"id":2,"name":"ci","head_branch":"main","status":"completed","conclusion":"failure","created_at":"2026-10-08T11:00:00Z","run_started_at":"2026-10-08T11:00:00Z","updated_at":"2026-10-08T11:08:00Z","html_url":"https://example.invalid/runs/2"},
     {"id":3,"name":"deploy","head_branch":"main","status":"in_progress","conclusion":null,"created_at":"2026-10-08T12:00:00Z","updated_at":"2026-10-08T12:02:00Z","html_url":"https://example.invalid/runs/3"}
    ]}
    """

    static let repository = #"{"default_branch":"main"}"#

    static let merges = """
    {"data":{"currentUser":{
     "mine":{"count":2,"nodes":[
      {"id":"gid://gitlab/MergeRequest/1","iid":"41","title":"DEMO-41 - Drop the poller","webUrl":"https://gitlab.example.invalid/demo/web/-/merge_requests/41","draft":false,"conflicts":false,"updatedAt":"2026-10-08T09:00:00Z","approvalsLeft":0,"project":{"fullPath":"demo/web"},"headPipeline":{"status":"FAILED"},"discussions":{"nodes":[]}},
      {"id":"gid://gitlab/MergeRequest/2","iid":"42","title":"Cache the index","webUrl":"https://gitlab.example.invalid/demo/web/-/merge_requests/42","draft":false,"conflicts":false,"updatedAt":"2026-10-08T08:00:00Z","approvalsLeft":0,"project":{"fullPath":"demo/web"},"headPipeline":{"status":"SUCCESS"},"discussions":{"nodes":[]}}
     ]},
     "reviewing":{"count":0,"nodes":[]}}}}
    """

    static var http: FakeHTTPClient {
        FakeHTTPClient(routes: [
            ("gitlab.example.invalid", .success(.json(merges))),
            ("/graphql", .success(.json(pulls))),
            ("/notifications", .success(.json(notifications))),
            ("/actions/runs", .success(.json(runs))),
            ("/repos/demo/site", .success(.json(repository))),
        ])
    }
}

/// Returns at once.
struct InstantSleeper: Sleeper {
    func sleep(seconds: TimeInterval) async throws {}
}

/// A deck with every kind of card, in-memory everything and a fixed clock.
@MainActor
func goldenRuntime(
    http: FakeHTTPClient = RuntimeFixture.http,
    commandRunner: any CommandRunning = StubCommandRunner([]),
    folderRunner: (@Sendable (String?) -> any CommandRunning)? = nil
) -> (DeckRuntime, Preferences) {
    let preferences = Preferences(backend: InMemoryPreferences())
    preferences.notificationsEnabled = true
    preferences.actionsRepositories = ["demo/site"]
    let account = GitHubAccount(id: "work", label: "Work")
    let accounts = GitHubAccountsStore(backend: InMemoryPreferences())
    accounts.save([account])
    let gitlabAccount = GitLabAccount(id: "lab", label: "Lab", host: URL(string: "https://gitlab.example.invalid")!)
    let gitlab = GitLabAccountsStore(backend: InMemoryPreferences())
    gitlab.save([gitlabAccount])
    let arc = ArcProjectsStore(backend: InMemoryPreferences())
    arc.save([ArcProject(id: "paper", title: "Paper", organization: "demo")])
    let ddev = DDEVProjectsStore(backend: InMemoryPreferences())
    ddev.save([DDEVProject(id: "shop", name: "shop", folder: "/invalid/shop")])
    let local = LocalProjectsStore(backend: InMemoryPreferences())
    local.save([LocalProject(
        id: "feed", title: "Feed", subtitle: "bun · next", folder: "/invalid/feed",
        startCommand: "bun run dev", holdsProcess: true, healthURL: "http://localhost:3000"
    )])
    let runtime = DeckRuntime(
        preferences: preferences,
        tokenStore: InMemoryTokenStore(tokens: [account.tokenKey: "token", gitlabAccount.tokenKey: "token"]),
        accountsStore: accounts,
        gitlabAccountsStore: gitlab,
        projectsStore: arc,
        ddevProjectsStore: ddev,
        localProjectsStore: local,
        commandRunner: commandRunner,
        canStartDocker: true,
        localAddress: { nil },
        http: http,
        projectHTTP: FakeHTTPClient([.failure(APIError.transport("offline fixture"))]),
        projectFiles: ProjectRuntimeFiles(directory: URL(fileURLWithPath: "/invalid/runtime")),
        clock: MutableDateProvider(now: RuntimeFixture.now),
        sleeper: InstantSleeper(),
        folderRunner: folderRunner
    )
    for descriptor in runtime.cards.catalog {
        runtime.cards.setEnabled(descriptor.isImplemented, for: descriptor.id)
    }
    runtime.setActiveCards(Set(runtime.cards.visible))
    // The loops would run passes of their own; the transcript runs them by hand.
    runtime.stop()
    return (runtime, preferences)
}

/// One line of a transcript.
private struct Line<Value: Encodable>: Encodable {
    let step: String
    let value: Value
}

private final class Transcript {
    private var data = Data()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    func write<Value: Encodable>(_ step: String, _ value: Value) throws {
        data.append(try encoder.encode(Line(step: step, value: value)))
        data.append(0x0A)
    }

    var bytes: Data { data }
}

/// A card's model under the name of its kind, since the enum that holds them is the engine's
/// own and not a wire type yet.
private struct CardLine: Encodable {
    let card: String
    var reviewList: ReviewListCardModel?
    var inbox: InboxCardModel?
    var actions: ActionsCardModel?
    var workInFlight: WorkInFlightCardModel?
    var project: DeckProjectCardModel?

    init(_ card: CardID, _ model: DeckCardModel?) {
        self.card = card.rawValue
        switch model {
        case .reviewList(let value): reviewList = value
        case .inbox(let value): inbox = value
        case .actions(let value): actions = value
        case .workInFlight(let value): workInFlight = value
        case .project(let value): project = value
        case nil: break
        }
    }
}

/// A frame as four numbers: what both platforms print the same way.
private struct Frame: Encodable {
    let card: String
    let change: String
    let frame: [Double]

    init(_ change: DeckPanelChange) {
        switch change {
        case .close(let card): self.card = card.rawValue; self.change = "close"; frame = []
        case .open(let card, let rect): self.card = card.rawValue; self.change = "open"; frame = Self.numbers(rect)
        case .place(let card, let rect): self.card = card.rawValue; self.change = "place"; frame = Self.numbers(rect)
        }
    }

    private static func numbers(_ rect: CGRect) -> [Double] {
        [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
    }
}

@MainActor
private func cardsTranscript(_ transcript: Transcript, _ runtime: DeckRuntime) throws {
    for card in runtime.cards.visible {
        try transcript.write("card", CardLine(card, runtime.model(for: card)))
    }
}

@MainActor
private func runtimeScenario(_ name: String) async throws -> Data {
    let language: AppLanguage = name.hasSuffix("-ru") ? .russian : .english
    Strings.use(language, lookingIn: LocalizationResources.root)
    defer { Strings.use(.english, lookingIn: LocalizationResources.root) }
    let transcript = Transcript()
    // The banners scenario asks the pull requests alone, twice, and the second answer has a
    // review request the first did not.
    let (runtime, _) = name.hasPrefix("runtime-banners")
        ? goldenRuntime(http: FakeHTTPClient([
            .success(.json(RuntimeFixture.pulls)),
            .success(.json(RuntimeFixture.pulls.replacingOccurrences(of: "\"id\":\"review\"", with: "\"id\":\"review-new\""))),
        ]))
        : goldenRuntime()
    var effects: [DeckEffect] = []
    runtime.onEffect = { effects.append($0) }

    switch name.dropLast(3) {
    case "runtime-cards":
        try cardsTranscript(transcript, runtime)
        _ = await runtime.refreshOnce()
        await runtime.refreshLocalOnce()
        try cardsTranscript(transcript, runtime)
        runtime.toggleExpanded(.githubPullRequests)
        runtime.toggleCollapsed(.githubInbox)
        runtime.toggleCollapsed(CardID(rawValue: "project.feed"))
        try transcript.write("card", CardLine(.githubPullRequests, runtime.model(for: .githubPullRequests)))
        try transcript.write("card", CardLine(.githubInbox, runtime.model(for: .githubInbox)))
        try transcript.write("card", CardLine(CardID(rawValue: "project.feed"), runtime.model(for: CardID(rawValue: "project.feed"))))

    case "runtime-menu":
        try transcript.write("status", runtime.status())
        try transcript.write("menu", runtime.menu())
        _ = await runtime.refreshOnce()
        await runtime.refreshLocalOnce()
        try transcript.write("status", runtime.status())
        try transcript.write("menu", runtime.menu())
        try transcript.write("inboxMenu", runtime.cardMenu(for: .githubInbox))
        try transcript.write("projectMenu", runtime.cardMenu(for: CardID(rawValue: "project.feed")))

    case "runtime-banners":
        runtime.setActiveCards([.githubPullRequests])
        runtime.stop()
        _ = await runtime.refreshOnce()
        try transcript.write("firstPass", effects.compactMap(\.banners))
        effects.removeAll()
        _ = await runtime.refreshOnce()
        try transcript.write("secondPass", effects.compactMap(\.banners))
        let many = (1...4).map { index in
            DeckAlert(
                id: "review:\(index)", kind: .reviewRequest, source: .github, title: "Review \(index)",
                subtitle: "demo/site #\(index)", body: "", subject: "Change \(index)", target: .menu, isQuiet: false
            )
        }
        try transcript.write("summary", DeckRuntime.banners(for: many))

    default:
        throw TestFailure(message: "no scenario \(name)", file: #filePath, line: #line)
    }
    return transcript.bytes
}

/// Placement needs no language: it is all numbers.
@MainActor
private func placementScenario() async throws -> Data {
    let transcript = Transcript()
    let (runtime, _) = goldenRuntime()
    let laptop = DisplayFrame(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))
    let external = DisplayFrame(id: "external", visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1410))
    var screens = [laptop, external]
    let placement = runtime.placePanels(
        measure: { card in CGSize(width: 352, height: card.rawValue.hasPrefix("project.") ? 209 : 182) },
        displays: { DeckDisplays(screens: screens, main: laptop, fallback: laptop) }
    )
    try transcript.write("open", placement.sync().map(Frame.init))

    // A person drags the plain project onto the monitor, and it is believed.
    let feed = CardID(rawValue: "project.feed")
    _ = placement.moved(feed, to: CGRect(x: 2000, y: 1000, width: 352, height: 209), at: 10)
    _ = placement.settleMoves(at: 20)
    try transcript.write("tidy", placement.tidy().map(Frame.init))

    // Unplugged: the window server's shove first, the screen change after.
    _ = placement.moved(feed, to: CGRect(x: 100, y: 100, width: 352, height: 209), at: 30)
    screens = [laptop]
    placement.screensChanged()
    _ = placement.settleMoves(at: 31)
    try transcript.write("unplugged", placement.placeAfterScreensChanged().map(Frame.init))
    try transcript.write("parked", runtime.parkedCards.map(\.rawValue).sorted())

    screens = [laptop, external]
    placement.screensChanged()
    try transcript.write("pluggedBack", placement.placeAfterScreensChanged().map(Frame.init))
    return transcript.bytes
}

private extension DeckEffect {
    var banners: [DeckAlert]? {
        if case .announce(let alerts) = self { return alerts }
        return nil
    }
}

@MainActor
func runRuntimeGoldenTests(_ run: TestRun) async {
    run.section("Golden runtime transcripts")
    // Every clock the cards wear is in UTC here, so the transcripts are the same on any machine.
    NSTimeZone.default = TimeZone(identifier: "UTC")!
    let scenarios = [
        "runtime-cards-en", "runtime-cards-ru",
        "runtime-menu-en", "runtime-menu-ru",
        "runtime-banners-en", "runtime-banners-ru",
        "runtime-placement",
    ]
    for scenario in scenarios {
        await run.test(scenario) {
            let actual = scenario == "runtime-placement"
                ? try await placementScenario()
                : try await runtimeScenario(scenario)
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Golden", isDirectory: true)
                .appendingPathComponent(scenario + ".expected.jsonl")
            if ProcessInfo.processInfo.environment["UPDATE_GOLDEN_TRANSCRIPTS"] == "1" {
                try actual.write(to: source, options: .atomic)
                return
            }
            guard let expectedURL = Bundle.module.url(forResource: scenario + ".expected", withExtension: "jsonl", subdirectory: "Golden") else {
                throw TestFailure(message: "no golden file for \(scenario)", file: #filePath, line: #line)
            }
            try expectEqual(actual, try Data(contentsOf: expectedURL))
        }
    }
}
