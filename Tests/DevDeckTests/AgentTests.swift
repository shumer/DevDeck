import DevDeckCore
import DevDeckEngine
import Foundation
import ProjectKit
import TestHarness

// The deck as an agent reaches it: what each setting lets through, that a command goes through
// the card's own rules, and that the endpoint is a real socket only its owner can use.

private let dockerUp = CommandResult(exitCode: 0, standardOutput: "27.0.1", standardError: "")

/// A plain project serving on localhost, started outside DevDeck: no pid on record.
private func servedProject() throws -> (project: LocalProject, files: ProjectRuntimeFiles) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-agents-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let project = LocalProject(
        id: "agent-\(UUID().uuidString.prefix(8))",
        title: "Sample",
        folder: directory.path,
        startCommand: "npm run dev",
        holdsProcess: true,
        healthURL: "http://localhost:5173"
    )
    return (project, ProjectRuntimeFiles(directory: directory))
}

@MainActor
private func makeDeck(_ access: AgentAccess) throws -> (deck: Deck, project: LocalProject, runner: StubCommandRunner) {
    let site = try servedProject()
    let runner = StubCommandRunner([(DockerEnvironment.probeCommand, dockerUp)])
    let deck = Deck(
        cards: [site.project.cardID, .githubPullRequests],
        runner: runner,
        localProjects: [site.project],
        projectHTTP: FakeHTTPClient(routes: [("localhost", .success(HTTPResponse(statusCode: 200)))]),
        projectFiles: site.files
    )
    deck.preferences.agentAccess = access
    return (deck, site.project, runner)
}

private func object(_ line: String) throws -> [String: Any] {
    try expectNotNil(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], "an object: \(line)")
}

private func request(_ fields: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), as: UTF8.self)
}

