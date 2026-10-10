import DevDeckCore
import DevDeckEngine
import GitHubKit
import DevDeckLocalization
import Foundation
import ProjectKit
import TestHarness

// Golden transcripts of the protocol a shell in another process speaks: intents in, as the
// shell would write them, and every event the session sends back, byte for byte. The same
// scenario must give the same bytes on the Mac and on Windows. See docs/engine-protocol.md.

/// One intent as a line of JSON, the way a shell writes it.
private func intent(_ id: Int, _ name: String, _ fields: String = "") -> Data {
    let rest = fields.isEmpty ? "" : "," + fields
    return Data(#"{"protocolVersion":2,"id":"\#(id)","intent":"\#(name)"\#(rest)}"#.utf8)
}

/// Two displays as Windows reports them: the laptop's work area under its taskbar, and a
/// monitor to its right.
private let displays = #""displays":[{"id":"laptop","frame":[0,0,1512,904],"isPrimary":true},{"id":"external","frame":[1512,0,2560,1400],"isPrimary":false}]"#

@MainActor
private func sessionScenario(_ name: String) async throws -> Data {
    let russian = name.hasSuffix("-ru")
    defer { Strings.use(.english, lookingIn: LocalizationResources.root) }
    var bytes = Data()
    let (runtime, _) = goldenRuntime()
    let session = DeckSession(
        runtime: runtime,
        clock: MutableDateProvider(now: RuntimeFixture.now),
        sleeper: InstantSleeper(),
        localizationRoot: LocalizationResources.root,
        runsLoops: false
    ) { bytes.append($0) }
    let feed = #""card":"project.feed""#

    // Before the session starts, and not an intent at all: both are answered, not ignored.
    session.handle(line: intent(1, "command", #""command":{"refreshNow":{}}"#))
    session.handle(line: Data("not json".utf8))

    // The deck's language is the system's, which the shell reports.
    session.handle(line: intent(2, "session.start", #""systemLanguage":"\#(russian ? "ru-RU" : "en-US")",\#(displays)"#))
    _ = await runtime.refreshOnce()
    await runtime.refreshLocalOnce()
    session.flush()

    // The shell drew the project card taller than the guess.
    session.handle(line: intent(3, "card.measured", #"\#(feed),"size":[352,209]"#))
    // Clicks come back as the commands the events carried.
    session.handle(line: intent(4, "command", #""command":{"toggleExpanded":{"_0":"github.pullRequests"}}"#))
    session.handle(line: intent(5, "command", #""command":{"openLink":{"_0":"https://example.invalid/pull/90","account":"work","service":"github"}}"#))
    session.handle(line: intent(6, "command", #""command":{"followAlert":{"_0":{"card":{"_0":"project.feed"}}}}"#))
    session.handle(line: intent(7, "logWindow.changed", #"\#(feed),"isOpen":true"#))
    await runtime.settle()
    session.flush()
    // A card taken off the deck: its panel closes and the menu ticks it off. (A folder effect is
    // not here: it is spelled the platform's way, which is the point of it, so the bytes differ.)
    session.handle(line: intent(8, "command", #""command":{"toggleCard":{"_0":"github.actions"}}"#))
    session.handle(line: intent(9, "command", #""command":{"toggleCollapsed":{"_0":"project.feed"}}"#))
    session.handle(line: intent(10, "command", #""command":{"toggleLock":{}}"#))

    // Dragged to the monitor, then the monitor goes: the drag was the system's shove.
    session.handle(line: intent(11, "card.moved", #"\#(feed),"frame":[2000,100,352,44]"#))
    session.handle(line: intent(12, "displays.changed", #""displays":[{"id":"laptop","frame":[0,0,1512,904],"isPrimary":true}]"#))
    session.handle(line: intent(13, "command", #""command":{"tidy":{}}"#))

    // Wrong shapes are named, not dropped.
    session.handle(line: intent(14, "card.measured", #"\#(feed),"size":[352]"#))
    session.handle(line: intent(15, "card.moved", #"\#(feed),"frame":[0,0,-1,10]"#))
    session.handle(line: intent(16, "teleport"))
    session.handle(line: intent(17, "logWindow.changed", #"\#(feed),"isOpen":false"#))
    session.handle(line: intent(18, "command", #""command":{"quit":{}}"#))
    return bytes
}

/// A settings request as the shell would put it on the wire.
private func settings(_ id: Int, _ request: DeckSettingsRequest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let body = String(decoding: try encoder.encode(request), as: UTF8.self)
    return intent(id, "settings", #""request":\#(body)"#)
}

private let release = """
{"tag_name":"v9.0","html_url":"https://github.com/shumer/DevDeck/releases/tag/v9.0","draft":false,"prerelease":false,"published_at":"2026-10-01T10:00:00Z","assets":[{"name":"DevDeck-9.0-1.zip","browser_download_url":"https://example.invalid/DevDeck.zip","size":2097152}]}
"""

/// The settings window and the update row over the wire: what a form reads, what it saves, the
/// checks behind its status lines, and an update from offer to failure.
@MainActor
private func settingsScenario(_ name: String) async throws -> Data {
    let russian = name.hasSuffix("-ru")
    defer { Strings.use(.english, lookingIn: LocalizationResources.root) }
    var bytes = Data()
    let (runtime, preferences) = goldenRuntime()
    preferences.notifiesUpdates = true
    let session = DeckSession(
        runtime: runtime,
        clock: MutableDateProvider(now: RuntimeFixture.now),
        sleeper: InstantSleeper(),
        localizationRoot: LocalizationResources.root,
        runsLoops: false
    ) { bytes.append($0) }
    session.handle(line: intent(1, "session.start", #""systemLanguage":"\#(russian ? "ru" : "en")",\#(displays)"#))
    session.watchForUpdates(currentVersion: "0.19.2", canInstall: true, http: FakeHTTPClient([.success(.json(release))]))
    session.flush()
    // What starting looks like is the other scenario's; this one starts from here.
    bytes.removeAll()

    let feed = try expectNotNil(runtime.localProject(forCard: CardID(rawValue: "project.feed")), "the fixture has a project")
    let work = GitHubAccount(id: "work", label: "Work")
    var model = runtime.preferencesModel
    model.isLocked = true
    model.language = russian ? .english : .russian

    // One at a time: a shell may have several in flight, but then the order of the answers is
    // the order they were ready in, which a transcript cannot pin.
    let requests: [DeckSettingsRequest] = [
        .list, .preferences, .localProject(id: "feed"), .detect(folder: nil), .checkLocalProject(feed),
        .testLocalProjectLink(feed), .ddevCandidates,
    ]
    for (index, request) in requests.enumerated() {
        session.handle(line: try settings(2 + index, request))
        await session.settle()
    }
    // A token is checked against the service and kept when it works; it never comes back.
    session.handle(line: try settings(9, .checkGitHubToken(work, typed: "")))
    await session.settle()
    session.handle(line: try settings(10, .removeLocalProject(id: "feed")))
    await session.settle()
    // The language changes under the deck: every card is said again in the other one.
    session.handle(line: try settings(11, .setPreferences(model)))
    await session.settle()

    // An update, from the check to a download that failed.
    session.handle(line: intent(12, "update.check"))
    await session.settle()
    session.handle(line: intent(13, "update.act"))
    await session.settle()
    session.handle(line: intent(14, "update.progress", #""fraction":0.5"#))
    session.handle(line: intent(15, "update.failed", #""reason":"disk full""#))

    session.handle(line: intent(16, "settings"))
    session.handle(line: intent(17, "update.progress", #""fraction":2"#))
    return bytes
}

@MainActor
func runSessionGoldenTests(_ run: TestRun) async {
    run.section("Golden protocol transcripts")
    NSTimeZone.default = TimeZone(identifier: "UTC")!
    for scenario in ["session-en", "session-ru", "session-settings-en", "session-settings-ru"] {
        await run.test(scenario) {
            let actual = scenario.hasPrefix("session-settings")
                ? try await settingsScenario(scenario)
                : try await sessionScenario(scenario)
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

    await run.test("every card model the session sends reads back as the same model") {
        let lines = try await sessionScenario("session-en").split(separator: 0x0A)
        var checked = 0
        for line in lines {
            guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["event"] as? String == "card.changed", let model = object["model"]
            else { continue }
            let data = try JSONSerialization.data(withJSONObject: model)
            _ = try JSONDecoder().decode(DeckCardModel.self, from: data)
            checked += 1
        }
        try expect(checked >= 8, "every kind of card was sent: \(checked)")
    }

    await run.test("a settings window gets every word it says, in the deck's language") {
        defer { Strings.use(.english, lookingIn: LocalizationResources.root) }
        Strings.use(.russian, lookingIn: LocalizationResources.root)
        let (runtime, _) = goldenRuntime()
        guard case .words(let russian) = await runtime.answer(.words) else {
            throw TestFailure(message: "words expected", file: #filePath, line: #line)
        }
        try expectEqual(russian["settings.deck.title"], "Дека")
        try expectEqual(russian["button.cancel"], L("button.cancel"))
        try expect(russian["settings.notifications.allow.detail.windows"]?.contains("Windows") == true)
        try expectNil(russian["card.asOf"], "a card's words are the model's, not the window's")
        try expect(russian.count > 150, "the whole window: \(russian.count)")
        Strings.use(.english, lookingIn: LocalizationResources.root)
        guard case .words(let english) = await runtime.answer(.words) else {
            throw TestFailure(message: "words expected", file: #filePath, line: #line)
        }
        try expectEqual(english["settings.deck.title"], "Deck")
        try expectEqual(Set(english.keys), Set(russian.keys), "every language says everything English says")
    }

    await run.test("a folder is spelled the platform's way, and the place of a project is read from it") {
        #if os(Windows)
        try expectEqual(DeckSession.platformPath(URL(fileURLWithPath: #"C:\Users\demo\site"#)), #"C:\Users\demo\site"#)
        #else
        try expectEqual(DeckSession.platformPath(URL(fileURLWithPath: "/Users/demo/site")), "/Users/demo/site")
        #endif
        try expectEqual(ProjectLocation(folder: #"C:\Users\demo\site"#), .windows(path: #"C:\Users\demo\site"#))
        try expectEqual(ProjectLocation(folder: #"\\wsl.localhost\Ubuntu-24.04\home\demo\site"#), .wsl(distribution: "Ubuntu-24.04", path: "/home/demo/site"))
        try expectEqual(ProjectLocation(folder: "//wsl$/Debian/srv/app"), .wsl(distribution: "Debian", path: "/srv/app"))
        try expectEqual(ProjectLocation(folder: "/Users/demo/site"), .posix(path: "/Users/demo/site"))
        try expectNil(ProjectLocation(folder: ""))
        try expectEqual(ProjectLocation(folder: "C:/site")?.label, "Windows")
        try expectEqual(ProjectLocation(folder: "/srv/site")?.label, nil)
    }
}
