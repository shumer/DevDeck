import DevDeckCore
import DevDeckEngine
import DevDeckLocalization
import Foundation
import ProjectKit
import TestHarness

private enum GoldenFixture {
    static let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Golden", isDirectory: true)

    static let scenarios = ["initial-data-en", "ready-to-blocked-ru", "project-start-stop-en"]

    static let ready = response(checkState: "SUCCESS")
    static let blocked = response(checkState: "FAILURE")

    static func response(checkState: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {"data":{"viewer":{"login":"demo"},"mine":{"issueCount":1,"nodes":[
                  {"id":"item","number":123,"title":"DEMO-123 - Sample change","url":"https://example.invalid/123","updatedAt":"2026-10-08T12:00:00Z","repository":{"nameWithOwner":"demo/sample","owner":{"login":"demo"}},"reviewDecision":"APPROVED","commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"\(checkState)"}}}]}}
                ]},"reviewing":{"issueCount":0,"nodes":[]}}}
                """.utf8))
    }

    static func responses(for scenario: String) -> [HTTPResponse] {
        scenario == "ready-to-blocked-ru" ? [ready, blocked] : [ready]
    }

    static func projectResponses(for scenario: String) -> [Result<HTTPResponse, Error>] {
        let stopped: Result<HTTPResponse, Error> = .failure(APIError.transport("offline fixture"))
        if scenario == "project-start-stop-en" {
            return [stopped, stopped, .success(HTTPResponse(statusCode: 200)), stopped]
        }
        return [stopped]
    }

    static func resource(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Golden")
        else {
            throw TestFailure(message: "Golden resource is missing", file: #filePath, line: #line)
        }
        return url
    }
}

private func goldenConfiguration(language: String) throws -> EngineConfiguration {
    try JSONDecoder().decode(
        EngineConfiguration.self,
        from: Data(
            """
            {"language":"\(language)","github":{"account":"github","label":"Work"},"projects":[
            {"id":"demo","title":"Demo","distribution":"Demo","path":"/demo","startCommand":"demo","healthURL":"http://example.invalid/health","siteURL":"http://example.invalid/site"}]}
            """.utf8))
}

private func replayGoldenScenario(_ scenario: String) async throws -> Data {
    let inputURL = try GoldenFixture.resource(scenario + ".input")
    let lines = try String(contentsOf: inputURL, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    guard let first = lines.first else {
        throw TestFailure(message: "Golden scenario is empty", file: #filePath, line: #line)
    }
    let start = try EngineIntent.decode(Data(first.utf8))
    guard let language = start.language else {
        throw TestFailure(message: "Golden scenario has no language", file: #filePath, line: #line)
    }
    let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 1_760_000_000))
    let events = Events()
    let runtimeFiles = ProjectRuntimeFiles(directory: URL(fileURLWithPath: "/invalid/demo"))
    let projectService = LocalProjectService(
        project: LocalProject(
            id: "demo", title: "Demo", folder: "/demo", startCommand: "start-demo",
            stopCommand: "stop-demo", holdsProcess: false, healthURL: "http://example.invalid/health",
            localSiteURL: "http://example.invalid/site"),
        runner: StubCommandRunner([
            ("start-demo", CommandResult(exitCode: 0, standardOutput: "", standardError: "")),
            ("stop-demo", CommandResult(exitCode: 0, standardOutput: "", standardError: "")),
        ]),
        httpClient: FakeHTTPClient(GoldenFixture.projectResponses(for: scenario)),
        clock: clock,
        sleeper: AdvancingSleeper(clock: clock),
        files: runtimeFiles)
    let engine = DevDeckEngine(
        configuration: try goldenConfiguration(language: language),
        runner: StubCommandRunner([]),
        projectServices: ["demo": projectService],
        http: FakeHTTPClient(GoldenFixture.responses(for: scenario).map { .success($0) }),
        clock: clock,
        runtimeFiles: runtimeFiles,
        timeZone: TimeZone(secondsFromGMT: 0)!,
        localizationRoot: LocalizationResources.root,
        pollingEnabled: false,
        output: { events.append($0) })
    for line in lines {
        await engine.handle(try EngineIntent.decode(Data(line.utf8)))
        await engine.waitForSingleRefresh()
    }
    await engine.shutdown()
    return events.items.reduce(into: Data()) { $0.append($1) }
}

func runGoldenTranscriptTests(_ run: TestRun) async {
    run.section("Golden engine transcripts")
    for scenario in GoldenFixture.scenarios {
        await run.test(scenario) {
            let actual = try await replayGoldenScenario(scenario)
            if ProcessInfo.processInfo.environment["UPDATE_GOLDEN_TRANSCRIPTS"] == "1" {
                let expectedURL = GoldenFixture.sourceDirectory.appendingPathComponent(
                    scenario + ".expected.jsonl")
                try actual.write(to: expectedURL, options: .atomic)
                return
            }
            let expectedURL = try GoldenFixture.resource(scenario + ".expected")
            let expected = try Data(contentsOf: expectedURL)
            try expectEqual(actual, expected)
        }
    }
}
