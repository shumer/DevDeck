import ArcKit
import DevDeckCore
import DevDeckUI
import Foundation
import GitHubKit
import TestHarness

func runPresentationTests(_ run: TestRun) async {
    run.section("Cards — expanding")

    await run.test("a collapsed card shows three rows at most") {
        try expectEqual(CardMetrics.rowCount(total: 8, isExpanded: false), 3)
        try expectEqual(CardMetrics.rowCount(total: 2, isExpanded: false), 2)
        try expectEqual(CardMetrics.rowCount(total: 0, isExpanded: false), 0)
    }

    await run.test("an expanded card shows everything up to the ceiling") {
        try expectEqual(CardMetrics.rowCount(total: 8, isExpanded: true), 8)
        try expectEqual(CardMetrics.rowCount(total: 40, isExpanded: true), CardMetrics.maxExpandedRows,
                        "a busy week must not produce a panel taller than the screen")
        try expectEqual(CardMetrics.hiddenWhenExpanded(total: 40), 40 - CardMetrics.maxExpandedRows)
        try expectEqual(CardMetrics.hiddenWhenExpanded(total: 8), 0)
    }

    await run.test("the expander only appears when it would do something") {
        try expect(!CardMetrics.showsExpander(total: 3))
        try expect(CardMetrics.showsExpander(total: 4))
    }

    await run.test("height follows the rows on screen") {
        let collapsed = CardMetrics.height(base: 127, total: 8, isExpanded: false)
        let expanded = CardMetrics.height(base: 127, total: 8, isExpanded: true)
        try expectEqual(collapsed, 127 + 27 * 3 + 22, "three rows plus the expander")
        try expectEqual(expanded, 127 + 27 * 8 + 22)
        try expect(expanded > collapsed)

        try expectEqual(CardMetrics.height(base: 127, total: 2, isExpanded: false), 127 + 27 * 2,
                        "no expander, no extra height")
    }

    run.section("Cards — Arc chip rows")

    await run.test("each row that has chips is paid for, and no more") {
        var project = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let stopped = LocalStackStatus(state: .stopped)

        project.links = [ArcLink(label: "PageBuilder", urlTemplate: "https://example.com", isEnabled: true)]
        let both = ArcProjectCard.size(for: project, status: stopped)

        project.links = []
        let localOnly = ArcProjectCard.size(for: project, status: stopped)
        try expect(both.height > localOnly.height, "the tooling row costs a row")

        // More links do not cost more: the rows are plain stacks and never wrap.
        project.links = ["PageBuilder", "Composer", "Deployer", "Site Service", "Delivery API"]
            .map { ArcLink(label: $0, urlTemplate: "https://example.com/\($0)", isEnabled: true) }
        try expectEqual(ArcProjectCard.size(for: project, status: stopped).height, both.height)
    }

    await run.test("the branch line adds its own height") {
        let project = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let without = ArcProjectCard.size(for: project, status: LocalStackStatus(state: .stopped))
        let with = ArcProjectCard.size(for: project, status: LocalStackStatus(state: .stopped, branch: "main"))
        try expectEqual(with.height - without.height, 18)
    }

    run.section("Browsers")

    await run.test("the default choice is the system browser") {
        try expect(BrowserChoice.systemDefault.isSystemDefault)
        try expect(!BrowserChoice(bundleIdentifier: "com.google.chrome").isSystemDefault)
    }

    await run.test("Chromium profiles are read with their human names") {
        let localState = """
        {
          "profile": {
            "info_cache": {
              "Profile 2": { "name": "Work" },
              "Default": { "name": "Personal" },
              "Profile 10": { "name": "Client" }
            }
          }
        }
        """
        let profiles = ChromiumProfiles.parse(localState: Data(localState.utf8))
        try expectEqual(profiles.map(\.directory), ["Default", "Profile 2", "Profile 10"],
                        "Default first, then natural order so the list does not reshuffle")
        try expectEqual(profiles.first?.name, "Personal")
    }

    await run.test("a profile with no name falls back to its directory") {
        let localState = """
        { "profile": { "info_cache": { "Profile 3": { "name": "" }, "Profile 4": {} } } }
        """
        let profiles = ChromiumProfiles.parse(localState: Data(localState.utf8))
        try expectEqual(profiles.map(\.name), ["Profile 3", "Profile 4"])
    }

    await run.test("anything unreadable yields no profiles rather than a crash") {
        try expect(ChromiumProfiles.parse(localState: Data("not json".utf8)).isEmpty)
        try expect(ChromiumProfiles.parse(localState: Data("{}".utf8)).isEmpty)
    }

    run.section("Accounts — stored shape")

    await run.test("an account stored before browsers existed still decodes") {
        let json = """
        { "id": "work", "label": "Work", "organizations": ["editoria"], "isEnabled": true,
          "apiBaseURL": "https://api.github.com" }
        """
        let account = try JSONDecoder().decode(GitHubAccount.self, from: Data(json.utf8))
        try expectEqual(account.id, "work")
        try expect(account.browser.isSystemDefault, "a missing browser means the default one")
    }

    await run.test("the browser choice survives a round trip") {
        let account = GitHubAccount(
            id: "work",
            label: "Work",
            browser: BrowserChoice(bundleIdentifier: "com.google.chrome", profileDirectory: "Profile 2")
        )
        let data = try JSONEncoder().encode([account])
        let restored = try JSONDecoder().decode([GitHubAccount].self, from: data)
        try expectEqual(restored.first?.browser.bundleIdentifier, "com.google.chrome")
        try expectEqual(restored.first?.browser.profileDirectory, "Profile 2")
    }
}
