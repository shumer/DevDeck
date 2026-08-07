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

    run.section("Cards — tidying the deck")

    // A real deck: the five cards on this machine, on the built-in display.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 957)
    let deck = [
        CGSize(width: 320, height: 222),
        CGSize(width: 320, height: 222),
        CGSize(width: 320, height: 215),
        CGSize(width: 320, height: 190),
        CGSize(width: 320, height: 215),
    ]

    await run.test("a column that would run off the bottom wraps into the next one") {
        let places = DeckLayout.tidy(
            sizes: deck,
            anchorTopLeft: CGPoint(x: 24, y: 940),
            screen: screen,
            gap: 12
        )
        try expectEqual(places.count, deck.count)
        try expectEqual(places[0], CGPoint(x: 24, y: 940), "the anchor does not move")
        try expectEqual(places[1], CGPoint(x: 24, y: 940 - 222 - 12))
        // Four cards and their gaps come to 885 points, and a fifth would end below zero.
        try expectEqual(places[4], CGPoint(x: 24 + 320 + 12, y: 940), "the fifth starts a new column")

        for (place, size) in zip(places, deck) {
            try expect(place.y - size.height >= screen.minY, "nothing may hang below the screen")
        }
    }

    await run.test("the columns grow towards the free side of the screen") {
        // Anchored against the right edge, the only way out is leftwards.
        let places = DeckLayout.tidy(
            sizes: deck,
            anchorTopLeft: CGPoint(x: 1512 - 320 - 24, y: 940),
            screen: screen,
            gap: 12
        )
        try expectEqual(places[4].x, 1512 - 320 - 24 - 320 - 12)
        try expect(places.allSatisfy { $0.x >= screen.minX })
    }

    await run.test("a deck that fits is simply closed up") {
        let places = DeckLayout.tidy(
            sizes: Array(deck.prefix(3)),
            anchorTopLeft: CGPoint(x: 100, y: 900),
            screen: screen,
            gap: 12
        )
        try expectEqual(places.map(\.x), [100, 100, 100], "one column is enough")
        try expectEqual(places.map(\.y), [900, 900 - 234, 900 - 234 - 234])
    }

    await run.test("a panel taller than the screen is placed rather than looped over") {
        let places = DeckLayout.tidy(
            sizes: [CGSize(width: 320, height: 2000), CGSize(width: 320, height: 200)],
            anchorTopLeft: CGPoint(x: 24, y: 940),
            screen: screen,
            gap: 12
        )
        try expectEqual(places.count, 2)
        try expectEqual(places[0], CGPoint(x: 24, y: 940), "it goes where it was going to go")
        try expectEqual(places[1].x, 24 + 320 + 12, "and the next one starts a column of its own")
        try expect(DeckLayout.tidy(sizes: [], anchorTopLeft: .zero, screen: screen, gap: 12).isEmpty)
    }

    run.section("Panels — a placement belongs to a display")

    // A laptop and an external, arranged with the external as the main display: the laptop's
    // screen sits below and to the left, which is where the numbers come from.
    let laptop = DisplayFrame(id: "laptop", visibleFrame: CGRect(x: 0, y: -982, width: 1512, height: 957))
    let external = DisplayFrame(id: "external", visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415))

    await run.test("a position is remembered against the display it is on") {
        let placement = try expectNotNil(
            PanelPlacement.from(
                topLeft: CGPoint(x: 24, y: -50),
                size: CGSize(width: 352, height: 200),
                displays: [external, laptop]
            ),
            "placement"
        )
        try expectEqual(placement.displayID, "laptop", "the card is on the laptop, not the external")
        try expectEqual(placement.offset, CGPoint(x: 24, y: 25), "24 in from the left, 25 down from the top")
        try expectEqual(placement.topLeft(on: [external, laptop]), CGPoint(x: 24, y: -50))
    }

    await run.test("the same offset survives the arrangement changing under it") {
        // Unplug the external: macOS makes the laptop the main display at the origin, so the
        // old global point (24, -50) now means somewhere off the bottom of it.
        let placement = PanelPlacement(displayID: "laptop", offset: CGPoint(x: 24, y: 25))
        let alone = DisplayFrame(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 957))
        try expectEqual(placement.topLeft(on: [alone]), CGPoint(x: 24, y: 932),
                        "the card is still 25 points below the top of the laptop screen")
    }

    await run.test("a card whose display is gone is parked, not moved house") {
        let placement = PanelPlacement(displayID: "external", offset: CGPoint(x: 2200, y: 40))
        try expectNil(placement.topLeft(on: [laptop]), "its display is not here")

        let parked = placement.topLeft(borrowing: laptop, size: CGSize(width: 352, height: 200))
        try expectEqual(parked.y, laptop.visibleFrame.maxY - 40, "the same distance from the top")
        try expectEqual(parked.x, laptop.visibleFrame.maxX - 352,
                        "and pulled back onto the screen rather than left off its right edge")
        // The placement itself is untouched, which is what takes the card home again.
        try expectEqual(placement.displayID, "external")
    }

    await run.test("a placement survives a round trip through the preferences string") {
        let placement = PanelPlacement(displayID: "37D8832A-2D66-02CA-B9F7-8F30A301B230", offset: CGPoint(x: 24, y: 25.5))
        let restored = try expectNotNil(PanelPlacement(storage: placement.storage), "restored")
        try expectEqual(restored, placement)
        try expectNil(PanelPlacement(storage: "{24, 932}"), "a global point from an older build is not a placement")
        try expectNil(PanelPlacement(storage: "|1|2"), "and neither is a nameless display")
    }

    run.section("Cards — chips wrap, and the panel knows by how much")

    await run.test("chips break onto a new line only when the line is full") {
        // Widths chosen against the real content width of 292 points.
        try expectEqual(CardChipFlow.lineCount(widths: [], available: 292), 0)
        try expectEqual(CardChipFlow.lineCount(widths: [100, 100], available: 292), 1)
        try expectEqual(CardChipFlow.lineCount(widths: [100, 100, 100], available: 292), 2,
                        "300 plus two gaps does not fit on one line")
        try expectEqual(CardChipFlow.lineCount(widths: [400], available: 292), 1,
                        "a chip wider than the card still gets a line rather than none")
    }

    await run.test("every chip line is paid for, and no more") {
        try expectEqual(CardChipFlow.height(lineCount: 0), 0, "no chips, no block")
        try expectEqual(CardChipFlow.height(lineCount: 1), 12 + 20)
        try expectEqual(CardChipFlow.height(lineCount: 2), 12 + 40 + 5, "one gap between two lines")
    }

    await run.test("a card grows by exactly one chip line when its chips wrap") {
        var project = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let stopped = LocalStackStatus(state: .stopped)

        project.links = [ArcLink(label: "PageBuilder", urlTemplate: "https://example.com", isEnabled: true)]
        let oneLine = ArcProjectCard.size(for: project, status: stopped)

        // Five tools plus the environments cannot share a 292-point line.
        project.links = ["PageBuilder", "Composer", "Deployer", "Site Service", "Delivery API"]
            .map { ArcLink(label: $0, urlTemplate: "https://example.com/\($0)", isEnabled: true) }
        let twoLines = ArcProjectCard.size(for: project, status: stopped)

        try expectEqual(twoLines.height - oneLine.height, CardChip.height + CardChipFlow.lineSpacing)
        try expectEqual(oneLine.width, CardMetrics.width, "the width never moves")
    }

    await run.test("the branch line adds its own height") {
        let project = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let without = ArcProjectCard.size(for: project, status: LocalStackStatus(state: .stopped))
        let with = ArcProjectCard.size(for: project, status: LocalStackStatus(state: .stopped, branch: "main"))
        try expectEqual(with.height - without.height, CardMetaBlock.branchHeight)
    }

    await run.test("the three project cards are built to the same measurements") {
        // Same chips, same branch — the three cards must come out the same height, or one of
        // them has quietly grown its own layout.
        let arc = ProjectCardMetrics.height(
            tools: ["Mailpit"], environments: ["Local site", "Prod"], hasBranch: true, hasMetaRow: true
        )
        try expectEqual(
            arc,
            12 + 14 + CardHeroRow.topPadding + CardHeroRow.height
                + CardMetaBlock.height(hasBranch: true, hasRow: true)
                + CardChipFlow.height(lineCount: 1)
                + CardActionRow.height + 12
        )
        try expect(arc < 210, "the redesign has to stay shorter than the 249 it replaced")
    }

    run.section("Cards — the control row")

    await run.test("every button gets the same air around its label") {
        // The real row, with the label that caused this: `Terminal` all but touched its border
        // while `Logs` sat in a field of space, because the four shared the width equally.
        let actions = [
            CardAction("Stop", systemImage: "power", isProminent: true),
            CardAction("Restart", systemImage: "arrow.clockwise"),
            CardAction("Logs", systemImage: "doc.text"),
            CardAction("Terminal", systemImage: "terminal"),
        ]
        let widths = CardActionRow.widths(for: actions)
        try expectEqual(widths.count, 4)

        // Padding is width minus contents, and it has to be the same on every quiet button.
        let padding = zip(widths.dropFirst(), ["Restart", "Logs", "Terminal"]).map { width, title in
            width - CardActionRow.contentWidth(of: CardAction(title, systemImage: "x"))
        }
        for value in padding {
            try expect(abs(value - padding[0]) < 0.01, "the same air on each: \(padding)")
            try expect(value >= CardActionRow.labelPadding * 2, "and enough of it")
        }
        try expect(widths[0] > widths[1], "the prominent one still leads")

        let total = widths.reduce(0, +) + CardActionRow.spacing * 3
        try expectEqual(total.rounded(), CardChromeMetrics.contentWidth.rounded(),
                        "the row fills the card exactly, so it lines up with everything above it")
    }

    await run.test("a row too full to fit shrinks in proportion rather than truncating one label") {
        let crowded = [
            CardAction("Start Docker", systemImage: "shippingbox.fill", isProminent: true),
            CardAction("Restart", systemImage: "arrow.clockwise"),
            CardAction("Terminal", systemImage: "terminal"),
            CardAction("Folder", systemImage: "folder"),
            CardAction("Logs", systemImage: "doc.text"),
        ]
        let widths = CardActionRow.widths(for: crowded)
        let total = widths.reduce(0, +) + CardActionRow.spacing * Double(crowded.count - 1)
        try expect(total <= CardChromeMetrics.contentWidth + 0.5, "it fits, whatever it costs")
        try expect(widths.allSatisfy { $0 > 30 }, "and nothing collapses")
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
