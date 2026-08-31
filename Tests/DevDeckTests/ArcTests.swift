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
    run.section("Arc - project")

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
        try expectEqual(links.count, 3, "only the three admin links are enabled out of the box")
        try expectEqual(links.first?.label, "PageBuilder")
        try expectEqual(
            links.first?.url.absoluteString,
            "https://editoriaitaliana.arcpublishing.com/home/",
            "the confirmed PageBuilder shape - the environment lives in the organisation field"
        )
    }

    await run.test("templates never prepend an environment of their own") {
        // The organisation field carries the whole host label, so a template that added
        // `sandbox.` produced sandbox.sandbox.ilgiornale.
        var project = makeProject()
        project.organization = "sandbox.ilgiornale"
        project.links = ArcLink.defaults()
        let byLabel = Dictionary(uniqueKeysWithValues: project.resolvedLinks.map { ($0.label, $0.url.absoluteString) })
        try expectEqual(byLabel["PageBuilder"], "https://sandbox.ilgiornale.arcpublishing.com/home/")
        try expectEqual(byLabel["Deployer"], "https://sandbox.ilgiornale.arcpublishing.com/deployments/fusion/")
    }

    await run.test("stored links are brought up to date on read") {
        let json = """
        { "id": "p", "title": "P", "organization": "sandbox.ilgiornale", "healthPath": "/release",
          "isEnabled": true, "localURL": "",
          "links": [
            { "label": "PageBuilder", "urlTemplate": "https://{org}.arcpublishing.com/pagebuilder", "isEnabled": true },
            { "label": "Dev Center", "urlTemplate": "https://{org}.arcpublishing.com/developer", "isEnabled": false }
          ] }
        """
        let project = try JSONDecoder().decode(ArcProject.self, from: Data(json.utf8))
        let byLabel = Dictionary(uniqueKeysWithValues: project.links.map { ($0.label, $0) })

        try expectEqual(byLabel["PageBuilder"]?.urlTemplate, "https://{org}.arcpublishing.com/home/",
                        "the old guessed path is replaced")
        try expectEqual(byLabel["Deployer"]?.urlTemplate, "https://{org}.arcpublishing.com/deployments/fusion/")
        try expect(byLabel["Deployer"]?.isEnabled == false, "whether it is shown stays the user's choice")
        try expect(byLabel["Sandbox"] != nil && byLabel["Prod"] != nil,
                   "links added since this project was created are appended")
    }

    await run.test("a Dev Center link someone edited keeps its name and its URL") {
        let json = """
        { "id": "p", "title": "P", "organization": "ilgiornale", "healthPath": "/release",
          "isEnabled": true, "localURL": "",
          "links": [{ "label": "Dev Center", "urlTemplate": "https://internal.example.com/dev", "isEnabled": true }] }
        """
        let project = try JSONDecoder().decode(ArcProject.self, from: Data(json.utf8))
        let theirs = try expectNotNil(project.links.first, "their link")
        try expectEqual(theirs.label, "Dev Center")
        try expectEqual(theirs.urlTemplate, "https://internal.example.com/dev")
    }

    await run.test("the card gets tooling and environments as separate rows") {
        var project = makeProject()
        project.links = [
            ArcLink(label: "PageBuilder", urlTemplate: "https://{org}.example.com/home", isEnabled: true),
            ArcLink(label: "Sandbox", urlTemplate: "https://sandbox.example.com", isEnabled: true, kind: .site),
            ArcLink(label: "Composer", urlTemplate: "https://{org}.example.com/composer", isEnabled: true),
            ArcLink(label: "Prod", urlTemplate: "https://example.com", isEnabled: true, kind: .site),
        ]
        try expectEqual(project.adminLinks.map(\.label), ["PageBuilder", "Composer"])
        try expectEqual(project.siteLinks.map(\.label), ["Sandbox", "Prod"])
        try expectEqual(project.resolvedLinks.count, 4, "configured order is left as it is")
    }

    await run.test("a site link stored before kinds existed is put back in its row") {
        // Sandbox and Prod shipped one build before kinds did, so a URL typed in between was
        // saved without one and read back as admin tooling - five chips in the top row.
        let json = """
        { "id": "p", "title": "P", "organization": "ilgiornale", "healthPath": "/release",
          "isEnabled": true, "localURL": "",
          "links": [
            { "label": "Sandbox", "urlTemplate": "https://sandbox.example.com", "isEnabled": true },
            { "label": "Prod", "urlTemplate": "https://example.com", "isEnabled": true }
          ] }
        """
        let project = try JSONDecoder().decode(ArcProject.self, from: Data(json.utf8))
        try expectEqual(project.siteLinks.map(\.label), ["Sandbox", "Prod"])
        try expect(!project.adminLinks.contains { $0.label == "Sandbox" || $0.label == "Prod" })
    }

    await run.test("links stored before kinds existed are admin tooling") {
        let json = """
        { "label": "PageBuilder", "urlTemplate": "https://{org}.arcpublishing.com/home/", "isEnabled": true }
        """
        let link = try JSONDecoder().decode(ArcLink.self, from: Data(json.utf8))
        try expectEqual(link.kind, .admin)
    }

    await run.test("a link with no URL yet is simply not drawn") {
        var project = makeProject()
        project.links = [ArcLink(label: "Prod", urlTemplate: "", isEnabled: true)]
        try expect(project.resolvedLinks.isEmpty, "an empty template has nothing to open")
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

    run.section("Arc - checked out branch")

    await run.test("the branch is read straight from .git/HEAD") {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("devdeck-git-\(UUID().uuidString)", isDirectory: true)
        let dotGit = folder.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let head = dotGit.appendingPathComponent("HEAD")

        try "ref: refs/heads/fix/EI-303-video-play-badge\n".write(to: head, atomically: true, encoding: .utf8)
        try expectEqual(GitCheckout.branch(in: folder), "fix/EI-303-video-play-badge",
                        "slashes in a branch name are normal")

        try "ref: refs/heads/main\n".write(to: head, atomically: true, encoding: .utf8)
        try expectEqual(GitCheckout.branch(in: folder), "main")

        // Detached HEAD holds a bare commit; the short form is what a prompt shows.
        try "9f2b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b\n".write(to: head, atomically: true, encoding: .utf8)
        try expectEqual(GitCheckout.branch(in: folder), "9f2b1c4")
    }

    await run.test("a worktree's gitdir pointer is followed") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("devdeck-wt-\(UUID().uuidString)", isDirectory: true)
        let real = root.appendingPathComponent("real-git", isDirectory: true)
        let checkout = root.appendingPathComponent("checkout", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "ref: refs/heads/spike\n".write(to: real.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try "gitdir: \(real.path)\n".write(to: checkout.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        try expectEqual(GitCheckout.branch(in: checkout), "spike")
    }

    await run.test("a folder that is not a checkout has no branch") {
        try expectNil(GitCheckout.branch(in: URL(fileURLWithPath: NSTemporaryDirectory())))
        try expectNil(GitCheckout.branch(in: nil))
    }

    run.section("Arc - the port comes from .env")

    await run.test("PORT is read the way a shell would read it") {
        let contents = """
        # local overrides
        FUSION_RELEASE=7.0.2

        export CONTENT_BASE="https://api.example.com"
        PORT = 8080
        EMPTY=
        """
        let values = EnvFile.parse(contents)
        try expectEqual(values["PORT"], "8080", "spaces around the equals sign are normal")
        try expectEqual(values["CONTENT_BASE"], "https://api.example.com", "quotes are stripped")
        try expectEqual(values["FUSION_RELEASE"], "7.0.2")
        try expectEqual(values["EMPTY"], "")
        try expectNil(values["# local overrides"], "comments are not variables")
    }

    await run.test("the local URL follows PORT, and leaves 80 implicit") {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("devdeck-env-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let envFile = folder.appendingPathComponent(".env")
        try "PORT=8080\n".write(to: envFile, atomically: true, encoding: .utf8)
        try expectEqual(EnvFile.localURL(in: folder), "http://localhost:8080")

        try "PORT=80\n".write(to: envFile, atomically: true, encoding: .utf8)
        try expectEqual(EnvFile.localURL(in: folder), "http://localhost", "80 is the browser default")

        try FileManager.default.removeItem(at: envFile)
        try expectEqual(EnvFile.localURL(in: folder), "http://localhost", "no .env falls back to 80")
        try expectEqual(EnvFile.port(in: nil), 80)
    }

    await run.test("the old hardcoded localhost default is dropped on read") {
        let json = """
        { "id": "p", "title": "P", "organization": "o", "localURL": "http://localhost",
          "startCommand": "npx fusion daemon", "stopCommand": "npx fusion stop",
          "rebuildCommand": "npx fusion rebuild", "teardownCommand": "npx fusion down",
          "healthPath": "/release", "isEnabled": true, "links": [] }
        """
        let project = try JSONDecoder().decode(ArcProject.self, from: Data(json.utf8))
        try expectEqual(project.localURL, "", "an earlier default is not a decision to preserve")

        let kept = """
        { "id": "p", "title": "P", "organization": "o", "localURL": "http://localhost:9000",
          "healthPath": "/release", "isEnabled": true, "links": [] }
        """
        try expectEqual(
            try JSONDecoder().decode(ArcProject.self, from: Data(kept.utf8)).localURL,
            "http://localhost:9000",
            "a port someone typed is kept"
        )
    }

    await run.test("a project without an override picks the port up from its checkout") {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("devdeck-env-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "PORT=8080\n".write(to: folder.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        var project = makeProject(folder: folder.path, localURL: "")
        try expectEqual(project.effectiveLocalURL, "http://localhost:8080")
        try expectEqual(project.healthURL?.absoluteString, "http://localhost:8080/release")

        project.localURL = "http://localhost:9999"
        try expectEqual(project.effectiveLocalURL, "http://localhost:9999",
                        "an explicit setting still wins")
    }

    run.section("Arc - project storage")

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

    run.section("Arc - local stack status")

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
        _ = try expectNotNil(status.checkedAt, "checkedAt")
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

    await run.test("a stop that did not take effect says so instead of going quiet") {
        // The failure this exists for: `fusion stop` returns, the containers stay up, and the
        // next poll paints the card green again as though the button had never been pressed.
        let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 0))
        let service = LocalStackService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient(routes: [("localhost", .success(.json("{}")))]),
            clock: clock,
            sleeper: AdvancingSleeper(clock: clock)
        )
        let status = await service.waitUntilStopped(timeout: 10, pollInterval: 2)
        try expectEqual(status.state, .running, "it is still up, and the card must not pretend otherwise")
        try expectEqual(status.detail, "stop did not take effect, still answering")
    }

    await run.test("a stop that worked resolves as soon as the engine goes quiet") {
        let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 0))
        let service = LocalStackService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([
                .success(.json("{}")),
                .failure(APIError.transport("connection refused")),
            ]),
            clock: clock,
            sleeper: AdvancingSleeper(clock: clock)
        )
        let status = await service.waitUntilStopped(timeout: 10, pollInterval: 2)
        try expectEqual(status.state, .stopped)
        try expectNil(status.detail, "nothing to explain when it simply worked")
    }

    await run.test("a start that printed a reason shows the reason, not the silence") {
        // The real failure: ddev-router holds port 80, `fusion daemon` cannot bind, four of ten
        // containers come up, and the command exits zero having said exactly what was wrong.
        let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 0))
        let service = LocalStackService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient(routes: [("localhost", .failure(APIError.transport("refused")))]),
            clock: clock,
            sleeper: AdvancingSleeper(clock: clock)
        )
        let hint = "Error response from daemon: ports are not available: "
            + "exposing port TCP 0.0.0.0:80 -> 127.0.0.1:0: listen tcp 0.0.0.0:80: bind: address already in use"
        let status = await service.waitUntilRunning(timeout: 10, pollInterval: 2, hint: hint)
        try expectEqual(status.state, .stopped)
        try expectEqual(status.detail, hint, "what the command said beats the fact that it went quiet")
    }

    await run.test("with nothing said, the card still names the URL it tried") {
        let clock = MutableDateProvider(now: Date(timeIntervalSince1970: 0))
        let service = LocalStackService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient(routes: [("localhost", .failure(APIError.transport("refused")))]),
            clock: clock,
            sleeper: AdvancingSleeper(clock: clock)
        )
        let status = await service.waitUntilRunning(timeout: 10, pollInterval: 2)
        try expectEqual(status.detail, "started, but http://localhost/release never answered")
    }

    await run.test("a running command hands over its lines as they arrive") {
        let output = "Container fusion-engine Starting\nContainer fusion-engine Started\nbind: address already in use"
        let runner = StubCommandRunner([
            ("fusion", CommandResult(exitCode: 0, standardOutput: output, standardError: "")),
        ])
        let service = LocalStackService(
            project: makeProject(),
            runner: runner,
            httpClient: FakeHTTPClient([])
        )

        let seen = Box<[String]>([])
        _ = await service.perform(.start) { line in seen.mutate { $0.append(line) } }
        try expectEqual(seen.value.count, 3, "one call per line, while the command is still going")
        try expectEqual(seen.value.last, "bind: address already in use")
    }

    run.section("Arc - which Fusion is actually running")

    // Taken from a real machine: two stacks' worth of containers, Fusion's compose project named
    // `fusion` whatever the checkout is, and the working directory as the only label that says
    // whose they are.
    let dockerOutput = """
    fusion-origin\twashpost/fusion-origin:latest\t/Users/me/Projects/libero-theme/.fusion
    fusion-engine\twashpost/fusion-engine:7.0.2\t/Users/me/Projects/libero-theme/.fusion
    fusion-cli-api\twashpost/fusion-cli-api:production\t/Users/me/Projects/libero-theme/.fusion
    ddev-shop-web\tdrud/ddev-webserver:v1.24\t/Users/me/Projects/shop
    """

    await run.test("containers belong to the checkout their compose file lives in") {
        // Fusion calls the compose project `fusion` for every checkout on the machine, so
        // filtering by project name matched nothing at all: the card showed no container count
        // and fell back to asking the site for its version.
        let mine = LocalStackService.containers(
            in: dockerOutput,
            folder: URL(fileURLWithPath: "/Users/me/Projects/libero-theme")
        )
        try expectEqual(mine.count, 3, "including the ones under .fusion, and not the neighbour's")
        try expect(!mine.contains { $0.name.hasPrefix("ddev") })
        try expect(LocalStackService.containers(
            in: dockerOutput,
            folder: URL(fileURLWithPath: "/Users/me/Projects/other")
        ).isEmpty)
    }

    await run.test("the release comes from the engine's image tag") {
        // The site's port is published by fusion-cli-api, so asking the site for /release answers
        // with that container's own version: this deck showed 6.2.0 for a stack running engine
        // 7.0.2, and both numbers were true about different things.
        let mine = LocalStackService.containers(
            in: dockerOutput,
            folder: URL(fileURLWithPath: "/Users/me/Projects/libero-theme")
        )
        try expectEqual(LocalStackService.engineRelease(in: mine), "7.0.2")
    }

    await run.test("a tag that says nothing is not shown as a version") {
        try expectNil(
            LocalStackService.engineRelease(in: [(name: "fusion-engine", image: "washpost/fusion-engine:latest")]),
            "`latest` on a card is a word, not an answer"
        )
        try expectNil(
            LocalStackService.engineRelease(in: [(name: "fusion-cli-api", image: "washpost/fusion-cli-api:6.2.0")]),
            "and the engine is the only container whose version is the stack's"
        )
        try expectNil(LocalStackService.engineRelease(in: []))
    }

    run.section("Arc - the local editor")

    await run.test("PageBuilder's editor follows the port the checkout serves on") {
        var project = ArcProject(id: "p", title: "P", organization: "acme", folder: "/tmp")
        project.localURL = "http://localhost:8112"
        try expectEqual(
            project.localPageBuilderURL?.absoluteString,
            "http://localhost:8112/pagebuilder/experiences/_default/pages/",
            "the host and port are the site's; only the path belongs to PageBuilder"
        )

        // Cleared, so the port comes from the checkout's own .env, which is where it really
        // lives. With no .env at all that is port 80, which Fusion leaves implicit.
        project.localURL = ""
        try expectEqual(
            project.localPageBuilderURL?.absoluteString,
            "http://localhost/pagebuilder/experiences/_default/pages/"
        )
    }

    await run.test("a multisite local URL keeps its query for the site and drops it for everything else") {
        // A multisite checkout is served as one origin with the site in the query. That query is
        // what makes the front end show Libero rather than one of its siblings, and it is exactly
        // what must not end up in the middle of a path.
        var project = ArcProject(id: "p", title: "Libero", organization: "acme", folder: "/tmp")
        project.localURL = "http://localhost:8112/?_website=liberoquotidiano"

        try expectEqual(project.localSiteURL?.absoluteString,
                        "http://localhost:8112/?_website=liberoquotidiano",
                        "the site link is the one thing that needs the query")
        try expectEqual(project.localPageBuilderURL?.absoluteString,
                        "http://localhost:8112/pagebuilder/experiences/_default/pages/")
        try expectEqual(project.healthURL?.absoluteString, "http://localhost:8112/release",
                        "the engine answers by path, not per site")
    }

    await run.test("the hosted PageBuilder link is a different place entirely") {
        let hosted = ArcLink.defaults().first { $0.label == "PageBuilder" }
        try expectEqual(hosted?.urlTemplate, "https://{org}.arcpublishing.com/home/",
                        "which is why the local one needed a chip of its own rather than a rename")
    }

    run.section("Arc - local stack actions")

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

    await run.test("a start waits for the engine instead of giving up at once") {
        // `fusion daemon` returns as soon as the containers exist; the engine answers later.
        let clock = MutableDateProvider()
        let service = LocalStackService(
            project: makeProject(),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient([
                .failure(APIError.transport("connection refused")),
                .failure(APIError.transport("connection refused")),
                .success(.json("{\"version\":\"7.0.2\"}")),
            ]),
            clock: clock,
            sleeper: AdvancingSleeper(clock: clock)
        )
        let status = await service.waitUntilRunning(timeout: 60, pollInterval: 2)
        try expectEqual(status.state, .running)
        try expectEqual(status.engineVersion, "7.0.2")
    }

    await run.test("a stack that never answers says which URL was tried") {
        let clock = MutableDateProvider()
        let responses = Array(repeating: Result<HTTPResponse, Error>.failure(APIError.transport("refused")), count: 100)
        let service = LocalStackService(
            project: makeProject(localURL: "http://localhost:1234"),
            runner: StubCommandRunner([]),
            httpClient: FakeHTTPClient(responses),
            clock: clock,
            sleeper: AdvancingSleeper(clock: clock)
        )
        let status = await service.waitUntilRunning(timeout: 10, pollInterval: 2)
        try expectEqual(status.state, .stopped)
        try expectEqual(
            status.detail,
            "started, but http://localhost:1234/release never answered",
            "the port is the usual culprit, so name it"
        )
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

        // What `npx fusion daemon` really prints outside a Fusion checkout: the reason first,
        // then a line about where the log lives.
        let npm = CommandResult(
            exitCode: 1,
            standardOutput: "",
            standardError: """
            npm error could not determine executable to run
            npm error A complete log of this run can be found in: /Users/x/.npm/_logs/debug.log
            """
        )
        try expectEqual(npm.failureLine, "npm error could not determine executable to run",
                        "the cause, not the path to the log")
    }
}
