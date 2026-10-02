import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

private actor WorkerTestRunner: CommandRunning {
    private var commands: [String] = []
    let result: CommandResult
    init(_ output: String = "", exitCode: Int32 = 0) {
        result = CommandResult(exitCode: exitCode, standardOutput: output, standardError: "")
    }
    func run(_ command: String, in directory: URL, timeout: TimeInterval, isInteractive: Bool,
             onOutput: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        commands.append(command)
        return result
    }
    func recorded() -> [String] { commands }
}

func runWorkerTests(_ run: TestRun) async {
    run.section("WSL worker protocol")
    await run.test("log window payload keeps the newest 400 lines and optional full-file path") {
        let result = WorkerLogs(lines: (0..<500).map(String.init), source: "fixture", detail: nil, filePath: "/tmp/project/log.txt")
        try expect(result.lines.count == 400 && result.lines.first == "100" && result.lines.last == "499")
        let roundTrip = try JSONDecoder().decode(WorkerLogs.self, from: JSONEncoder().encode(result))
        try expect(roundTrip.filePath == "/tmp/project/log.txt")
    }
    await run.test("log payload limits UTF8 bytes while retaining newest complete lines") {
        let line = String(repeating: "Ж", count: 1000)
        let result = WorkerLogs(lines: Array(repeating: line, count: 400), source: nil, detail: nil)
        try expect(result.lines.count == 131 && result.lines.reduce(0) { $0 + $1.utf8.count } <= LogWindowLimit.bytes)
    }
    let encoder = JSONEncoder()
    let service = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner())

    await run.test("settings-only project check advertises and exports the shared answer without attention") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = WorkerTestRunner()
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let project = WorkerProject(id: "project.settings-check", distribution: "Ubuntu-24.04", kind: .local,
            path: directory.path, startCommand: "bun run dev")
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "check", operation: "project.check", project: project)))
        try expectNil(response.error)
        try expectEqual(response.status?.state, "stopped")
        try expectEqual(response.status?.checkSummary?.detail, L("project.noHealthURL"))
        try expect(response.status?.checkedAt != nil)
        try expectNil(response.attention)
        let hello = await worker.handle(try encoder.encode(WorkerRequest(id: "hello", operation: "hello")))
        try expect(hello.capabilities?.contains("project.check") == true)
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("draft settings check cannot seed a running state into the real stopped card") {
        let saved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let draft = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for directory in [saved, draft] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        defer { for directory in [saved, draft] { try? FileManager.default.removeItem(at: directory) } }
        let http = FakeHTTPClient([.failure(APIError.transport("offline saved fixture")), .success(.status(200)), .failure(APIError.transport("offline saved fixture"))])
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner(), arcHTTPClient: http)
        let project = WorkerProject(id: "arc.project.settings-isolation", distribution: "Ubuntu-24.04", kind: .arc,
            path: saved.path, arc: WorkerArcConfiguration(localURL: "http://localhost:8112"))
        let edited = WorkerProject(id: project.id, distribution: project.distribution, kind: .arc,
            path: draft.path, arc: WorkerArcConfiguration(localURL: "http://localhost:9111"))
        let initial = await worker.handle(try encoder.encode(WorkerRequest(id: "saved-before", operation: "project.status", project: project)))
        try expectEqual(initial.status?.state, "stopped")
        let checked = await worker.handle(try encoder.encode(WorkerRequest(id: "draft", operation: "project.check", project: edited)))
        try expectNil(checked.error)
        try expectEqual(checked.status?.state, "running")
        try expectNil(checked.attention)
        let actual = await worker.handle(try encoder.encode(WorkerRequest(id: "saved-after", operation: "project.status", project: project)))
        try expectEqual(actual.status?.state, "stopped")
        try expectEqual(actual.status?.siteURL, "http://localhost:8112")
        try expect(actual.attention?.alerts.isEmpty == true)
        try expectEqual(await http.request(at: 1)?.url.absoluteString, "http://localhost:9111/release")
        try expectEqual(await http.request(at: 2)?.url.absoluteString, "http://localhost:8112/release")
    }
    await run.test("repeated bad draft checks cannot advance card polling or create a stop episode") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([.success(.status(200)), .failure(APIError.transport("draft fixture")),
            .failure(APIError.transport("draft fixture")), .failure(APIError.transport("real hiccup fixture"))])
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner(), arcHTTPClient: http)
        let project = WorkerProject(id: "arc.project.settings-poll-isolation", distribution: "Ubuntu-24.04", kind: .arc,
            path: directory.path, arc: WorkerArcConfiguration(localURL: "http://localhost:8112"))
        let edited = WorkerProject(id: project.id, distribution: project.distribution, kind: .arc,
            path: directory.path, arc: WorkerArcConfiguration(localURL: "http://localhost:9111"))
        let up = await worker.handle(try encoder.encode(WorkerRequest(id: "up", operation: "project.status", project: project)))
        try expectEqual(up.status?.state, "running")
        for index in 0..<2 {
            let checked = await worker.handle(try encoder.encode(WorkerRequest(id: "draft-\(index)", operation: "project.check", project: edited)))
            try expectNil(checked.error)
            try expectEqual(checked.status?.state, "stopped")
            try expectEqual(checked.status?.checkSummary?.state, L("check.stopped"))
            try expectNil(checked.attention)
        }
        let actual = await worker.handle(try encoder.encode(WorkerRequest(id: "actual-hiccup", operation: "project.status", project: project)))
        try expectEqual(actual.status?.state, "running")
        try expectEqual(actual.status?.siteURL, "http://localhost:8112")
        try expect(actual.attention?.alerts.isEmpty == true)
    }

    await run.test("settings check summary bounds Unicode and removes unsafe controls") {
        let answer = WorkerCheckSummary(CheckSummary(tone: .good,
            state: "\u{0}\n" + String(repeating: "😀", count: 200),
            detail: "\t\n" + String(repeating: "Ж", count: 10_000) + "\u{0}"))
        try expectEqual(answer.tone, "good")
        try expectEqual(answer.state, String(repeating: "😀", count: 128))
        try expect(answer.detail.utf8.count <= 16_384)
        try expectEqual(answer.detail, "\t\n" + String(repeating: "Ж", count: 8_191))
        let decoded = try JSONDecoder().decode(WorkerCheckSummary.self, from: encoder.encode(answer))
        try expectEqual(decoded, answer)
    }
    await run.test("optional settings check payload remains protocol1 compatible and bounds its timestamp") {
        let legacy = try JSONDecoder().decode(WorkerStatus.self, from: Data(#"{"projectID":"legacy","state":"stopped"}"#.utf8))
        try expectNil(legacy.checkSummary)
        try expectNil(legacy.checkedAt)
        let answer = WorkerCheckSummary(CheckSummary(tone: .busy, state: L("check.starting"), detail: L("check.starting.detail")))
        let status = WorkerStatus(projectID: "fixture", state: "starting", checkSummary: answer, checkedAt: 1_800_000_000)
        let decoded = try JSONDecoder().decode(WorkerStatus.self, from: encoder.encode(status))
        try expectEqual(decoded.checkSummary, answer)
        try expectEqual(decoded.checkedAt, 1_800_000_000)
        for invalid in [-1, Double.infinity, Double.nan, 253_402_300_800] {
            try expectNil(WorkerStatus(projectID: "fixture", state: "stopped", checkedAt: invalid).checkedAt)
        }
    }

    await run.test("generic Detect reuses ProjectProbe without executing commands") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"packageManager":"bun@1.2.0","scripts":{"dev":"next dev --port 4111"},"dependencies":{"next":"15"}}"#.utf8)
            .write(to: directory.appendingPathComponent("package.json"))
        let runner = WorkerTestRunner()
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let project = WorkerProject(id: "project.detect", distribution: "Ubuntu-24.04", kind: .local, path: directory.path)
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "detect", operation: "project.probe", project: project)))
        try expectNil(response.error)
        let object = try JSONSerialization.jsonObject(with: encoder.encode(response)) as! [String: Any]
        let suggestion = object["suggestion"] as? [String: Any]
        try expectEqual(suggestion?["startCommand"] as? String, "bun run dev")
        try expectEqual(suggestion?["subtitle"] as? String, "bun · next")
        try expectEqual(suggestion?["healthURL"] as? String, "http://localhost:4111")
        try expectEqual(await runner.recorded(), [])
    }

    await run.test("generic worker Detect retains shared Compose dev Make start precedence") {
        let runner = WorkerTestRunner()
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        for (files, command) in [
            (["compose.yaml": "services: {}", "package.json": #"{"scripts":{"dev":"vite"}}"#], "docker compose up -d"),
            (["package.json": #"{"scripts":{"dev":"vite","start":"node server.js"}}"#, "Makefile": "up:\n\ttrue\n"], "npm run dev"),
            (["package.json": #"{"scripts":{"start":"node server.js"}}"#, "Makefile": "dev:\n\ttrue\n"], "make dev"),
            (["package.json": #"{"scripts":{"start":"node server.js"}}"#], "npm start")
        ] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            for (name, text) in files { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
            let project = WorkerProject(id: "project.fixture", distribution: "Ubuntu-24.04", kind: .local, path: directory.path)
            let response = await worker.handle(try encoder.encode(WorkerRequest(id: "probe", operation: "project.probe", project: project)))
            try expectNil(response.error)
            try expectEqual(response.suggestion?.startCommand, command)
            try expectNil(response.attention)
        }
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("generic worker Detect reads workspace frontend port and nested Docker scripts") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("apps/web"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("apps/api"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, text) in [
            "package.json": #"{"packageManager":"bun@1","scripts":{"dev":"bun run db:up && turbo run dev","db:up":"docker compose up -d"},"workspaces":["apps/*"]}"#,
            "apps/web/package.json": #"{"scripts":{"dev":"next dev --port 4112"},"dependencies":{"next":"15"}}"#,
            "apps/api/package.json": #"{"scripts":{"dev":"nest start"},"dependencies":{"@nestjs/core":"11"}}"#,
            "apps/api/.env": "PORT=9111\n"
        ] { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner())
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "probe", operation: "project.probe",
            project: WorkerProject(id: "project.workspace", distribution: "Ubuntu-24.04", kind: .local, path: directory.path))))
        try expectNil(response.error)
        try expectEqual(response.suggestion?.subtitle, "bun · next + nest")
        try expectEqual(response.suggestion?.healthURL, "http://localhost:4112")
        try expectEqual(response.suggestion?.requiresDocker, true)
        try expectEqual(response.suggestion?.holdsProcess, true)
    }
    await run.test("generic worker Detect no-match and invalid requests execute nothing") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = WorkerTestRunner(); let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let project = WorkerProject(id: "project.empty", distribution: "Ubuntu-24.04", kind: .local, path: directory.path)
        let empty = await worker.handle(try encoder.encode(WorkerRequest(id: "empty", operation: "project.probe", project: project)))
        try expectNil(empty.error); try expectNil(empty.suggestion)
        for (candidate, code) in [
            (WorkerProject(id: "project.bad", distribution: "Debian", kind: .local, path: directory.path), "wrongDistribution"),
            (WorkerProject(id: "project.bad", distribution: "Ubuntu-24.04", kind: .local, path: "/tmp/../elsewhere"), "invalidProject"),
            (WorkerProject(id: "project.bad", distribution: "Ubuntu-24.04", kind: .ddev, path: directory.path), "invalidProject")
        ] {
            let result = await worker.handle(try encoder.encode(WorkerRequest(id: "bad", operation: "project.probe", project: candidate)))
            try expectEqual(result.error?.code, code)
        }
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("generic optional caption and open URL map through the original model with legacy fallback") {
        let legacy = try JSONDecoder().decode(WorkerProject.self, from: Data(#"{"id":"project.old","distribution":"Ubuntu-24.04","kind":"local","path":"/tmp/example","healthURL":"http://localhost:3000/health"}"#.utf8))
        try expectEqual(legacy.localModel().siteURL?.absoluteString, "http://localhost:3000/health")
        let project = WorkerProject(id: legacy.id, distribution: legacy.distribution, kind: .local, path: legacy.path,
            startCommand: "bun run dev", healthURL: legacy.healthURL, subtitle: "bun · next + nest", openURL: "http://localhost:4112/front")
        try expectEqual(project.localModel().siteURL?.absoluteString, "http://localhost:4112/front")
        try expectEqual(project.localModel().healthCheckURL?.absoluteString, legacy.healthURL)
        try expectEqual(project.localModel().subtitle, "bun · next + nest")
        let decoded = try JSONDecoder().decode(WorkerProject.self, from: encoder.encode(project))
        try expectEqual(decoded, project)
    }

    await run.test("generic production status exports separate frontend and chosen caption without a health probe") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = WorkerProject(id: "project.frontend-fixture", distribution: "Ubuntu-24.04", kind: .local, path: directory.path,
            startCommand: "bun run dev", subtitle: "bun · next + nest", openURL: "http://localhost:4112/front")
        let response = await WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner()).handle(
            try encoder.encode(WorkerRequest(id: "status", operation: "project.status", project: project)))
        try expectNil(response.error)
        try expectEqual(response.status?.siteURL, "http://localhost:4112/front")
        try expectEqual(response.status?.framework, "bun · next + nest")
    }
    await run.test("generic production status preserves the original settings check answer") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = WorkerTestRunner()
        let project = WorkerProject(id: "project.check-fixture", distribution: "Ubuntu-24.04", kind: .local,
            path: directory.path, startCommand: "bun run dev")
        let response = await WorkerService(distribution: "Ubuntu-24.04", runner: runner).handle(
            try encoder.encode(WorkerRequest(id: "check", operation: "project.status", project: project)))
        try expectNil(response.error)
        let json = try JSONSerialization.jsonObject(with: encoder.encode(response)) as! [String: Any]
        let status = json["status"] as? [String: Any]
        let answer = status?["checkSummary"] as? [String: Any]
        try expectEqual(answer?["tone"] as? String, "idle")
        try expectEqual(answer?["state"] as? String, L("check.stopped"))
        try expectEqual(answer?["detail"] as? String, L("project.noHealthURL"))
        try expect((status?["checkedAt"] as? Double).map { $0.isFinite && $0 > 0 } == true)
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("Arc production check retains the exact failed health answer and endpoint") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([.success(.status(503))])
        let project = WorkerProject(id: "arc.project.check-fixture", distribution: "Ubuntu-24.04", kind: .arc,
            path: directory.path, arc: WorkerArcConfiguration(localURL: "http://localhost:8112/front?_website=news", healthPath: "/health"))
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner(), arcHTTPClient: http)
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "check", operation: "project.status", project: project)))
        try expectNil(response.error)
        let json = try JSONSerialization.jsonObject(with: encoder.encode(response)) as! [String: Any]
        let status = json["status"] as? [String: Any]
        let answer = status?["checkSummary"] as? [String: Any]
        try expectEqual(answer?["tone"] as? String, "idle")
        try expectEqual(answer?["state"] as? String, L("check.stopped"))
        try expectEqual(answer?["detail"] as? String, L("project.health.answered", 503))
        try expect((status?["checkedAt"] as? Double).map { $0.isFinite && $0 > 0 } == true)
        try expectEqual(await http.request(at: 0)?.url.absoluteString, "http://localhost:8112/health")
    }
    await run.test("new Arc address receives a fresh check answer while card polling remains settled") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([.success(.json("{\"version\":\"1.0\"}")), .success(.status(503))])
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner(), arcHTTPClient: http)
        let before = WorkerProject(id: "arc.project.changed-address", distribution: "Ubuntu-24.04", kind: .arc,
            path: directory.path, arc: WorkerArcConfiguration(localURL: "http://localhost:8112", healthPath: "/health"))
        let after = WorkerProject(id: before.id, distribution: before.distribution, kind: .arc,
            path: directory.path, arc: WorkerArcConfiguration(localURL: "http://localhost:9111", healthPath: "/health"))
        let first = await worker.handle(try encoder.encode(WorkerRequest(id: "before", operation: "project.status", project: before)))
        try expectEqual(first.status?.state, "running")
        let second = await worker.handle(try encoder.encode(WorkerRequest(id: "after", operation: "project.status", project: after)))
        try expectEqual(second.status?.state, "running")
        let json = try JSONSerialization.jsonObject(with: encoder.encode(second)) as! [String: Any]
        let answer = (json["status"] as? [String: Any])?["checkSummary"] as? [String: Any]
        try expectEqual(answer?["state"] as? String, L("check.stopped"))
        try expectEqual(answer?["detail"] as? String, L("project.health.answered", 503))
        try expectEqual(await http.request(at: 1)?.url.absoluteString, "http://localhost:9111/health")
    }
    await run.test("generic invalid new metadata is rejected before probing files or commands") {
        let runner = WorkerTestRunner(); let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        for project in [
            WorkerProject(id: "project.bad", distribution: "Ubuntu-24.04", kind: .local, path: "/tmp/example", subtitle: "caption\ninvalid"),
            WorkerProject(id: "project.bad", distribution: "Ubuntu-24.04", kind: .local, path: "/tmp/example", openURL: "https://user:password@example.com"),
            WorkerProject(id: "project.bad", distribution: "Ubuntu-24.04", kind: .local, path: "/tmp/example", openURL: "file:///tmp/private"),
            WorkerProject(id: "project.bad", distribution: "Ubuntu-24.04", kind: .local, path: "/tmp/example", openURL: "http://localhost/invalid\npath"),
            WorkerProject(id: "project.bad", distribution: "Ubuntu-24.04", kind: .local, path: "/tmp/example", openURL: "http://localhost/" + String(repeating: "Ж", count: 1024))
        ] {
            let result = await worker.handle(try encoder.encode(WorkerRequest(id: "bad", operation: "project.probe", project: project)))
            try expectEqual(result.error?.code, "invalidProject")
        }
        try expectEqual(await runner.recorded(), [])
    }

    await run.test("organisation-only Arc status is unavailable locally without touching WSL commands") {
        let runner = WorkerTestRunner()
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let request: [String: Any] = ["protocolVersion": 1, "id": "arc-hosted", "operation": "project.status",
            "project": ["id": "arc.project.hosted", "distribution": "Ubuntu-24.04", "kind": "arc", "path": "",
                        "arc": ["organization": "sandbox.example", "site": "news", "localURL": "", "healthPath": "/release"]]]
        let response = await worker.handle(try JSONSerialization.data(withJSONObject: request))
        try expectNil(response.error)
        try expectEqual(response.status?.state, "unavailable")
        let json = try JSONSerialization.jsonObject(with: encoder.encode(response)) as! [String: Any]
        let answer = (json["status"] as? [String: Any])?["checkSummary"] as? [String: Any]
        try expectEqual(answer?["state"] as? String, L("project.notConfigured"))
        try expectEqual(answer?["detail"] as? String, L("project.notConfigured.detail"))
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("Arc production status preserves configured origin query and exports the shared local editor") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([.failure(APIError.transport("offline fixture"))])
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner(), arcHTTPClient: http)
        let project = WorkerProject(id: "arc.project.fixture", distribution: "Ubuntu-24.04", kind: .arc, path: directory.path,
            startCommand: "npm run owned-start", stopCommand: "npm run owned-stop",
            arc: WorkerArcConfiguration(organization: "sandbox.example", site: "news", localURL: "http://localhost:8112/front?_website=news", healthPath: "/health"))
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "arc-options", operation: "project.status", project: project)))
        try expectNil(response.error)
        try expectEqual(response.status?.siteURL, "http://localhost:8112/front?_website=news")
        try expectEqual(response.status?.localEditorURL, "http://localhost:8112/pagebuilder/experiences/_default/pages/")
        try expectEqual(await http.request(at: 0)?.url.absoluteString, "http://localhost:8112/health")
        try expectEqual(project.arcModel.startCommand, "npm run owned-start")
        try expectEqual(project.arcModel.stopCommand, "npm run owned-stop")
        try expectEqual(project.arcModel.organization, "sandbox.example")
        let decoded = try JSONDecoder().decode(WorkerResponse.self, from: encoder.encode(response))
        try expectEqual(decoded.status?.localEditorURL, response.status?.localEditorURL)
    }
    await run.test("Arc protocol defaults remain no-install Fusion and release health for legacy and partial options") {
        let legacy = WorkerProject(id: "arc.project.legacy", distribution: "Ubuntu-24.04", kind: .arc, path: "/tmp/example")
        try expectEqual(legacy.arcModel.startCommand, "npx --no-install fusion daemon")
        try expectEqual(legacy.arcModel.stopCommand, "npx --no-install fusion stop")
        try expectEqual(legacy.arcModel.healthPath, "/release")
        let partial = try JSONDecoder().decode(WorkerArcConfiguration.self, from: Data("{\"organization\":\"sandbox.example\"}".utf8))
        try expectEqual(partial.healthPath, "/release")
        try expectEqual(partial.localURL, "")
    }
    await run.test("custom Arc commands keep Docker port ownership preflight without requiring the default npx launcher") {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(".fusion"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("services: {}".utf8).write(to: directory.appendingPathComponent(".fusion/docker-compose.yml"))
        let runner = WorkerTestRunner(#"{"services":{}}"#)
        let result = await ArcStartPreflight(runner: runner).check(folder: directory, requiresLocalCLI: false)
        try expectNil(result)
        let commands = await runner.recorded()
        try expectEqual(commands.count, 2)
        try expect(commands[0].hasPrefix("docker compose") && commands[1].hasPrefix("docker ps"))
    }
    await run.test("Arc invalid options and folderless local actions never execute project commands") {
        let runner = WorkerTestRunner()
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        for options in [WorkerArcConfiguration(organization: "sandbox..example"), WorkerArcConfiguration(site: "unsafe/path"),
                        WorkerArcConfiguration(localURL: "file:///tmp/example"), WorkerArcConfiguration(healthPath: "//elsewhere")] {
            let project = WorkerProject(id: "arc.project.invalid", distribution: "Ubuntu-24.04", kind: .arc, path: "", arc: options)
            let response = await worker.handle(try encoder.encode(WorkerRequest(id: "invalid", operation: "project.status", project: project)))
            try expectEqual(response.error?.code, "invalidProject")
        }
        let project = WorkerProject(id: "arc.project.hosted", distribution: "Ubuntu-24.04", kind: .arc, path: "")
        for operation in ["project.start", "project.stop", "project.restart", "project.logs", "project.preflight"] {
            let response = await worker.handle(try encoder.encode(WorkerRequest(id: "missing-folder", operation: operation, project: project)))
            try expectEqual(response.error?.code, "missingFolder")
        }
        try expectEqual(await runner.recorded(), [])
    }

    await run.test("hello correlates a request and advertises only implemented operations") {
        let response = await service.handle(try encoder.encode(WorkerRequest(id: "hello-1", operation: "hello")))
        try expectEqual(response.id, "hello-1")
        try expectEqual(response.distribution, "Ubuntu-24.04")
        try expectEqual(response.capabilities, WorkerProtocol.capabilities)
        try expect(response.error == nil)
        let decoded = try JSONDecoder().decode(WorkerResponse.self, from: encoder.encode(response))
        try expectEqual(decoded.protocolVersion, 1)
    }
    await run.test("incompatible versions fail before dispatch") {
        let response = await service.handle(try encoder.encode(WorkerRequest(protocolVersion: 2, id: "version", operation: "hello")))
        try expectEqual(response.error?.code, "unsupportedVersion")
        try expectEqual(response.id, "version")
    }
    await run.test("malformed JSON and invalid IDs return bounded errors") {
        let response = await service.handle(Data("{\"token\":\"do-not-echo\"}".utf8))
        try expectEqual(response.error?.code, "invalidRequest")
        try expect(!String(decoding: encoder.encode(response), as: UTF8.self).contains("do-not-echo"))
        let badID = await service.handle(try encoder.encode(WorkerRequest(id: "x\n", operation: "hello")))
        try expectEqual(badID.error?.code, "invalidRequestID")
        try expect(badID.id == nil)
    }
    await run.test("unsupported destructive operations cannot affect a project") {
        let runner = WorkerTestRunner()
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "start", operation: "project.teardown")))
        try expectEqual(response.error?.code, "unsupportedOperation")
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("cross-distro projects fail before touching the command runner") {
        let runner = WorkerTestRunner()
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let project = WorkerProject(id: "arc.project.sport1", distribution: "Debian", kind: .arc, path: "/home/user/Sport1")
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "cross", operation: "project.status", project: project)))
        try expectEqual(response.error?.code, "wrongDistribution")
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("Linux paths preserve spaces and reject UNC, relative and control paths") {
        try expect(WorkerService.isLinuxPath("/home/user/project with spaces"))
        for path in ["C:\\project", "\\\\wsl.localhost\\Debian\\home", "~/project", "project", "//server/home", "/home/../etc", "/home/a\u{0}"] {
            try expect(!WorkerService.isLinuxPath(path), "accepted \(path)")
        }
    }
    await run.test("missing project and missing directory have distinct errors") {
        let missing = await service.handle(try encoder.encode(WorkerRequest(id: "missing", operation: "project.status")))
        try expectEqual(missing.error?.code, "missingProject")
        let project = WorkerProject(id: "ddev.project.missing", distribution: "Ubuntu-24.04", kind: .ddev,
                                    path: "/devdeck-test-directory-that-does-not-exist")
        let folder = await service.handle(try encoder.encode(WorkerRequest(id: "folder", operation: "project.status", project: project)))
        try expectEqual(folder.error?.code, "missingFolder")
    }
    await run.test("DDEV discovery uses the existing parser and preserves paused state") {
        let runner = WorkerTestRunner(#"{"raw":[{"name":"shop","approot":"/home/user/shop with spaces","status":"paused","type":"drupal11"}]}"#)
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "list", operation: "ddev.list")))
        try expectEqual(response.projects?.first?.path, "/home/user/shop with spaces")
        try expectEqual(response.projects?.first?.state, "paused")
        try expectEqual(response.projects?.first?.distribution, "Ubuntu-24.04")
        try expectEqual(await runner.recorded(), ["ddev list -j"])
    }
    await run.test("unavailable DDEV is different from an empty inventory") {
        let worker = WorkerService(distribution: "Debian", runner: WorkerTestRunner(exitCode: 127))
        let response = await worker.handle(try encoder.encode(WorkerRequest(id: "list", operation: "ddev.list")))
        try expectEqual(response.error?.code, "ddevUnavailable")
        try expect(response.projects == nil)
    }
    await run.test("DDEV worker exports checkout versions and reported tools across runtime states") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".ddev"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = WorkerProject(id: "ddev.project.metadata", distribution: "Ubuntu-24.04", kind: .ddev, path: folder.path)
        try #"{"packages":[{"name":"drupal/core","version":"11.4.4"}]}"#.write(to: folder.appendingPathComponent("composer.lock"), atomically: true, encoding: .utf8)
        for (php, database, version, expected) in [
            ("8.4", "mysql", "8.0", "php 8.4 · mysql 8.0"),
            ("8.3", "mariadb", "10.11", "php 8.3 · mariadb 10.11"),
            ("8.2", "postgres", "16", "php 8.2 · postgres 16")
        ] {
            try "name: metadata\ntype: drupal9\nphp_version: '\(php)'\ndatabase:\n  type: \(database)\n  version: \"\(version)\"\n".write(to: folder.appendingPathComponent(".ddev/config.yaml"), atomically: true, encoding: .utf8)
            for state in ["running", "stopped", "paused", "unknown"] {
                let entry: [String: Any] = ["name": "metadata", "approot": folder.path, "status": state, "type": "drupal9",
                                           "mailpit_https_url": "https://metadata.example.test:8026", "xhgui_https_url": "https://metadata.example.test:8144",
                                           "mutagen_enabled": true, "mutagen_status": "error"]
                let payload = try JSONSerialization.data(withJSONObject: ["raw": [entry]])
                let worker = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner(String(decoding: payload, as: UTF8.self)))
                let response = await worker.handle(try encoder.encode(WorkerRequest(id: "metadata", operation: "project.status", project: project)))
                try expectNil(response.error)
                let json = try JSONSerialization.jsonObject(with: encoder.encode(response)) as? [String: Any]
                let status = json?["status"] as? [String: Any]
                try expectEqual(status?["versionsLine"] as? String, expected)
                try expectNil(status?["checkSummary"])
                try expectNil(status?["checkedAt"])
                try expectEqual(response.status?.framework, "drupal 11.4.4")
                try expectEqual(response.status?.state, state)
                try expectEqual(response.status?.toolLinks?.map(\.label), ["Mailpit", "xhgui"])
                try expectEqual(response.status?.toolLinks?.last?.url, "https://metadata.example.test:8144")
                try expectEqual(response.status?.syncBroken, "mutagen")
            }
        }
    }
    await run.test("DDEV metadata tolerates unavailable CLI missing config and legacy versionless responses") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".ddev"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = WorkerProject(id: "ddev.project.metadata", distribution: "Ubuntu-24.04", kind: .ddev, path: folder.path)
        for (config, expected) in [("", nil), ("php_version: 8.4\n", "php 8.4"),
                                   ("database:\n  type: mariadb\n  version: 10.11\n", "mariadb 10.11"),
                                   ("database:\n  type: postgres\n", "postgres")] {
            let configURL = folder.appendingPathComponent(".ddev/config.yaml")
            if config.isEmpty { try? FileManager.default.removeItem(at: configURL) }
            else { try config.write(to: configURL, atomically: true, encoding: .utf8) }
            let worker = WorkerService(distribution: "Ubuntu-24.04", runner: WorkerTestRunner(exitCode: 127))
            let response = await worker.handle(try encoder.encode(WorkerRequest(id: "metadata", operation: "project.status", project: project)))
            try expectNil(response.error)
            try expectEqual(response.status?.versionsLine, expected)
            try expectEqual(response.status?.state, "unknown")
            try expectEqual(response.status?.toolLinks?.count, 0)
            let decoded = try JSONDecoder().decode(WorkerResponse.self, from: encoder.encode(response))
            try expectEqual(decoded.status?.versionsLine, expected)
        }
        let legacy = try JSONDecoder().decode(WorkerStatus.self, from: Data(#"{"projectID":"legacy","state":"stopped"}"#.utf8))
        try expectNil(legacy.versionsLine)
    }
    await run.test("DDEV statuses share one inventory per explicit refresh cycle") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-poll-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = WorkerTestRunner(#"{"raw":[]}"#)
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        for index in 0..<3 {
            let request: [String: Any] = ["protocolVersion": 1, "id": "poll-\(index)", "operation": "project.status", "refreshCycle": "fixture-cycle",
                                        "project": ["id": "ddev.project.\(index)", "distribution": "Ubuntu-24.04", "kind": "ddev", "path": folder.path]]
            let response = await worker.handle(try JSONSerialization.data(withJSONObject: request))
            try expectNil(response.error)
        }
        try expectEqual(await runner.recorded().filter { $0 == "ddev list -j" }.count, 1)
    }
    await run.test("DDEV cycle invalidates for a new poll manual refresh import or action") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-poll-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = WorkerTestRunner(#"{"raw":[]}"#)
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let project = WorkerProject(id: "ddev.project.poll", distribution: "Ubuntu-24.04", kind: .ddev, path: folder.path)
        for cycle in ["first", "first", "second", "second", nil, "second"] {
            let response = await worker.handle(try encoder.encode(WorkerRequest(id: UUID().uuidString, operation: "project.status", project: project, refreshCycle: cycle)))
            try expectNil(response.error)
        }
        try expectEqual(await runner.recorded().filter { $0 == "ddev list -j" }.count, 4)
        _ = await worker.handle(try encoder.encode(WorkerRequest(id: "import", operation: "ddev.list")))
        _ = await worker.handle(try encoder.encode(WorkerRequest(id: "after-import", operation: "project.status", project: project, refreshCycle: "second")))
        let missing = WorkerProject(id: project.id, distribution: project.distribution, kind: .ddev, path: "/devdeck-nonexistent-poll-fixture")
        let action = await worker.handle(try encoder.encode(WorkerRequest(id: "action", operation: "project.start", project: missing)))
        try expectEqual(action.error?.code, "missingFolder")
        _ = await worker.handle(try encoder.encode(WorkerRequest(id: "after-action", operation: "project.status", project: project, refreshCycle: "second")))
        try expectEqual(await runner.recorded().filter { $0 == "ddev list -j" }.count, 7)
    }
    await run.test("unavailable DDEV is shared inside a cycle and retried next cycle") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-poll-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = WorkerTestRunner(exitCode: 127)
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        let project = WorkerProject(id: "ddev.project.poll", distribution: "Ubuntu-24.04", kind: .ddev, path: folder.path)
        async let first = worker.handle(try encoder.encode(WorkerRequest(id: "first", operation: "project.status", project: project, refreshCycle: "same")))
        async let second = worker.handle(try encoder.encode(WorkerRequest(id: "second", operation: "project.status", project: project, refreshCycle: "same")))
        let responses = try await [first, second]
        try expect(responses.allSatisfy { $0.status?.state == "unknown" })
        try expectEqual(await runner.recorded().filter { $0 == "ddev list -j" }.count, 1)
        _ = await worker.handle(try encoder.encode(WorkerRequest(id: "next", operation: "project.status", project: project, refreshCycle: "next")))
        try expectEqual(await runner.recorded().filter { $0 == "ddev list -j" }.count, 2)
    }
    await run.test("invalid refresh cycles fail before executing a command") {
        let runner = WorkerTestRunner()
        let worker = WorkerService(distribution: "Ubuntu-24.04", runner: runner)
        for cycle in ["", "bad\ncycle", String(repeating: "Ж", count: 65)] {
            let response = await worker.handle(try encoder.encode(WorkerRequest(id: "invalid-cycle", operation: "hello", refreshCycle: cycle)))
            try expectEqual(response.error?.code, "invalidRequest")
        }
        try expectEqual(await runner.recorded(), [])
    }
    await run.test("chunked frames and EOF preserve request boundaries") {
        var framer = WorkerFramer(limit: 8)
        try expectEqual(framer.feed(Data("one".utf8)), [])
        try expectEqual(framer.feed(Data("\ntwo\n\nlast".utf8)), [.data(Data("one".utf8)), .data(Data("two".utf8))])
        try expectEqual(framer.finish(), [.data(Data("last".utf8))])
        try expectEqual(framer.finish(), [])
    }
    await run.test("oversized input is discarded and the next frame recovers") {
        var framer = WorkerFramer(limit: 4)
        try expectEqual(framer.feed(Data(repeating: 65, count: 100_000)), [])
        try expectEqual(framer.feed(Data("\nok\n".utf8)), [.oversized, .data(Data("ok".utf8))])
        let response = await service.handle(Data(repeating: 65, count: WorkerProtocol.maximumFrameBytes + 1))
        try expectEqual(response.error?.code, "frameTooLarge")
    }
    await run.test("Fusion port preflight rejects unrelated MongoDB ownership across distros") {
        let row = #"{"Names":"unrelated","Ports":"0.0.0.0:27017->27017/tcp, [::]:27017->27017/tcp","Labels":"com.docker.compose.project.working_dir=/home/user/other"}"#
        try expectEqual(ArcStartPreflight.conflict(requiredPorts: [27017], dockerRows: row, folder: "/home/user/fusion")?.code, "portConflict")
        try expect(ArcStartPreflight.conflict(requiredPorts: [3000], dockerRows: row, folder: "/home/user/fusion") == nil)
    }
    await run.test("Fusion preflight allows ports already held by the same checkout") {
        let row = #"{"Names":"own","Ports":"0.0.0.0:27017->27017/tcp","Labels":"com.docker.compose.project.working_dir=/home/user/fusion/.fusion"}"#
        try expect(ArcStartPreflight.conflict(requiredPorts: [27017], dockerRows: row, folder: "/home/user/fusion") == nil)
        try expectEqual(ArcStartPreflight.conflict(requiredPorts: [27017], dockerRows: row, folder: "/home/user/fusion-other")?.code, "portConflict")
    }
    await run.test("an undecodable Docker inventory fails port preflight closed") {
        try expectEqual(ArcStartPreflight.conflict(requiredPorts: [27017], dockerRows: "invalid", folder: "/tmp")?.code, "preflightUnavailable")
    }
}
