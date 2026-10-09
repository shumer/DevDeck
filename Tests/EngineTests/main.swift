import DevDeckCore
import DevDeckEngine
import DevDeckLocalization
import Foundation
import ProjectKit
import TestHarness

final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [Data] = []
    func append(_ item: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(item)
    }
    var items: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

struct FixtureHTTP: HTTPClient {
    let unauthorized: Bool
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.path == "/graphql" {
            if unauthorized { return HTTPResponse(statusCode: 401) }
            return HTTPResponse(
                statusCode: 200,
                body: Data(
                    """
                    {"data":{"viewer":{"login":"demo"},"mine":{"issueCount":2,"nodes":[
                      {"id":"ready","number":123,"title":"PROJ-123 - Ready item","url":"https://example.invalid/123","updatedAt":"2026-10-08T12:00:00Z","repository":{"nameWithOwner":"demo/sample","owner":{"login":"demo"}},"reviewDecision":"APPROVED","commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}},
                      {"id":"blocked","number":124,"title":"PROJ-124 - Fix item","url":"https://example.invalid/124","updatedAt":"2026-10-07T12:00:00Z","repository":{"nameWithOwner":"demo/sample","owner":{"login":"demo"}},"reviewDecision":"APPROVED","commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}}
                    ]},"reviewing":{"issueCount":0,"nodes":[]}}}
                    """.utf8))
        }
        return HTTPResponse(statusCode: 200)
    }
}

let run = TestRun()
run.section("Engine protocol and model checks")

