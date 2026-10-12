import ArcKit
import DevDeckCore
import DevDeckEngine
import DevDeckLocalization
import Foundation
import TestHarness

@MainActor
func runTerminalReadinessTests(_ run: TestRun) async {
    Strings.use(.english, lookingIn: LocalizationResources.root)
    let guid = "{00000000-0000-0000-0000-000000000001}"
    await run.test("terminal profiles preserve JSONC strings and skip hidden or invalid profiles") {
        let profiles = TerminalProfiles.parse(#"""
            {
              // The default profiles are supplied by Terminal.
              "profiles": { "list": [
                {"guid":"{00000000-0000-0000-0000-000000000001}","name":"Demo // shell",},
                {"guid":"{00000000-0000-0000-0000-000000000002}","name":"Hidden","hidden":true},
                {"guid":"invalid","name":"Invalid"},
                {"guid":"{00000000-0000-0000-0000-000000000001}","name":"Duplicate"}, /* Last entry. */
              ] }
            }
            """#)
        try expectEqual(profiles, [TerminalProfile(id: guid, name: "Demo // shell")])
        try expect(TerminalProfiles.parse("not JSON").isEmpty)
    }
    await run.test("terminal settings persist, reset profiles and keep the system default") {
        let applications = [TerminalApplication(id: "windowsTerminal", profiles: [TerminalProfile(id: guid, name: "Demo shell")]), TerminalApplication(id: "commandPrompt")]
        let (runtime, preferences) = goldenRuntime(terminalApplications: { applications })
        _ = await runtime.answer(.setTerminalProfile(value: guid))
        try expectEqual(preferences.terminalWindows, TerminalChoice(profile: guid))
        try expectEqual(runtime.terminalSettings().fields.count, 2)
        _ = await runtime.answer(.setTerminalApplication(value: "commandPrompt"))
        try expectEqual(preferences.terminalWindows, TerminalChoice(application: "commandPrompt"))
        try expectEqual(runtime.terminalSettings().fields.count, 1)
        _ = await runtime.answer(.setTerminalApplication(value: "missing"))
        try expectEqual(preferences.terminalWindows.application, "commandPrompt")
        _ = await runtime.answer(.setTerminalApplication(value: nil))
        try expectEqual(preferences.terminalWindows, TerminalChoice())
        let backend = InMemoryPreferences()
        let saved = Preferences(backend: backend)
        saved.terminalWindows = TerminalChoice(application: "windowsTerminal", profile: guid)
        try expectEqual(Preferences(backend: backend).terminalWindows, saved.terminalWindows)
    }
    await run.test("an open terminal effect carries the persisted choice") {
        let (runtime, preferences) = goldenRuntime()
        preferences.terminalWindows = TerminalChoice(application: "windowsTerminal", profile: guid)
        var bytes = Data()
        let session = DeckSession(runtime: runtime, localizationRoot: LocalizationResources.root, runsLoops: false) { bytes.append($0) }
        session.handle(line: Data(#"{"protocolVersion":2,"id":"1","intent":"session.start","displays":[{"id":"demo","frame":[0,0,1500,900],"isPrimary":true}]}"#.utf8))
        session.handle(line: Data(#"{"protocolVersion":2,"id":"2","intent":"command","command":{"openTerminal":{"_0":"project.feed"}}}"#.utf8))
        let lines = String(decoding: bytes, as: UTF8.self).split(separator: "\n")
        guard let line = lines.first(where: { $0.contains("\"kind\":\"openTerminal\"") }) else {
            throw TestFailure(message: "No terminal effect", file: #filePath, line: #line)
        }
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        let effect = object?["effect"] as? [String: Any]
        let terminal = effect?["terminal"] as? [String: String]
        try expectEqual(terminal?["profile"], guid)
        try expectEqual(terminal?["application"], "windowsTerminal")
        session.stop()
    }
    await run.test("Arc readiness names a missing folder, command, Node or Fusion without downloading") {
        let project = ArcProject(id: "demo", title: "Demo", organization: "demo", folder: "/demo")
        let runner = StubCommandRunner([])
        let noFolder = await ArcLaunchReadiness.check(project, runner: runner, pathExists: { _ in false })
        try expect(!noFolder.canStart)
        var empty = project
        empty.startCommand = ""
        let noCommand = await ArcLaunchReadiness.check(empty, runner: runner, pathExists: { _ in true })
        try expect(!noCommand.canStart)
        let noNode = await ArcLaunchReadiness.check(project, runner: runner, pathExists: { _ in true })
        try expectEqual(noNode.detail, L("arc.readiness.node"))
        let cli = StubCommandRunner([
            ("node --version", CommandResult(exitCode: 0, standardOutput: "v22.0.0\n", standardError: "")),
            ("npx --version", CommandResult(exitCode: 0, standardOutput: "10.0.0", standardError: "")),
        ])
        let noCLI = await ArcLaunchReadiness.check(project, runner: cli, pathExists: { _ in true })
        try expectEqual(noCLI.detail, L("arc.readiness.fusion"))
        let commands = await cli.commands
        try expect(!commands.contains { $0.contains("npx fusion") || $0.contains("npm install") })
    }
    await run.test("Arc readiness respects the WSL environment and accepts an installed CLI") {
        let runner = StubCommandRunner([
            ("node --version", CommandResult(exitCode: 0, standardOutput: "v22.0.0", standardError: "")),
            ("npx --version", CommandResult(exitCode: 0, standardOutput: "10.0.0", standardError: "")),
            ("require.resolve", CommandResult(exitCode: 0, standardOutput: "devdeck-fusion-ready", standardError: "")),
        ])
        let project = ArcProject(id: "demo", title: "Demo", organization: "demo", folder: "/demo", startCommand: "PATH=/demo/node/bin:$PATH npx fusion daemon")
        let readiness = await ArcLaunchReadiness.check(project, runner: runner, pathExists: { _ in true })
        try expect(readiness.canStart)
        let commands = await runner.commands
        try expect(commands.allSatisfy { $0.hasPrefix("PATH=/demo/node/bin:$PATH ") })
    }
    await run.test("custom Arc commands do not require Fusion and missing Node scripts are blocked") {
        let runner = StubCommandRunner([("node --version", CommandResult(exitCode: 0, standardOutput: "v22.0.0", standardError: ""))])
        var project = ArcProject(id: "demo", title: "Demo", organization: "demo", folder: "/demo", startCommand: "node daemon.js")
        let valid = await ArcLaunchReadiness.check(project, runner: runner, pathExists: { _ in true })
        try expect(valid.canStart)
        let missing = await ArcLaunchReadiness.check(project, runner: runner, pathExists: { $0.lastPathComponent != "daemon.js" })
        try expectEqual(missing.detail, L("arc.readiness.script"))
        project.startCommand = "custom-tool start"
        let custom = await ArcLaunchReadiness.check(project, runner: runner, pathExists: { _ in true })
        try expect(custom.canStart && custom.detail == L("arc.readiness.custom"))
        let count = await runner.commands.count
        for value in ["$(custom-tool)", "value&custom-tool", "value>demo-output", "value<demo-input"] {
            project.startCommand = "CHECK=\(value) npx fusion daemon"
            let unchecked = await ArcLaunchReadiness.check(project, runner: runner, pathExists: { _ in true })
            try expectEqual(await runner.commands.count, count)
            try expectEqual(unchecked.detail, L("arc.readiness.custom"))
        }
    }
    await run.test("Arc readiness also resolves a global CLI without interpreting its path in the shell") {
        let encoded = Data("/demo/global folder".utf8).base64EncodedString()
        let runner = StubCommandRunner([
            (encoded, CommandResult(exitCode: 0, standardOutput: "devdeck-fusion-ready", standardError: "")),
            ("node --version", CommandResult(exitCode: 0, standardOutput: "v22.0.0", standardError: "")),
            ("npx --version", CommandResult(exitCode: 0, standardOutput: "10.0.0", standardError: "")),
            ("npm root -g", CommandResult(exitCode: 0, standardOutput: "/demo/global folder\n", standardError: "")),
        ])
        let project = ArcProject(id: "demo", title: "Demo", organization: "demo", folder: "/demo")
        let readiness = await ArcLaunchReadiness.check(project, runner: runner, pathExists: { _ in true })
        try expect(readiness.canStart)
        let commands = await runner.commands
        try expect(!commands.contains { $0.contains("/demo/global folder") })
    }
    await run.test("Arc start rechecks readiness before running a command") {
        let runner = StubCommandRunner([])
        let (runtime, _) = goldenRuntime(commandRunner: runner, checksArcReadiness: true)
        let project = ArcProject(id: "demo", title: "Demo", organization: "demo", folder: "/invalid/arc-readiness")
        runtime.perform(.start, for: project)
        await runtime.settle()
        let commands = await runner.commands
        try expect(commands.isEmpty)
        try expect(runtime.stackStatus(for: project).readiness?.canStart == false)
    }
    await run.test("Arc rechecks Docker in the project's runner before starting") {
        let runner = StubCommandRunner([
            ("node --version", CommandResult(exitCode: 0, standardOutput: "v22.0.0", standardError: "")),
            ("npx --version", CommandResult(exitCode: 0, standardOutput: "10.0.0", standardError: "")),
            ("require.resolve", CommandResult(exitCode: 0, standardOutput: "devdeck-fusion-ready", standardError: "")),
            ("docker version", CommandResult(exitCode: 1, standardOutput: "", standardError: "offline")),
        ])
        let (runtime, _) = goldenRuntime(commandRunner: runner, checksArcReadiness: true)
        let project = ArcProject(id: "demo", title: "Demo", organization: "demo", folder: NSHomeDirectory())
        runtime.perform(.start, for: project)
        await runtime.settle()
        try expect(runtime.stackStatus(for: project).readiness?.canStart == false)
        let commands = await runner.commands
        try expect(commands.contains { $0.contains("docker version") })
        try expect(!commands.contains { $0.contains("npx fusion daemon") })
    }
    await run.test("a stopped Arc card is neutral until the first poll has asked") {
        let (runtime, _) = goldenRuntime(commandRunner: StubCommandRunner([]), checksArcReadiness: true)
        let project = ArcProject(id: "fresh", title: "Fresh", organization: "demo", folder: NSHomeDirectory())
        let status = runtime.stackStatus(for: project)
        try expectNil(status.readiness, "nothing has been checked yet")
        let card = DeckProjectCardModel.arc(project, status: status, docker: DockerStatus(state: .running), canStartDocker: true, isShowingLogs: false, isCollapsed: false, phoneURL: nil)
        try expectEqual(card.hero.text, L("card.state.stopped"))
        try expectEqual(card.hero.tone, .neutral)
    }
    await run.test("the launch check runs once per folder and command, and again after they change or a press") {
        let runner = StubCommandRunner([])
        let (runtime, _) = goldenRuntime(commandRunner: runner, checksArcReadiness: true)
        var project = ArcProject(id: "paper", title: "Paper", organization: "demo", folder: NSHomeDirectory())
        _ = runtime.saveArcProject(project)
        func probes() async -> Int { await runner.commands.filter { $0.contains("node --version") }.count }
        await runtime.refreshLocalOnce()
        await runtime.refreshLocalOnce()
        await runtime.refreshLocalOnce()
        try expectEqual(await probes(), 1, "three polls, one check")
        try expect(runtime.stackStatus(for: project).readiness?.canStart == false, "and its answer is on the card")
        project.startCommand = "PATH=/opt/demo/bin:$PATH npx fusion daemon"
        _ = runtime.saveArcProject(project)
        await runtime.refreshLocalOnce()
        try expectEqual(await probes(), 2, "a new command is a new question")
        runtime.perform(.start, for: project)
        await runtime.settle()
        try expectEqual(await probes(), 3, "a press asks afresh")
        await runtime.refreshLocalOnce()
        try expectEqual(await probes(), 3, "and the poll after it trusts that answer")
    }
    await run.test("a change of language is a new question, so the reason reads in the new language") {
        let runner = StubCommandRunner([])
        let (runtime, preferences) = goldenRuntime(commandRunner: runner, checksArcReadiness: true)
        let project = ArcProject(id: "paper", title: "Paper", organization: "demo", folder: NSHomeDirectory())
        _ = runtime.saveArcProject(project)
        await runtime.refreshLocalOnce()
        try expectEqual(runtime.stackStatus(for: project).readiness?.detail, "Node is not available in this project's environment.")
        preferences.language = .russian
        Strings.use(.russian, lookingIn: LocalizationResources.root)
        defer { Strings.use(.english, lookingIn: LocalizationResources.root) }
        await runtime.refreshLocalOnce()
        try expectEqual(runtime.stackStatus(for: project).readiness?.detail, "Node недоступен в среде этого проекта.")
        try expectEqual(await runner.commands.filter { $0.contains("node --version") }.count, 2, "asked once per language")
    }
    await run.test("editing an Arc start command gives Check Now a new question") {
        let (runtime, _) = goldenRuntime()
        var project = ArcProject(id: "demo", title: "Demo", organization: "demo", folder: "/demo")
        _ = runtime.saveArcProject(project)
        project.startCommand = "node daemon.js"
        try expect(runtime.saveArcProject(project))
    }
    await run.test("Arc cards disable Start and Restart but retain Stop when launch requirements are missing") {
        let project = ArcProject(id: "demo", title: "Demo", organization: "demo", folder: "/demo")
        var status = LocalStackStatus(state: .stopped)
        status.readiness = ArcLaunchReadiness(canStart: false, detail: "Missing CLI")
        func card(_ status: LocalStackStatus) -> DeckProjectCardModel {
            DeckProjectCardModel.arc(project, status: status, docker: DockerStatus(state: .running), canStartDocker: true, isShowingLogs: false, isCollapsed: false, phoneURL: nil)
        }
        try expect(card(status).actions.first(where: { $0.glyph == .start })?.isEnabled == false)
        status.state = .running
        try expect(card(status).actions.first(where: { $0.glyph == .stop })?.isEnabled == true)
        try expect(card(status).actions.first(where: { $0.glyph == .restart })?.isEnabled == false)
    }
}