@MainActor
func runAgentTests(_ run: TestRun) async {
    run.section("Agents - what each setting lets through")

    await run.test("off answers only where to turn it on") {
        let (deck, _, _) = try makeDeck(.off)
        let agents = deck.runtime.serveAgents(version: "9.9", address: "/tmp/devdeck-unused-\(UUID().uuidString.prefix(6)).sock")
        try expect(!agents.isListening, "off opens nothing")
        let answer = try object(await agents.answer(request(["id": "1", "request": "hello"])))
        try expectEqual(answer["error"] as? String, L("agents.error.off"))
        try expectNil(answer["access"])
    }

    await run.test("read sees the cards and the menu's rows, and may not command") {
        let (deck, project, _) = try makeDeck(.read)
        await deck.runtime.refreshLocalOnce()
        let agents = deck.runtime.serveAgents(version: "9.9", address: "/tmp/devdeck-read-\(UUID().uuidString.prefix(6)).sock")
        defer { agents.stop() }

        let hello = try object(await agents.answer(request(["id": "1", "request": "hello"])))
        try expectEqual(hello["access"] as? String, "read")
        try expectEqual(hello["version"] as? String, "9.9")
        try expectEqual(hello["id"] as? String, "1", "the answer carries the question's id")

        let cards = try object(await agents.answer(request(["request": "cards"])))
        let ids = (cards["cards"] as? [[String: Any]] ?? []).compactMap { $0["card"] as? String }
        try expect(ids.contains(project.cardID.rawValue), "the project's card is there: \(ids)")
        let model = (cards["cards"] as? [[String: Any]])?.first { $0["card"] as? String == project.cardID.rawValue }?["model"] as? [String: Any]
        _ = try expectNotNil(model?["project"], "the model is the one the shell draws, keyed by its kind")

        let attention = try object(await agents.answer(request(["request": "attention"])))
        _ = try expectNotNil(attention["attention"] as? [Any], "the menu's rows, possibly none")

        let refused = try object(await agents.answer(request(["request": "command", "command": ["project": ["_0": project.cardID.rawValue, "_1": "stop"]]])))
        try expectEqual(refused["error"] as? String, L("agents.error.readOnly"))
    }

    await run.test("control runs a command through the card's own rules") {
        let (deck, project, runner) = try makeDeck(.control)
        await deck.runtime.refreshLocalOnce()
        let agents = deck.runtime.serveAgents(version: "9.9", address: "/tmp/devdeck-control-\(UUID().uuidString.prefix(6)).sock")
        defer { agents.stop() }

        // Started outside DevDeck: the card's Stop runs nothing, and neither does the agent's.
        let answer = try object(await agents.answer(request(["request": "command", "command": ["project": ["_0": project.cardID.rawValue, "_1": "stop"]]])))
        try expectNil(answer["error"])
        try expectEqual(answer["done"] as? Bool, true)
        let card = (answer["cards"] as? [[String: Any]])?.first
        try expectEqual(card?["card"] as? String, project.cardID.rawValue, "the answer is the card as it is now")
        let kills = await runner.commands.filter { $0.contains("kill") }
        try expect(kills.isEmpty, "nothing DevDeck did not start is stopped from here: \(kills)")
        let hero = ((card?["model"] as? [String: Any])?["project"] as? [String: Any])?["hero"] as? [String: Any]
        try expectEqual(hero?["note"] as? String, L("card.project.startedElsewhere"), "and the card says why")
    }

    await run.test("an agent may run a project's buttons and the inbox's, and nothing else") {
        try expect(DeckAgents.isAllowed(.project(CardID(rawValue: "project.x"), .start)))
        try expect(DeckAgents.isAllowed(.markRead(threadID: "1")))
        try expect(DeckAgents.isAllowed(.markRestRead))
        for command: DeckCommand in [.quit, .openSettings, .tidy, .installUpdate, .openTerminal(CardID(rawValue: "project.x")), .markAllRead] {
            try expect(!DeckAgents.isAllowed(command), "\(command) stays with the person")
        }

        let (deck, _, _) = try makeDeck(.control)
        let agents = deck.runtime.serveAgents(version: "9.9", address: "/tmp/devdeck-allowed-\(UUID().uuidString.prefix(6)).sock")
        defer { agents.stop() }
        let quit = try object(await agents.answer(request(["request": "command", "command": ["quit": [String: Any]()]])))
        try expectEqual(quit["error"] as? String, L("agents.error.notAllowed"))
        let unknown = try object(await agents.answer(request(["request": "command", "command": ["project": ["_0": "project.nowhere", "_1": "start"]]])))
        try expectEqual(unknown["error"] as? String, L("agents.error.unknownCard", "project.nowhere"))
        let nonsense = try object(await agents.answer("not json"))
        try expectEqual(nonsense["error"] as? String, L("agents.error.badRequest"))
        let other = try object(await agents.answer(request(["request": "dance"])))
        try expectEqual(other["error"] as? String, L("agents.error.unknownRequest", "dance"))
    }

    await run.test("a project's log is read as its window reads it, and a card with none says so") {
        let (deck, project, _) = try makeDeck(.read)
        let files = ProjectRuntimeFiles(directory: URL(fileURLWithPath: project.folder!))
        try "compiled\nlistening on 5173\n".write(to: files.log(project.id), atomically: true, encoding: .utf8)
        let agents = deck.runtime.serveAgents(version: "9.9", address: "/tmp/devdeck-log-\(UUID().uuidString.prefix(6)).sock")
        defer { agents.stop() }
        let answer = try object(await agents.answer(request(["request": "log", "card": project.cardID.rawValue])))
        let log = try expectNotNil(answer["log"] as? [String: Any], "a log: \(answer)")
        try expectEqual(log["lines"] as? [String], ["compiled", "listening on 5173"])
        let none = try object(await agents.answer(request(["request": "log", "card": CardID.githubPullRequests.rawValue])))
        try expectEqual(none["error"] as? String, L("agents.error.noLog", CardID.githubPullRequests.rawValue))
    }

    await run.test("the setting travels with the preferences, and a shell that does not know it leaves it alone") {
        let (deck, _, _) = try makeDeck(.read)
        var model = deck.runtime.preferencesModel
        try expectEqual(model.agentAccess, .read)
        model.agentAccess = nil
        _ = await deck.runtime.answer(.setPreferences(model))
        try expectEqual(deck.preferences.agentAccess, .read, "absent is not off")
        model.agentAccess = .control
        _ = await deck.runtime.answer(.setPreferences(model))
        try expectEqual(deck.preferences.agentAccess, .control)
    }

    await run.test("an agent adds the folder it works in, and what it says wins over what the folder says") {
        let (deck, _, _) = try makeDeck(.control)
        let agents = deck.runtime.serveAgents(version: "9.9", address: "/tmp/devdeck-add-\(UUID().uuidString.prefix(6)).sock")
        defer { agents.stop() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-added-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A folder the probe recognises: a dev script in package.json.
        try #"{"name":"sample","scripts":{"dev":"vite"}}"#.write(to: folder.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let seen = try object(await agents.answer(request(["request": "detect", "folder": folder.path])))
        let detection = try expectNotNil(seen["detection"] as? [String: Any], "a detection: \(seen)")
        let suggestion = try expectNotNil(detection["suggestion"] as? [String: Any], "the folder says what it is")
        try expectEqual(suggestion["startCommand"] as? String, "npm run dev")
        try expectNil(seen["card"], "not on the deck yet")

        let added = try object(await agents.answer(request([
            "request": "addProject", "folder": folder.path, "title": "Sample API",
            "startCommand": "npm run start:api", "healthURL": "http://localhost:4100/health", "localSiteURL": "http://localhost:4100/docs",
        ])))
        try expectNil(added["error"], "\(added)")
        let card = try expectNotNil(added["card"] as? String, "the new card")
        let project = try expectNotNil(deck.runtime.localProject(forCard: CardID(rawValue: card)), "written down")
        try expectEqual(project.title, "Sample API")
        try expectEqual(project.startCommand, "npm run start:api", "the agent's command, not the folder's")
        try expectEqual(project.healthURL, "http://localhost:4100/health")
        try expectEqual(project.localSiteURL, "http://localhost:4100/docs")
        try expect(project.holdsProcess, "what the folder said stays where the agent said nothing")
        try expectEqual(project.subtitle, "npm · vite")
        try expect((added["cards"] as? [[String: Any]])?.first?["card"] as? String == card, "the answer is the card")
        try expect(deck.effects.contains(.cardsChanged), "the deck is told a card came")

        let again = try object(await agents.answer(request(["request": "addProject", "folder": folder.path])))
        try expectEqual(again["error"] as? String, L("agents.error.alreadyOnDeck", "Sample API"))
        try expectEqual(again["card"] as? String, card, "and which card it is")
        let nowhere = try object(await agents.answer(request(["request": "addProject", "folder": "/nowhere/\(UUID().uuidString)"])))
        try expect((nowhere["error"] as? String)?.hasSuffix(" is not a folder on this computer.") == true, "a typo is not a card: \(nowhere)")

        let (reader, _, _) = try makeDeck(.read)
        let readOnly = reader.runtime.serveAgents(version: "9.9", address: "/tmp/devdeck-add-read-\(UUID().uuidString.prefix(6)).sock")
        defer { readOnly.stop() }
        let refused = try object(await readOnly.answer(request(["request": "addProject", "folder": folder.path])))
        try expectEqual(refused["error"] as? String, L("agents.error.readOnly"), "adding a card is control")
        let allowed = try object(await readOnly.answer(request(["request": "detect", "folder": folder.path])))
        _ = try expectNotNil(allowed["detection"], "looking at a folder is reading")
    }

    run.section("Agents - the endpoint")

    await run.test("a socket only its owner can use carries a line each way, and goes when stopped") {
        let path = "/tmp/devdeck-echo-\(UUID().uuidString.prefix(6)).sock"
        let server = LocalEndpointServer(address: path) { line in line.uppercased() }
        try server.start()
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        try expectEqual(mode, 0o600, "owner only")
        let first = try await Task.detached { try LocalEndpointClient.request("hello", address: path) }.value
        let second = try await Task.detached { try LocalEndpointClient.request("again", address: path) }.value
        try expectEqual(first, "HELLO")
        try expectEqual(second, "AGAIN")
        server.stop()
        for _ in 0..<40 where FileManager.default.fileExists(atPath: path) {
            try await Task.sleep(for: .milliseconds(25))
        }
        try expect(!FileManager.default.fileExists(atPath: path), "the socket file goes with the endpoint")
        do {
            _ = try await Task.detached { try LocalEndpointClient.request("hello", address: path) }.value
            throw TestFailure(message: "a closed endpoint answered", file: #filePath, line: #line)
        } catch let error as LocalEndpointError {
            try expectEqual(error, .notListening)
        }
    }

    await run.test("the deck answers through its endpoint, and closes it when access goes off") {
        let (deck, _, _) = try makeDeck(.read)
        let path = "/tmp/devdeck-deck-\(UUID().uuidString.prefix(6)).sock"
        let agents = deck.runtime.serveAgents(version: "9.9", address: path)
        try expect(agents.isListening, "read opens the endpoint")
        let line = try await Task.detached { try LocalEndpointClient.request(#"{"request":"hello"}"#, address: path) }.value
        try expectEqual(try object(line)["access"] as? String, "read")

        deck.preferences.agentAccess = .off
        agents.applyPreferences()
        try expect(!agents.isListening, "off closes it")
        for _ in 0..<40 where FileManager.default.fileExists(atPath: path) {
            try await Task.sleep(for: .milliseconds(25))
        }
        try expect(!FileManager.default.fileExists(atPath: path))
    }
}