await run.test("protocol rejects an incompatible version and oversized input") {
    do {
        _ = try EngineIntent.decode(
            Data("{\"protocolVersion\":1,\"id\":\"1\",\"intent\":\"session.start\"}".utf8))
        throw TestFailure(message: "Expected invalid version", file: #filePath, line: #line)
    } catch EngineProtocolError.invalidIntent {}
    do {
        _ = try EngineIntent.decode(Data(repeating: 32, count: 1_048_577))
        throw TestFailure(message: "Expected size limit", file: #filePath, line: #line)
    } catch EngineProtocolError.oversizedMessage {}
}

#if os(Windows)
await run.test("project liveness reads PID and probes it in one command") {
    let runner = StubCommandRunner([
        ("read -r pid", CommandResult(exitCode: 0, standardOutput: "42", standardError: ""))
    ])
    let project = LocalProject(
        id: "demo", title: "Demo", folder: "/demo", startCommand: "demo", holdsProcess: true)
    let status = await LocalProjectService(project: project, runner: runner).status()
    try expect(status.isRunning)
    try expectEqual(status.pid, 42)
    let commands = await runner.commands
    try expectEqual(commands.count, 1)
    try expect(commands[0].contains("kill -0"))
    try expect(commands[0].contains("boot_id"))
}
#endif

for language in ["en", "ru"] {
    await run.test("\(language) events are translated, ordered and never echo credentials") {
        let config = try JSONDecoder().decode(
            EngineConfiguration.self,
            from: Data(
                """
                {"language":"\(language)","github":{"account":"github","label":"Work"},"project":{"id":"demo","title":"Demo","distribution":"demo","path":"/demo","startCommand":"demo","healthURL":"http://example.invalid/"}}
                """.utf8))
        let events = Events()
        let runner = StubCommandRunner([])
        let engine = DevDeckEngine(
            configuration: config, runner: runner, http: FixtureHTTP(unauthorized: true),
            clock: MutableDateProvider(),
            runtimeFiles: ProjectRuntimeFiles(directory: URL(fileURLWithPath: "/invalid/demo")),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            localizationRoot: LocalizationResources.root,
            pollingEnabled: false, output: { events.append($0) })
        let lines = [
            "{\"protocolVersion\":2,\"id\":\"1\",\"intent\":\"session.start\",\"language\":\"\(language)\",\"displays\":[{\"id\":\"demo\",\"visibleFrame\":[100,200,1920,1040],\"scale\":1.5}]}",
            "{\"protocolVersion\":2,\"id\":\"bootstrap\",\"intent\":\"shell.bootstrap\"}",
            "{\"protocolVersion\":2,\"id\":\"2\",\"intent\":\"credentials.set\",\"account\":\"github\",\"token\":\"fixture-secret\"}",
            "{\"protocolVersion\":2,\"id\":\"3\",\"intent\":\"card.measured\",\"card\":\"github.pullRequests\",\"size\":[352,216]}",
            "{\"protocolVersion\":2,\"id\":\"4\",\"intent\":\"card.measured\",\"card\":\"project.demo\",\"size\":[352,180]}",
        ]
        for line in lines { await engine.handle(try EngineIntent.decode(Data(line.utf8))) }
        await engine.waitForSingleRefresh()
        let data = events.items
        try expect(!data.isEmpty)
        let text = data.map { String(decoding: $0, as: UTF8.self) }.joined()
        try expect(!text.contains("fixture-secret"))
        try expect(text.contains(L("error.unauthorized")))
        try expect(!text.contains("error.unauthorized"))
        try expect(!text.contains("card.chrome.pulls"))
        try expect(L("card.chrome.pulls") != "card.chrome.pulls")
        let objects = try data.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
        let revisions = objects.map { $0["revision"] as! Int }
        try expectEqual(revisions, Array(1...revisions.count))
        let shell = objects.first { $0["event"] as? String == "shell.ready" }!["shell"] as! [String: Any]
        try expectEqual(shell["credentialAccounts"] as! [String], ["github"])
        try expectEqual(shell["quitLabel"] as! String, L("menu.quit"))
        let failureCards = shell["failureCards"] as! [[String: Any]]
        try expectEqual(failureCards.count, 2)
        try expect(text.contains(L("engine.unavailable")))
        let layouts = objects.filter { $0["event"] as? String == "layout.updated" }
        let placements = layouts.last!["cards"] as! [[String: Any]]
        try expectEqual(placements.count, 2)
        try expectEqual(placements[0]["topLeft"] as! [Double], [124, 224])
        try expectEqual(placements[1]["topLeft"] as! [Double], [124, 452])
        await engine.shutdown()
    }
}

await run.test("plural forms retain English and Russian count rules") {
    Strings.use(.english, lookingIn: LocalizationResources.root)
    try expectEqual(LN("card.repos", 1), "1 repo")
    try expectEqual(LN("card.repos", 2), "2 repos")
    Strings.use(.russian, lookingIn: LocalizationResources.root)
    try expectEqual(LN("card.repos", 1), "1 репозиторий")
    try expectEqual(LN("card.repos", 2), "2 репозитория")
    try expectEqual(LN("card.repos", 5), "5 репозиториев")
    try expectEqual(LN("card.repos", 11), "11 репозиториев")
    try expectEqual(LN("card.repos", 21), "21 репозиторий")
}

await run.test("PR model keeps blocked rows first and separates ticket text") {
    let config = try JSONDecoder().decode(
        EngineConfiguration.self,
        from: Data(
            """
            {"language":"en","github":{"account":"github","label":"Work"},"project":{"id":"demo","title":"Demo","distribution":"demo","path":"/demo","startCommand":"demo","healthURL":"http://example.invalid/"}}
            """.utf8))
    let events = Events()
    let engine = DevDeckEngine(
        configuration: config, runner: StubCommandRunner([]), http: FixtureHTTP(unauthorized: false),
        clock: MutableDateProvider(),
        runtimeFiles: ProjectRuntimeFiles(directory: URL(fileURLWithPath: "/invalid/demo")),
        timeZone: TimeZone(secondsFromGMT: 0)!,
        localizationRoot: LocalizationResources.root,
        pollingEnabled: false, output: { events.append($0) })
    await engine.handle(
        try EngineIntent.decode(
            Data(
                """
                {"protocolVersion":2,"id":"1","intent":"session.start","language":"en","displays":[{"id":"demo","visibleFrame":[0,0,1920,1040],"scale":1}]}
                """.utf8)))
    await engine.handle(
        try EngineIntent.decode(
            Data(
                """
                {"protocolVersion":2,"id":"2","intent":"credentials.set","account":"github","token":"fixture"}
                """.utf8)))
    await engine.waitForSingleRefresh()
    let objects = try events.items.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
    let cards = objects.compactMap { $0["card"] as? [String: Any] }.filter {
        $0["id"] as? String == "github.pullRequests"
    }
    let rows = cards.last!["rows"] as! [[String: Any]]
    try expectEqual(rows.count, 2)
    try expectEqual(rows[0]["title"] as! String, "Fix item")
    try expectEqual(rows[0]["trailing"] as! String, "CF")
    try expectEqual(rows[1]["trailing"] as! String, "AP")
    let hero = cards.last!["hero"] as! [String: Any]
    try expectEqual(hero["number"] as! String, "2")
    let badge = hero["badge"] as! [String: Any]
    try expectEqual(badge["text"] as! String, L("card.pill.blocked", 1))
    await engine.shutdown()
}

await run.test("typed cards round trip with explicit local time and separate site URL") {
    let configuration = try JSONDecoder().decode(
        EngineConfiguration.self,
        from: Data(
            """
            {"language":"en","github":{"account":"github","label":"Work"},"project":{"id":"demo","title":"Demo","distribution":"demo","path":"/demo","startCommand":"demo","healthURL":"http://example.invalid/health","siteURL":"http://example.invalid/site"}}
            """.utf8))
    let events = Events()
    let engine = DevDeckEngine(
        configuration: configuration,
        runner: StubCommandRunner([]),
        http: FixtureHTTP(unauthorized: false),
        clock: MutableDateProvider(now: Date(timeIntervalSince1970: 0)),
        runtimeFiles: ProjectRuntimeFiles(directory: URL(fileURLWithPath: "/invalid/demo")),
        timeZone: TimeZone(secondsFromGMT: 19_800)!,
        localizationRoot: LocalizationResources.root,
        pollingEnabled: false,
        output: { events.append($0) }
    )
    await engine.handle(
        try EngineIntent.decode(
            Data(
                """
                {"protocolVersion":2,"id":"session","intent":"session.start","language":"en","displays":[{"id":"demo","visibleFrame":[0,0,1920,1040],"scale":1}]}
                """.utf8)))
    await engine.handle(
        try EngineIntent.decode(
            Data(
                """
                {"protocolVersion":2,"id":"credentials","intent":"credentials.set","account":"github","token":"fixture"}
                """.utf8)))
    await engine.waitForSingleRefresh()
    await engine.handle(
        try EngineIntent.decode(
            Data(
                """
                {"protocolVersion":2,"id":"site","intent":"card.invoke","card":"project.demo","action":"site"}
                """.utf8)))
    let decoded = try events.items.map { try JSONDecoder().decode(EngineEvent.self, from: $0) }
    let listCards = decoded.compactMap { event -> ListCardModel? in
        guard case .list(let card) = event.card else { return nil }
        return card
    }
    let projectCards = decoded.compactMap { event -> ProjectCardModel? in
        guard case .project(let card) = event.card else { return nil }
        return card
    }
    try expectEqual(listCards.last?.timeText, "05:30:00")
    try expectEqual(projectCards.last?.timeText, "05:30:00")
    try expectEqual(listCards.last?.rows.first?.trailing, "CF")
    try expectEqual(decoded.last?.effect?.url, "http://example.invalid/site")
    try expectEqual(configuration.project.model.healthCheckURL?.path, "/health")
    let encoded = try JSONEncoder().encode(decoded.last!)
    let roundTrip = try JSONDecoder().decode(EngineEvent.self, from: encoded)
    try expectEqual(roundTrip.effect?.url, "http://example.invalid/site")
    for card in decoded.compactMap(\.card) {
        let encodedCard = try JSONEncoder().encode(card)
        _ = try JSONDecoder().decode(CardModel.self, from: encodedCard)
    }
    await engine.shutdown()
}
await run.test("project paths select execution location without a UI choice") {
    func project(_ path: String, distribution: String? = nil) throws -> EngineConfiguration.Project {
        let object: [String: String] = [
            "id": "demo", "title": "Demo", "path": path,
            "startCommand": "demo", "healthURL": "http://example.invalid/",
            "distribution": distribution ?? "",
        ]
        return try JSONDecoder().decode(
            EngineConfiguration.Project.self, from: JSONSerialization.data(withJSONObject: object))
    }
    try expectEqual(try project("C:\\demo folder").executionLocation, .windows(path: "C:\\demo folder"))
    try expectEqual(
        try project("\\\\wsl.localhost\\Ubuntu-24.04\\home\\demo").executionLocation,
        .wsl(distribution: "Ubuntu-24.04", path: "/home/demo"))
    try expectEqual(
        try project("\\\\wsl$\\Demo\\workspace").executionLocation,
        .wsl(distribution: "Demo", path: "/workspace"))
    try expectEqual(
        try project("/demo", distribution: "Demo").executionLocation,
        .wsl(distribution: "Demo", path: "/demo"))
    try expect(try project("/demo").executionLocation == nil)
    try expect(try project("relative").executionLocation == nil)
}

await run.test("multiple project cards retain independent state and ordered placement") {
    let configuration = try JSONDecoder().decode(
        EngineConfiguration.self,
        from: Data(
            """
            {"language":"en","github":{"account":"github","label":"Work"},"projects":[
            {"id":"demo","title":"Demo","distribution":"Demo","path":"/demo","startCommand":"demo","healthURL":"http://example.invalid/"},
            {"id":"demo-win","title":"Demo Windows","path":"C:\\\\demo","startCommand":"demo","healthURL":"http://example.invalid/"}]}
            """.utf8))
    let events = Events()
    let engine = DevDeckEngine(
        configuration: configuration, runner: StubCommandRunner([]), http: FixtureHTTP(unauthorized: false),
        clock: MutableDateProvider(),
        runtimeFiles: ProjectRuntimeFiles(directory: URL(fileURLWithPath: "/invalid/demo")),
        timeZone: TimeZone(secondsFromGMT: 0)!, localizationRoot: LocalizationResources.root,
        pollingEnabled: false,
        output: { events.append($0) })
    await engine.handle(
        try EngineIntent.decode(
            Data(
                """
                {"protocolVersion":2,"id":"1","intent":"session.start","language":"en","displays":[{"id":"demo","visibleFrame":[0,0,1920,1040],"scale":1}]}
                """.utf8)))
    await engine.waitForSingleRefresh()
    for card in ["github.pullRequests", "project.demo", "project.demo-win"] {
        await engine.handle(
            try EngineIntent.decode(
                Data(
                    """
                    {"protocolVersion":2,"id":"2","intent":"card.measured","card":"\(card)","size":[352,180]}
                    """.utf8)))
    }
    let decoded = try events.items.map { try JSONDecoder().decode(EngineEvent.self, from: $0) }
    try expectEqual(
        decoded.last?.cards?.map(\.card), ["github.pullRequests", "project.demo", "project.demo-win"])
    let projectCards = decoded.compactMap(\.card).compactMap { model -> ProjectCardModel? in
        if case .project(let project) = model { return project }
        return nil
    }
    try expect(projectCards.contains { $0.id == "project.demo" && $0.hero.tone == "good" })
    try expect(projectCards.contains { $0.id == "project.demo-win" && $0.hero.tone == "good" })
    await engine.shutdown()
}
await runGoldenTranscriptTests(run)
await runRuntimeGoldenTests(run)
await runSessionGoldenTests(run)
run.finish()
