import DevDeckCore
import Foundation
import ProjectKit
import TestHarness

private func makeProject(
    folder: String? = "/tmp",
    startCommand: String = "npm run dev",
    stopCommand: String = "",
    holdsProcess: Bool = true,
    requiresDocker: Bool = false,
    healthURL: String = "http://localhost:5173"
) -> LocalProject {
    LocalProject(
        id: "ledwall",
        title: "Ledwall",
        subtitle: "vite",
        folder: folder,
        startCommand: startCommand,
        stopCommand: stopCommand,
        holdsProcess: holdsProcess,
        requiresDocker: requiresDocker,
        healthURL: healthURL
    )
}

/// A scratch directory for the log and pid files, cleaned up by the caller.
private func makeRuntimeFiles() -> ProjectRuntimeFiles {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("devdeck-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return ProjectRuntimeFiles(directory: directory)
}

/// Writes a folder that looks like a real project, so the probe reads files rather than a mock.
private func makeFolder(_ files: [String: String]) -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("devdeck-probe-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, contents) in files {
        try? contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    return directory
}

func runProjectTests(_ run: TestRun) async {
    run.section("Projects - the model")

    await run.test("identifiers are slugged and never collide") {
        try expectEqual(LocalProject.makeID(from: "WR Proofing!", existing: []), "wr-proofing")
        try expectEqual(LocalProject.makeID(from: "ledwall", existing: ["ledwall"]), "ledwall-2")
        try expectEqual(LocalProject.makeID(from: "", existing: []), "project")
    }

    await run.test("the card identifier is derived from the project") {
        try expectEqual(makeProject().cardID.rawValue, "project.ledwall")
    }

    await run.test("the title falls back to the folder name") {
        var project = makeProject()
        project.title = "  "
        project.folder = "/Users/x/Projects/editoria-ledwall"
        try expectEqual(project.displayTitle, "editoria-ledwall")
    }

    await run.test("the local site follows the health URL unless overridden") {
        try expectEqual(makeProject().siteURL?.absoluteString, "http://localhost:5173")
        var project = makeProject()
        project.localSiteURL = "https://ledwall.localhost"
        try expectEqual(project.siteURL?.absoluteString, "https://ledwall.localhost")
    }

    await run.test("the local environment comes first, then whatever is filled in") {
        var project = makeProject()
        project.links = [
            LocalProjectLink(label: "Test", urlTemplate: "", isEnabled: false, kind: .site),
            LocalProjectLink(label: "Prod", urlTemplate: "https://ledwall.example.com", isEnabled: true, kind: .site),
            LocalProjectLink(label: "Admin", urlTemplate: "{site}/admin", isEnabled: true, kind: .tool),
        ]

        try expectEqual(project.environmentLinks().map(\.label), ["Local site", "Prod"],
                        "an empty environment is not a chip")
        try expectEqual(project.toolLinks().map(\.url.absoluteString), ["http://localhost:5173/admin"],
                        "{site} is substituted from the local URL")
    }

    await run.test("environments added since the project was made are appended on read") {
        let json = """
        { "id": "p", "title": "P", "startCommand": "make up",
          "links": [ { "label": "Prod", "urlTemplate": "https://x", "isEnabled": true, "kind": "site" } ] }
        """
        let project = try JSONDecoder().decode(LocalProject.self, from: Data(json.utf8))
        try expectEqual(project.links.map(\.label), ["Prod", "Test", "UAT"])
        try expectEqual(project.holdsProcess, false, "a field added later defaults rather than failing to decode")
    }

    await run.test("nothing local is offered without a folder and a command") {
        try expect(!makeProject(folder: nil).supportsCommands)
        try expect(!makeProject(startCommand: "").supportsCommands)
        try expect(makeProject().supportsCommands)
    }

    run.section("Projects - status")

    await run.test("no folder means nothing to run or check") {
        let files = makeRuntimeFiles()
        let service = LocalProjectService(
            project: makeProject(folder: nil),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([]),
            files: files
        )
        try expectEqual(await service.status().state, .unavailable)
        try expectNil(await service.perform(.start), "a command must not run without a folder")
    }

    await run.test("a server that serves means running, whatever else it says") {
        for code in [200, 204, 302, 401, 403] {
            let service = LocalProjectService(
                project: makeProject(),
                runner: StubCommandRunner([]),
                httpClient: FakeHTTPClient([.success(.status(code))]),
                files: makeRuntimeFiles()
            )
            // 401 and 403 are this project's own server asking you to sign in, which is a
            // normal thing for a health path to do.
            try expectEqual(await service.status().state, .running, "\(code)")
        }
    }

    await run.test("somebody else's server on the same port is not this project") {
        // The bug this rule exists for: a Docker container from another project held 8080 and
        // answered the configured /health with a 404, and the card called a backend nobody had
        // started "running". A 404 is a server saying it does not know this path.
        let service = LocalProjectService(
            project: makeProject(healthURL: "http://localhost:8080/health"),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([.success(.status(404))]),
            files: makeRuntimeFiles()
        )
        let status = await service.status()
        try expectEqual(status.state, .stopped)
        try expectEqual(status.detail, "http://localhost:8080/health answered 404",
                        "and the card says who answered what")

        try expect(!LocalProjectService.isServing(404))
        try expect(!LocalProjectService.isServing(500), "a crashed app is not something to open")
        try expect(LocalProjectService.isServing(200))
    }

    await run.test("a refused connection with nothing of ours running is stopped") {
        let service = LocalProjectService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([.failure(APIError.transport("connection refused"))]),
            files: makeRuntimeFiles()
        )
        let status = await service.status()
        try expectEqual(status.state, .stopped)
        try expectNil(status.pid, "pid")
    }

    await run.test("a live process that is not serving yet is starting, not stopped") {
        let files = makeRuntimeFiles()
        // This test process is alive by definition, which is the only pid a suite can rely on.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        try "\(ownPID)\n".write(to: files.pid("ledwall"), atomically: true, encoding: .utf8)

        let service = LocalProjectService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([.failure(APIError.transport("connection refused"))]),
            files: files
        )
        let status = await service.status()
        try expectEqual(status.state, .starting)
        try expectEqual(status.pid, ownPID)
    }

    await run.test("with no health URL the process is the whole answer") {
        let files = makeRuntimeFiles()
        try "\(ProcessInfo.processInfo.processIdentifier)".write(
            to: files.pid("ledwall"), atomically: true, encoding: .utf8
        )
        let service = LocalProjectService(
            project: makeProject(healthURL: ""),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([]),
            files: files
        )
        try expectEqual(await service.status().state, .running, "and no request was made")
    }

    await run.test("a dead pid is not a running project") {
        let files = makeRuntimeFiles()
        // Well above the system maximum, so it cannot belong to anything.
        try "999999".write(to: files.pid("ledwall"), atomically: true, encoding: .utf8)
        let service = LocalProjectService(
            project: makeProject(healthURL: ""),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([]),
            files: files
        )
        try expectEqual(await service.status().state, .stopped)
        try expect(!ProcessLiveness.isAlive(999_999))
        try expect(ProcessLiveness.isAlive(1), "launchd is alive even though it is not ours")
        try expect(!ProcessLiveness.isAlive(0))
    }

    run.section("Projects - the commands")

    await run.test("a command that holds its process is detached, logged and recorded") {
        let files = makeRuntimeFiles()
        let runner = StubCommandRunner([("nohup", CommandResult(exitCode: 0, standardOutput: "", standardError: ""))])
        let service = LocalProjectService(
            project: makeProject(),
            runner: runner,
            httpClient: FakeHTTPClient([]),
            files: files
        )
        _ = await service.perform(.start)

        let command = try expectNotNil(await runner.commands.first, "command")
        try expect(command.contains("nohup /bin/zsh -lc 'npm run dev'"), "the command runs under nohup")
        try expect(command.contains(">> '\(files.log("ledwall").path)' 2>&1"),
                   "its output goes to the log rather than to a pipe nobody drains")
        try expect(command.contains("echo $! > '\(files.pid("ledwall").path)'"), "the pid is written down")
    }

    await run.test("a command that returns is simply run, with its output kept") {
        let files = makeRuntimeFiles()
        let runner = StubCommandRunner([("docker", CommandResult(exitCode: 0, standardOutput: "", standardError: ""))])
        let service = LocalProjectService(
            project: makeProject(startCommand: "docker compose up -d", holdsProcess: false),
            runner: runner,
            httpClient: FakeHTTPClient([]),
            files: files
        )
        _ = await service.perform(.start)

        let command = try expectNotNil(await runner.commands.first, "command")
        try expect(!command.contains("nohup"), "nothing to detach - it returns on its own")
        try expect(command.contains("{ docker compose up -d ; }"))
        try expect(command.contains(files.log("ledwall").path), "the output is still readable afterwards")
    }

    await run.test("stopping without a stop command kills the whole tree") {
        let files = makeRuntimeFiles()
        try "4242".write(to: files.pid("ledwall"), atomically: true, encoding: .utf8)
        let runner = StubCommandRunner([("kt", CommandResult(exitCode: 0, standardOutput: "", standardError: ""))])
        let service = LocalProjectService(
            project: makeProject(),
            runner: runner,
            httpClient: FakeHTTPClient([]),
            files: files
        )
        _ = await service.perform(.stop)

        let command = try expectNotNil(await runner.commands.first, "command")
        // Killing the recorded pid alone leaves the server npm spawned holding the port.
        try expect(command.contains("pgrep -P"), "descendants are killed too")
        try expect(command.hasSuffix("kt 4242"))
        try expectNil(service.storedPID(), "the pid file is forgotten once it is stopped")
    }

    await run.test("a stop command is preferred over killing anything") {
        let files = makeRuntimeFiles()
        let runner = StubCommandRunner([("docker", CommandResult(exitCode: 0, standardOutput: "", standardError: ""))])
        let service = LocalProjectService(
            project: makeProject(stopCommand: "docker compose down", holdsProcess: false),
            runner: runner,
            httpClient: FakeHTTPClient([]),
            files: files
        )
        _ = await service.perform(.stop)
        let command = try expectNotNil(await runner.commands.first, "command")
        try expect(command.contains("docker compose down"))
        try expect(!command.contains("kill"))
    }

    await run.test("a restart stops before it starts") {
        let files = makeRuntimeFiles()
        try "4242".write(to: files.pid("ledwall"), atomically: true, encoding: .utf8)
        let runner = StubCommandRunner([
            ("kt", CommandResult(exitCode: 0, standardOutput: "", standardError: "")),
            ("nohup", CommandResult(exitCode: 0, standardOutput: "", standardError: "")),
        ])
        let service = LocalProjectService(
            project: makeProject(),
            runner: runner,
            httpClient: FakeHTTPClient([]),
            files: files
        )
        _ = await service.perform(.restart)

        let commands = await runner.commands
        try expectEqual(commands.count, 2)
        try expect(commands[0].contains("kt 4242"), "the old process goes first, or the port is still taken")
        try expect(commands[1].contains("nohup"))
    }

    await run.test("a command is quoted so the shell sees it exactly as typed") {
        try expectEqual(LocalProjectService.shellQuoted("npm run dev"), "'npm run dev'")
        try expectEqual(
            LocalProjectService.shellQuoted("sh -c 'echo hi'"),
            "'sh -c '\\''echo hi'\\'''",
            "a quote inside the command cannot end the quoting"
        )
    }

    await run.test("waiting gives up on a URL that never answers") {
        let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 0))
        let service = LocalProjectService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient(routes: [("localhost", .failure(APIError.transport("refused")))]),
            clock: clock,
            sleeper: AdvancingSleeper(clock: clock),
            files: makeRuntimeFiles()
        )
        let status = await service.waitUntilRunning(timeout: 10, pollInterval: 2)
        try expectEqual(status.state, .stopped)
        try expectEqual(
            status.detail,
            "started, but http://localhost:5173 never answered",
            "the URL that was tried is named - it is almost always the wrong port"
        )
    }

    run.section("Projects - reading a folder")

    await run.test("a compose file is a detached start with a matching stop") {
        let folder = makeFolder(["docker-compose.yml": "services:\n  web:\n"])
        let suggestion = try expectNotNil(ProjectProbe.suggestion(for: folder), "suggestion")
        try expectEqual(suggestion.startCommand, "docker compose up -d")
        try expectEqual(suggestion.stopCommand, "docker compose down")
        try expectEqual(suggestion.holdsProcess, false)
        try expectEqual(suggestion.requiresDocker, true)
    }

    await run.test("a dev script holds its process, and the port is guessed from the tooling") {
        let folder = makeFolder([
            "package.json": #"{"scripts":{"dev":"vite"},"devDependencies":{"vite":"^5.0.0"}}"#,
        ])
        let suggestion = try expectNotNil(ProjectProbe.suggestion(for: folder), "suggestion")
        try expectEqual(suggestion.startCommand, "npm run dev")
        try expectEqual(suggestion.holdsProcess, true)
        try expectEqual(suggestion.healthURL, "http://localhost:5173")
        try expectEqual(suggestion.requiresDocker, false)
    }

    await run.test("the lock file decides which package manager is offered") {
        let folder = makeFolder([
            "package.json": #"{"scripts":{"dev":"next dev"}}"#,
            "pnpm-lock.yaml": "lockfileVersion: 9",
        ])
        let suggestion = try expectNotNil(ProjectProbe.suggestion(for: folder), "suggestion")
        try expectEqual(suggestion.startCommand, "pnpm run dev")
        try expectEqual(suggestion.subtitle, "pnpm")
        try expectEqual(suggestion.healthURL, "http://localhost:3000", "next, read from the script line")
    }

    await run.test("compose wins over a Makefile in the same folder") {
        let folder = makeFolder([
            "compose.yaml": "services:\n  web:\n",
            "Makefile": "up:\n\tdocker compose up -d\n",
        ])
        try expectEqual(ProjectProbe.suggestion(for: folder)?.startCommand, "docker compose up -d")
    }

    await run.test("a Makefile is read for the targets a card would use") {
        let folder = makeFolder([
            "Makefile": ".PHONY: up down\nSHELL = /bin/sh\nup:\n\tdocker compose up -d\ndown:\n\tdocker compose down\n",
        ])
        let suggestion = try expectNotNil(ProjectProbe.suggestion(for: folder), "suggestion")
        try expectEqual(suggestion.startCommand, "make up")
        try expectEqual(suggestion.stopCommand, "make down")
        try expectEqual(suggestion.requiresDocker, true, "the recipe says docker even though the command does not")

        let targets = ProjectProbe.makeTargets(in: "up:\n\tcmd\n.PHONY: up\nVAR = 1\n\tindented: no\n")
        try expectEqual(targets, ["up"], "variables, phony lines and recipe bodies are not targets")
    }

    await run.test("a folder with nothing recognisable suggests nothing") {
        try expectNil(ProjectProbe.suggestion(for: makeFolder(["README.md": "hi"])), "suggestion")
    }

    run.section("Docker - one answer for the whole deck")

    let now = Date(timeIntervalSince1970: 1_000)

    await run.test("a version means the daemon answered") {
        let status = DockerEnvironment.status(
            from: CommandResult(exitCode: 0, standardOutput: "28.0.4\n", standardError: ""),
            now: now
        )
        try expectEqual(status.state, .running)
        try expectEqual(status.serverVersion, "28.0.4")
        try expect(status.isReady)
        try expectNil(status.blockingReason, "blockingReason")
    }

    await run.test("the daemon being down is not the CLI being missing") {
        // Recorded from a machine with Docker Desktop installed and not started.
        let down = DockerEnvironment.status(
            from: CommandResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "Cannot connect to the Docker daemon at unix:///Users/x/.docker/run/docker.sock."
            ),
            now: now
        )
        try expectEqual(down.state, .notRunning)
        try expectEqual(down.blockingReason, "Docker is not running")
        try expect(!down.allowsStart, "a Start that cannot work must not be offered")

        let missing = DockerEnvironment.status(
            from: CommandResult(exitCode: 127, standardOutput: "", standardError: "zsh: command not found: docker"),
            now: now
        )
        try expectEqual(missing.state, .notInstalled)
    }

    await run.test("not having asked yet blocks nothing") {
        let unknown = DockerStatus(state: .unknown)
        try expect(unknown.allowsStart, "the first poll of a launch must not grey out every button")
        try expectNil(unknown.blockingReason, "blockingReason")
        try expect(!unknown.isReady)
    }
}
