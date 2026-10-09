import ArcKit
import DevDeckCore
import DevDeckEngine
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit
import TestHarness

// What the settings window decides, in the engine: the sidebar and the operations behind the
// forms, checked without a window.

/// A folder with a `package.json` whose dev script is what Detect should find.
private func nodeFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-settings-\(UUID().uuidString)/site")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"name":"site","scripts":{"dev":"vite"}}"#.utf8).write(to: folder.appendingPathComponent("package.json"))
    return folder
}

@MainActor
func runSettingsModelTests(_ run: TestRun) async {
    run.section("Settings model - the sidebar")

    await run.test("projects are listed by name whatever their kind, and a stopped one wears no dot") {
        let projects = [
            LocalProject(id: "zeta", title: "Zeta", folder: "/tmp", startCommand: "npm run dev"),
            LocalProject(id: "alpha", title: "Alpha", folder: "/tmp", startCommand: ""),
        ]
        let deck = Deck(cards: [], localProjects: projects)
        let list = deck.runtime.settingsList()
        try expectEqual(list.projects.map(\.title), ["Alpha", "Zeta"])
        try expectEqual(list.projects.first?.detail, L("project.list.noStart"), "no start command says so")
        try expectNil(list.projects.first?.tone)
    }

    await run.test("an account with no token is flagged, one with a token is not") {
        let deck = Deck(cards: [])
        let list = deck.runtime.settingsList()
        try expectEqual(list.accounts.first?.tone, nil, "the test deck's account has a token")
        _ = deck.runtime.addGitHubAccount()
        let flagged = deck.runtime.settingsList().accounts.filter { $0.tone == .attention }
        try expectEqual(flagged.count, 1)
        try expectEqual(flagged.first?.detail, L("settings.list.noToken", "GitHub"))
    }

    run.section("Settings model - plain projects")

    await run.test("a project added from a folder takes what the folder says about itself") {
        let folder = try nodeFolder()
        let deck = Deck(cards: [])
        let id = deck.runtime.addLocalProject(folder: folder)
        let project = try expectNotNil(deck.runtime.settingsList().projects.first { $0.id == id }, "added")
        try expectEqual(project.title, "site")
        try expect(project.detail.contains("dev"), "the dev script becomes the start command: \(project.detail)")
    }

    await run.test("Detect names what it found, or says why it found nothing") {
        let deck = Deck(cards: [])
        let none = deck.runtime.detect(folder: nil)
        try expectEqual(none.note, L("project.detect.noFolder"))
        try expect(none.isError)
        try expectNil(none.suggestion)
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try expectEqual(deck.runtime.detect(folder: empty).note, L("project.detect.nothing"))
        let found = deck.runtime.detect(folder: try nodeFolder())
        try expect(!found.isError)
        try expect(found.suggestion != nil)
    }

    await run.test("an edit asks the status line again only when it changes the question") {
        var project = LocalProject(id: "ask", title: "Ask", folder: "/tmp", startCommand: "npm run dev", healthURL: "http://localhost:3000")
        let deck = Deck(cards: [], localProjects: [project])
        project.title = "Asked"
        try expect(!deck.runtime.saveLocalProject(project), "a new title is not a new question")
        project.healthURL = "http://localhost:4000"
        try expect(deck.runtime.saveLocalProject(project), "a new address is")
    }

    await run.test("testing a link opens the first one in the project's browser, or says there is none") {
        let deck = Deck(cards: [])
        let bare = LocalProject(id: "bare", title: "Bare", folder: "/tmp", startCommand: "npm run dev", links: [])
        try expectEqual(deck.runtime.testLink(bare), .note(L("project.link.nothingToOpen")))
    }

    run.section("Settings model - Arc and accounts")

    await run.test("an Arc project with no folder has no stack to check") {
        let deck = Deck(cards: [])
        let project = ArcProject(id: "a", title: "A", organization: "o")
        let status = await deck.runtime.checkArcStack(project)
        try expectNil(status)
    }

    await run.test("adding a GitLab instance turns the GitLab card on") {
        let deck = Deck(cards: [])
        deck.runtime.cards.setEnabled(false, for: .gitlabMergeRequests)
        _ = deck.runtime.addGitLabAccount()
        try expect(deck.runtime.cards.isEnabled(.gitlabMergeRequests))
    }

    await run.test("a typed token is kept only once it works") {
        let deck = Deck(cards: [], http: FakeHTTPClient([.success(.json(Fixtures.pullRequestSearch))]))
        let id = deck.runtime.addGitHubAccount()
        let fresh = GitHubAccount(id: id, label: "New")
        let answer = await deck.runtime.checkGitHubToken(for: fresh, typed: "typed-token")
        guard case .works = answer else {
            throw TestFailure(message: "the token should work: \(answer)", file: #filePath, line: #line)
        }
        try expect(deck.runtime.hasToken(fresh.tokenKey), "kept once it worked")
    }

    await run.test("with no token at all, both services say a token is needed") {
        let deck = Deck(cards: [], http: FakeHTTPClient([.success(.status(401)), .success(.status(401))]))
        let github = GitHubAccount(id: "nobody", label: "Nobody")
        try expectEqual(await deck.runtime.checkGitHubToken(for: github, typed: ""), .refused(L("token.needed")))
        let gitlab = GitLabAccount(id: "nobody", label: "Nobody")
        try expectEqual(await deck.runtime.checkGitLabToken(for: gitlab, typed: ""), .refused(L("token.needed")))
    }

    await run.test("removing an account takes its token with it") {
        let deck = Deck(cards: [])
        try expect(deck.runtime.hasToken(deck.account.tokenKey))
        deck.runtime.removeGitHubAccount(deck.account.id)
        try expect(!deck.runtime.hasToken(deck.account.tokenKey))
    }
}

// MARK: Updates

private func release(_ tag: String) -> String {
    """
    {"tag_name":"\(tag)","html_url":"https://github.com/shumer/DevDeck/releases/tag/\(tag)",
     "draft":false,"prerelease":false,"published_at":"2026-10-01T10:00:00Z",
     "assets":[{"name":"DevDeck-\(tag.dropFirst())-1.zip","browser_download_url":"https://example.com/DevDeck.zip","size":2097152}]}
    """
}

@MainActor
func runUpdateModelTests(_ run: TestRun) async {
    run.section("Updates - checking")

    await run.test("a newer release is on offer, said once in a banner, and not again for the same version") {
        let deck = Deck(cards: [], notifications: true)
        deck.preferences.notifiesUpdates = true
        let http = FakeHTTPClient([.success(.json(release("v9.0"))), .success(.json(release("v9.0")))])
        let updates = deck.runtime.watchForUpdates(currentVersion: "0.19.2", canInstall: true, http: http)
        await updates.check(quietly: false)
        try expectEqual(updates.available?.version.description, "9.0")
        try expectEqual(deck.effects.filter { if case .offerUpdate = $0 { return true }; return false }.count, 1)
        await updates.check(quietly: true)
        try expectEqual(deck.effects.filter { if case .offerUpdate = $0 { return true }; return false }.count, 1, "a restart is not news")
        try expect(deck.runtime.menu().contains { if case .header = $0 { return true }; return false })
    }

    await run.test("the same version or an older one is not an update") {
        let deck = Deck(cards: [])
        let updates = deck.runtime.watchForUpdates(currentVersion: "9.0", canInstall: true, http: FakeHTTPClient([.success(.json(release("v9.0")))]))
        await updates.check(quietly: false)
        try expectNil(updates.available)
        try expectEqual(updates.row().summary.state, L("update.upToDate"))
    }

    await run.test("a background check that fails keeps quiet; one somebody asked for says why") {
        let deck = Deck(cards: [])
        let updates = deck.runtime.watchForUpdates(currentVersion: "0.19.2", canInstall: true, http: FakeHTTPClient([.success(.status(500))]))
        await updates.check(quietly: true)
        try expectEqual(updates.state, .idle)
        try expectEqual(updates.row().summary.state, L("update.couldNotCheck"))
    }

    await run.test("a copy with nothing to replace says so and offers nothing") {
        let deck = Deck(cards: [])
        let updates = deck.runtime.watchForUpdates(currentVersion: nil, canInstall: false, http: FakeHTTPClient([]))
        try expect(!updates.isSupported)
        try expectEqual(updates.row().summary.state, L("update.notFromBundle"))
        try expect(!updates.row().isEnabled)
    }

    run.section("Updates - installing")

    await run.test("an install waits while a card is mid-command, and says which") {
        let project = LocalProject(id: "busy-\(UUID().uuidString)", title: "Busy", folder: FileManager.default.temporaryDirectory.path, startCommand: "npm run dev")
        let files = ProjectRuntimeFiles(directory: FileManager.default.temporaryDirectory.appendingPathComponent("devdeck-update-\(UUID().uuidString)"))
        let deck = Deck(cards: [project.cardID], localProjects: [project], projectFiles: files)
        let updates = deck.runtime.watchForUpdates(currentVersion: "0.19.2", canInstall: true, http: FakeHTTPClient([.success(.json(release("v9.0")))]))
        var handedOver: AvailableUpdate?
        updates.onInstall = { handedOver = $0 }
        await updates.check(quietly: false)
        deck.runtime.perform(.project(project.cardID, .start))
        updates.install()
        try expectEqual(updates.waitingFor, "Busy")
        try expectNil(handedOver, "nothing is replaced under a running command")
        try expectEqual(updates.row().summary.state, L("update.waits", "9.0"))
        await deck.runtime.settle()
        updates.install()
        try expectEqual(handedOver?.version.description, "9.0")
        guard case .downloading = updates.state else {
            throw TestFailure(message: "the install should be under way: \(updates.state)", file: #filePath, line: #line)
        }
    }

    await run.test("the installer's progress and failure are on the row") {
        let deck = Deck(cards: [])
        let updates = deck.runtime.watchForUpdates(currentVersion: "0.19.2", canInstall: true, http: FakeHTTPClient([.success(.json(release("v9.0")))]))
        updates.onInstall = { _ in }
        await updates.check(quietly: false)
        updates.install()
        updates.downloaded(0.42)
        try expectEqual(updates.row().summary.detail, "42%")
        updates.failed("disk full")
        try expectEqual(updates.row().summary.detail, "disk full")
        try expectEqual(updates.row().button, L("update.button.retry"))
    }
}
