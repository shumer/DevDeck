import ArcKit
import DevDeckCore
import Foundation
import TestHarness

private func makeProject(
    folder: String? = "/tmp",
    localURL: String = "http://localhost",
    healthPath: String = "/release"
) -> ArcProject {
    ArcProject(
        id: "ilgiornale",
        title: "ilgiornale",
        organization: "editoriaitaliana",
        site: "ilgiornale",
        folder: folder,
        localURL: localURL,
        healthPath: healthPath
    )
}

func runArcTests(_ run: TestRun) async {
    run.section("Arc — project")

    await run.test("identifiers are slugged and never collide") {
        try expectEqual(ArcProject.makeID(from: "Il Giornale!", existing: []), "il-giornale")
        try expectEqual(ArcProject.makeID(from: "ledwall", existing: ["ledwall"]), "ledwall-2")
        try expectEqual(ArcProject.makeID(from: "", existing: []), "project")
    }

    await run.test("the card identifier is derived from the project") {
        try expectEqual(makeProject().cardID.rawValue, "arc.project.ilgiornale")
    }

    await run.test("links substitute the organisation and site") {
        let links = makeProject().resolvedLinks
        try expectEqual(links.count, 3, "only the three defaults are enabled out of the box")
        try expectEqual(links.first?.label, "PageBuilder")
        try expectEqual(
            links.first?.url.absoluteString,
            "https://editoriaitaliana.arcpublishing.com/pagebuilder"
        )
    }

    await run.test("a disabled link does not reach the card") {
        var project = makeProject()
        project.links = [
            ArcLink(label: "PageBuilder", urlTemplate: "https://{org}.example.com/pb", isEnabled: false),
            ArcLink(label: "Preview", urlTemplate: "https://{org}.example.com/{site}", isEnabled: true),
        ]
        let links = project.resolvedLinks
        try expectEqual(links.map(\.label), ["Preview"])
        try expectEqual(links.first?.url.absoluteString, "https://editoriaitaliana.example.com/ilgiornale")
    }

    await run.test("folders expand a tilde and gate the local controls") {
        let project = makeProject(folder: "~/Projects/ilgiornale")
        try expect(project.supportsLocalStack)
        try expect(project.folderURL?.path.hasPrefix("/") == true, "the tilde is expanded")
        try expect(!makeProject(folder: nil).supportsLocalStack)
        try expectNil(makeProject(folder: "").folderURL)
    }

    await run.test("the health URL survives a trailing slash") {
        try expectEqual(makeProject().healthURL?.absoluteString, "http://localhost/release")
        try expectEqual(
            makeProject(localURL: "http://localhost:8080/").healthURL?.absoluteString,
            "http://localhost:8080/release"
        )
    }

    run.section("Arc — project storage")

    await run.test("a deck with no projects has no project cards") {
        try expect(ArcProjectsStore(backend: InMemoryPreferences()).projects().isEmpty,
                   "unlike GitHub, there is no sensible project to invent")
    }

    await run.test("projects round trip and can be disabled") {
        let store = ArcProjectsStore(backend: InMemoryPreferences())
        var project = makeProject()
        project.isEnabled = false
        store.save([project, ArcProject(id: "ledwall", title: "ledwall", organization: "editoriaitaliana")])
        try expectEqual(store.projects().count, 2)
        try expectEqual(store.enabledProjects().map(\.id), ["ledwall"])
        try expectEqual(store.project(withID: "ilgiornale")?.title, "ilgiornale")
        try expectEqual(store.project(forCard: CardID(rawValue: "arc.project.ledwall"))?.id, "ledwall")
    }

    run.section("Arc — local stack status")

    await run.test("no folder means nothing to run or check") {
        let service = LocalStackService(
            project: makeProject(folder: nil),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([])
        )
        let status = await service.status()
        try expectEqual(status.state, .unavailable)
        try expectNil(await service.perform(.start), "a command must not run without a folder")
    }

    await run.test("a healthy engine reports running with its version") {
        let service = LocalStackService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([.success(.json("{\"version\":\"2026.7.2\"}"))])
        )
        let status = await service.status()
        try expectEqual(status.state, .running)
        try expectEqual(status.engineVersion, "2026.7.2")
        try expectNotNil(status.checkedAt, "checkedAt")
    }

    await run.test("a refused connection reads as stopped, not as an error") {
        let service = LocalStackService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([.failure(APIError.transport("connection refused"))])
        )
        try expectEqual(await service.status().state, .stopped)
    }

    await run.test("a non-2xx health answer is stopped with the code kept") {
        let service = LocalStackService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([.success(.status(502))])
        )
        let status = await service.status()
        try expectEqual(status.state, .stopped)
        try expectEqual(status.detail, "health check answered 502")
    }

    await run.test("the engine version is read from several shapes") {
        try expectEqual(
            LocalStackService.engineVersion(from: Data("{\"engineVersion\":\"1.2.3\"}".utf8)),
            "1.2.3"
        )
        try expectEqual(LocalStackService.engineVersion(from: Data("2026.7.2".utf8)), "2026.7.2")
        try expectNil(
            LocalStackService.engineVersion(from: Data("<html><body>nope</body></html>".utf8)),
            "an HTML error page is not a version"
        )
        try expectNil(LocalStackService.engineVersion(from: Data("{}".utf8)))
    }

    run.section("Arc — local stack actions")

    await run.test("each action runs its own command") {
        for (action, expected) in [
            (LocalStackAction.start, "npx fusion daemon"),
            (.stop, "npx fusion stop"),
            (.rebuild, "npx fusion rebuild"),
            (.teardown, "npx fusion down"),
        ] {
            let runner = StubCommandRunner([("npx", CommandResult(exitCode: 0, standardOutput: "", standardError: ""))])
            let service = LocalStackService(
                project: makeProject(),
                runner: runner,
                httpClient: FakeHTTPClient([])
            )
            _ = await service.perform(action)
            try expectEqual(await runner.commands, [expected])
        }
    }

    await run.test("restart stops before it starts") {
        let runner = StubCommandRunner([("npx", CommandResult(exitCode: 0, standardOutput: "", standardError: ""))])
        let service = LocalStackService(project: makeProject(), runner: runner, httpClient: FakeHTTPClient([]))
        _ = await service.perform(.restart)
        try expectEqual(await runner.commands, ["npx fusion stop", "npx fusion daemon"],
                        "starting before the ports are released fails in a confusing way")
    }

    await run.test("a failure surfaces its last meaningful line") {
        let result = CommandResult(
            exitCode: 1,
            standardOutput: "building…\n",
            standardError: "Error: port 80 is already allocated\n\n"
        )
        try expect(!result.succeeded)
        try expectEqual(result.failureLine, "Error: port 80 is already allocated")

        let quiet = CommandResult(exitCode: 1, standardOutput: "npm ERR! missing script\n", standardError: "")
        try expectEqual(quiet.failureLine, "npm ERR! missing script", "some tools report on stdout")
    }
}
