import AppKit
import ArcKit
import DevDeckCore
import DevDeckUI
import SwiftUI
import Foundation
import GitHubKit
import GitLabKit
import TestHarness

func runPresentationTests(_ run: TestRun) async {
    run.section("Cards - expanding")

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
        try expectEqual(collapsed, 127 + 28 * 3 + 22, "three rows plus the expander")
        try expectEqual(expanded, 127 + 28 * 8 + 22)
        try expect(expanded > collapsed)

        try expectEqual(CardMetrics.height(base: 127, total: 2, isExpanded: false), 127 + 28 * 2,
                        "no expander, no extra height")
    }

    run.section("Cards - tidying the deck")

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

    run.section("Cards - packing a column")

    await run.test("cards share a column when they overlap, not when they are merely near") {
        let card = CGRect(x: 100, y: 0, width: 352, height: 200)
        try expect(DeckLayout.isSameColumn(card, CGRect(x: 100, y: 400, width: 352, height: 180)),
                   "the same x is the same column")
        try expect(DeckLayout.isSameColumn(card, CGRect(x: 108, y: 400, width: 352, height: 180)),
                   "and so is one dragged into place by eye, a few points out")
        try expect(!DeckLayout.isSameColumn(card, CGRect(x: 300, y: 400, width: 352, height: 180)),
                   "half a card apart is two columns, not one")
        try expect(!DeckLayout.isSameColumn(card, CGRect(x: 460, y: 0, width: 352, height: 200)),
                   "and a card beside it is certainly not in it")
    }

    await run.test("a new card joins the deck under the shortest column") {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let size = CGSize(width: 352, height: 110)
        // Two columns, the right one shorter. A new card belongs at the bottom of that one, not
        // on top of it, which is what "under the lowest panel of the deck" used to mean.
        let left = [CGRect(x: 24, y: 700, width: 352, height: 216), CGRect(x: 24, y: 400, width: 352, height: 280)]
        let right = [CGRect(x: 388, y: 700, width: 352, height: 216)]

        let spot = try expectNotNil(
            DeckLayout.nextSpot(size: size, among: left + right, screen: screen, gap: 12),
            "spot"
        )
        try expectEqual(spot.x, 388, "the shorter column")
        try expectEqual(spot.y, 700 - 12 - 110, "directly under its lowest card")
    }

    await run.test("a deck with no room starts a column beside itself") {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 400)
        let full = [CGRect(x: 24, y: 20, width: 352, height: 360)]
        let spot = try expectNotNil(
            DeckLayout.nextSpot(size: CGSize(width: 352, height: 110), among: full, screen: screen, gap: 12),
            "spot"
        )
        try expectEqual(spot.x, 24 + 352 + 12, "beside it, on the side with room")
        try expectEqual(spot.y, 380 - 110, "and from the top of the deck")
    }

    await run.test("the first card of all has no deck to join") {
        try expectNil(DeckLayout.nextSpot(
            size: CGSize(width: 352, height: 110),
            among: [],
            screen: CGRect(x: 0, y: 0, width: 1512, height: 950),
            gap: 12
        ))
    }

    await run.test("packing closes the gaps and keeps the order it was given") {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let sizes = [CGSize(width: 352, height: 200), CGSize(width: 352, height: 44), CGSize(width: 352, height: 180)]
        let points = DeckLayout.pack(
            sizes: sizes,
            anchorTopLeft: CGPoint(x: 24, y: 900),
            screen: screen,
            gap: 12
        )
        try expectEqual(points[0], CGPoint(x: 24, y: 900), "the anchor does not move")
        try expectEqual(points[1].y, 900 - 200 - 12, "the next one closes up under it")
        try expectEqual(points[2].y, 900 - 200 - 12 - 44 - 12)
        try expect(points.allSatisfy { $0.x == 24 }, "and the column stays a column")
    }

    await run.test("packing never sends a card to another column, however full this one is") {
        // Six full cards do not fit a laptop screen. Tidy would start a second column; packing
        // runs by itself, and a card that jumps sideways because its neighbour grew a line is
        // worse than the overlap it was avoiding.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 400)
        let sizes = Array(repeating: CGSize(width: 352, height: 200), count: 4)
        let points = DeckLayout.pack(sizes: sizes, anchorTopLeft: CGPoint(x: 24, y: 390), screen: screen, gap: 12)
        try expect(points.allSatisfy { $0.x == 24 }, "one column, whatever it costs")
        try expect(points.allSatisfy { $0.y - 200 >= screen.minY - 0.5 },
                   "and nothing is pushed off the bottom, where it could not be grabbed")
    }

    run.section("Panels - a placement belongs to a display")

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

    await run.test("parking is not saved, but arranging a parked card is") {
        let parked = PanelPlacement(displayID: "external", offset: CGPoint(x: 2200, y: 40))
        try expect(
            !PanelPlacement.shouldRecord(existing: parked, userMoved: false, displays: [laptop]),
            "the deck putting a card somewhere visible is not the user moving house"
        )
        try expect(
            PanelPlacement.shouldRecord(existing: parked, userMoved: true, displays: [laptop]),
            "but tidying or dragging it there is a decision, and the old placement gives way"
        )
        try expect(
            PanelPlacement.shouldRecord(existing: parked, userMoved: false, displays: [laptop, external]),
            "with its own display back, an ordinary move is recorded as usual"
        )
        try expect(
            PanelPlacement.shouldRecord(existing: nil, userMoved: false, displays: [laptop]),
            "a card that has never been placed records wherever it lands"
        )
        try expect(parked.isHome(on: [external]))
        try expect(!parked.isHome(on: [laptop]))
    }

    await run.test("a placement survives a round trip through the preferences string") {
        let placement = PanelPlacement(displayID: "37D8832A-2D66-02CA-B9F7-8F30A301B230", offset: CGPoint(x: 24, y: 25.5))
        let restored = try expectNotNil(PanelPlacement(storage: placement.storage), "restored")
        try expectEqual(restored, placement)
        try expectNil(PanelPlacement(storage: "{24, 932}"), "a global point from an older build is not a placement")
        try expectNil(PanelPlacement(storage: "|1|2"), "and neither is a nameless display")
    }

    run.section("Cards - chips wrap, and the panel knows by how much")

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
        try expectEqual(CardChipFlow.height(lineCount: 1), 11 + 22)
        try expectEqual(CardChipFlow.height(lineCount: 2), 11 + 44 + 5, "one gap between two lines")
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
        // Same chips, same branch - the three cards must come out the same height, or one of
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

    run.section("The menu-bar icon")

    await run.test("somebody waiting on you outranks your own queue being stuck") {
        // The old icon went red for either, plus a third thing, and said which only in a
        // tooltip. One of the two costs another person time; that is the one worth colour.
        let waiting = DeckStatusSummary(tooltip: "", blockedCount: 3, waitingCount: 1)
        try expectEqual(waiting.state, .waiting, "a person is waiting, whatever else is true")
        try expectEqual(DeckStatusSummary(tooltip: "", blockedCount: 2, waitingCount: 0).state, .blocked)
        try expectEqual(DeckStatusSummary(tooltip: "", blockedCount: 0, waitingCount: 0).state, .calm)
    }

    await run.test("the reason is a sentence, so the menu can answer why") {
        try expectEqual(
            DeckStatusSummary(tooltip: "", blockedCount: 2, waitingCount: 1).reason,
            "1 waiting on you, 2 of yours blocked",
            "the person first, since that is what the colour is about"
        )
        try expectEqual(DeckStatusSummary(tooltip: "", blockedCount: 2, waitingCount: 0).reason,
                        "2 of yours blocked")
        try expectNil(DeckStatusSummary(tooltip: "", blockedCount: 0, waitingCount: 0).reason,
                      "and nothing to say when nothing wants you")
    }

    await run.test("only the state that carries red opts out of being a template") {
        try expect(DeckIcon.statusItemImage(.calm).isTemplate)
        try expect(DeckIcon.statusItemImage(.blocked).isTemplate,
                   "blocked is the bar's own ink, so the bar keeps tinting it")
        try expect(!DeckIcon.statusItemImage(.waiting).isTemplate, "a template image has no colour")
        try expectEqual(DeckIcon.statusItemImage(.calm).size, DeckIcon.size,
                        "every state occupies the same slot, so the tray does not reshuffle")
        try expectEqual(DeckIcon.statusItemImage(.waiting).size, DeckIcon.size)
    }

    await run.test("the app icon is drawn at every size rather than resampled from one") {
        for size in [16.0, 32.0, 128.0, 1024.0] {
            let image = AppIcon.image(size: size)
            try expectEqual(image.size.width, size)
            try expectEqual(image.size.height, size)
        }
        // The squircle is a superellipse, not a rounded rectangle: at the halfway point of a
        // side it is still flat, which a circular corner is not.
        let path = AppIcon.squirclePath(center: CGPoint(x: 512, y: 512), radius: 412)
        try expectEqual(path.elementCount, 243, "241 sampled points and a close")
        try expect(path.bounds.width <= 824.5 && path.bounds.width >= 823.5,
                   "824 of 1024, the modern macOS inset")
    }

    run.section("Arrangements")

    func placed(_ card: String, visible: Bool = true, collapsed: Bool = false, at spot: String? = "d|0|0") -> DeckArrangement.Placed {
        DeckArrangement.Placed(card: card, isVisible: visible, isCollapsed: collapsed, placement: spot)
    }

    await run.test("an arrangement is what is on the deck, folded how, and where") {
        let saved = DeckArrangement(name: "Il Tempo day", cards: [
            placed("arc.project.tempo"),
            placed("arc.project.giornale", collapsed: true),
        ])
        try expect(saved.matches([placed("arc.project.tempo"), placed("arc.project.giornale", collapsed: true)]))
        try expect(!saved.matches([placed("arc.project.tempo"), placed("arc.project.giornale")]),
                   "unfolding a card is a different arrangement")
        try expect(!saved.matches([placed("arc.project.tempo")]), "and so is hiding one")
        try expect(!saved.matches([
            placed("arc.project.tempo", at: "d|400|0"),
            placed("arc.project.giornale", collapsed: true),
        ]), "and so is dragging one somewhere else")
    }

    await run.test("saving over a name replaces it rather than growing a twin") {
        let first = DeckArrangement(name: "Morning", cards: [placed("github.pullRequests")])
        let second = DeckArrangement(name: "Morning", cards: [placed("github.inbox")])
        let list = DeckArrangements.adding(second, to: DeckArrangements.adding(first, to: []))
        try expectEqual(list.count, 1)
        try expectEqual(list[0].cards.map(\.card), ["github.inbox"])
    }

    await run.test("the list has a ceiling, and forgetting one is by name") {
        var list: [DeckArrangement] = []
        for index in 1...(DeckArrangements.limit + 3) {
            list = DeckArrangements.adding(DeckArrangement(name: "L\(index)", cards: []), to: list)
        }
        try expectEqual(list.count, DeckArrangements.limit, "few enough that the menu stays a menu")
        try expectEqual(list.first?.name, "L4", "the oldest go")
        try expectEqual(DeckArrangements.removing("L5", from: list).count, DeckArrangements.limit - 1)
    }

    run.section("Being told")

    let review = DeckAlert(
        id: "review:1", kind: .reviewRequest, source: .gitlab, title: "Review requested",
        body: "acme/web!41 Drop the poller",
        url: URL(string: "https://git.acme.io/acme/web/-/merge_requests/41")!, accountID: "work"
    )
    let blocked = DeckAlert(
        id: "blocked:2:CI", kind: .blocked, source: .gitlab, title: "Pipeline failed",
        body: "acme/web!42 Rebase", url: URL(string: "https://git.acme.io")!, accountID: "work"
    )

    await run.test("the first answer after a launch is never announced") {
        // It is the state of the world as you left it. Announcing it means every restart tells
        // you about eight things you already knew, which is how notifications get turned off.
        try expect(NotificationDigest.newAlerts(from: [review, blocked], seen: [], isFirstPass: true).isEmpty)
        try expectEqual(
            NotificationDigest.newAlerts(from: [review, blocked], seen: [], isFirstPass: false).count,
            2
        )
    }

    await run.test("nothing is announced twice") {
        let fresh = NotificationDigest.newAlerts(
            from: [review, blocked],
            seen: ["review:1"],
            isFirstPass: false
        )
        try expectEqual(fresh.map(\.id), ["blocked:2:CI"])
    }

    await run.test("what was seen is remembered, and the memory has a floor and a ceiling") {
        let after = NotificationDigest.remembering(["a", "b"], in: ["b", "c"])
        try expectEqual(after, ["c", "a", "b"], "moved to the end rather than duplicated")

        let many = (1...NotificationDigest.memory + 50).map(String.init)
        let trimmed = NotificationDigest.remembering(many, in: [])
        try expectEqual(trimmed.count, NotificationDigest.memory)
        try expectEqual(trimmed.last, String(NotificationDigest.memory + 50), "the newest survive")
    }

    await run.test("a handful becomes one line rather than a wall of banners") {
        try expectNil(NotificationDigest.summary(for: [review, blocked]), "two are just two banners")
        let summary = try expectNotNil(
            NotificationDigest.summary(for: [review, review, blocked]),
            "summary"
        )
        try expectEqual(summary.body, "2 waiting for your review, 1 of yours blocked")
    }

    await run.test("only the two things worth interrupting somebody for become alerts") {
        let snapshot = MergeRequestsSnapshot(totalCount: 3, mergeRequests: [
            sampleRequest(id: "1", isReviewRequest: true, pipeline: .success),
            sampleRequest(id: "2", isReviewRequest: false, pipeline: .failed),
            sampleRequest(id: "3", isReviewRequest: false, pipeline: .success),
        ])
        try expectEqual(snapshot.alerts(includeBlocked: false).map(\.id), ["review:1"],
                        "a review request is somebody waiting on you")
        try expectEqual(snapshot.alerts(includeBlocked: true).map(\.kind), [.reviewRequest, .blocked],
                        "and a red pipeline of your own, when you asked for it")
        try expect(!snapshot.alerts(includeBlocked: true).contains { $0.id.contains(":3") },
                   "a merge request that is simply fine is not news")
    }

    await run.test("something broken, fixed and broken again is said twice") {
        let first = sampleRequest(id: "9", isReviewRequest: false, pipeline: .failed)
        let later = MergeRequestSummary(
            id: "9", iid: 9, title: "One", project: "acme/web",
            url: URL(string: "https://git.acme.io")!, isDraft: false, hasConflicts: true,
            updatedAt: Date(timeIntervalSince1970: 0), pipeline: .success,
            approvalsLeft: 0, unresolvedThreads: 0
        )
        let before = MergeRequestsSnapshot(totalCount: 1, mergeRequests: [first]).alerts(includeBlocked: true)
        let after = MergeRequestsSnapshot(totalCount: 1, mergeRequests: [later]).alerts(includeBlocked: true)
        try expect(before.first?.id != after.first?.id,
                   "the state is part of the identity, so the second failure is news again")
    }

    await run.test("a banner carries the service's own mark, not the app's") {
        // macOS puts the application icon on every notification and will not be talked out of
        // it. The attachment is the only place "who is asking" can be answered.
        for source in [DeckAlert.Source.github, .gitlab] {
            let url = try expectNotNil(NotificationArtwork.fileURL(for: source), "artwork")
            let data = try expectNotNil(try? Data(contentsOf: url), "png")
            try expect(data.count > 500, "a real drawing rather than an empty tile")
            try expectEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "and a PNG")
            let image = try expectNotNil(NSImage(contentsOf: url), "image")
            try expectEqual(image.size.width, 128)
        }
    }

    run.section("Cards - two sizes")

    await run.test("a collapsed card is one fixed row, whatever it used to hold") {
        let busy = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let quiet = ArcProject(id: "q", title: "Q", organization: "o", folder: "/tmp")
        let status = LocalStackStatus(state: .running, branch: "main")

        let one = ArcProjectCard.size(for: busy, status: status, isCollapsed: true)
        let two = ArcProjectCard.size(for: quiet, status: LocalStackStatus(state: .stopped), isCollapsed: true)
        try expectEqual(one.height, CollapsedCardMetrics.height, "44 points, and nothing to measure")
        try expectEqual(one.height, two.height, "the same for every card, however much it was holding")
        try expectEqual(one.width, CardMetrics.width, "the width does not change; the deck is still a column")

        let whole = ArcProjectCard.size(for: busy, status: status)
        try expect(whole.height > one.height * 3, "the saving is the point: 209 against 44")
    }

    await run.test("a list card collapses to the same row as a project card") {
        // It used to be the project cards only, so the menu item was there on a GitHub card and
        // did nothing at all - which is worse than not offering it.
        let empty = CardState<PullRequestsSnapshot>()
        try expectEqual(
            PullRequestsCard.size(for: empty, isExpanded: false, isCollapsed: true).height,
            CollapsedCardMetrics.height
        )
        try expectEqual(
            InboxCard.size(for: CardState<InboxSnapshot>(), isExpanded: false, isCollapsed: true).height,
            CollapsedCardMetrics.height
        )
        try expectEqual(ActionsCard.size(isCollapsed: true).height, CollapsedCardMetrics.height)
        try expectEqual(
            MergeRequestsCard.size(for: CardState<MergeRequestsSnapshot>(), isExpanded: false, isCollapsed: true).height,
            CollapsedCardMetrics.height
        )
        try expect(ActionsCard.size(isCollapsed: false).height > CollapsedCardMetrics.height)
    }

    await run.test("an open tray is not carried into a collapsed card") {
        let project = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let status = LocalStackStatus(state: .running)
        let logs = LogLines(lines: ["one", "two"], source: "docker logs x")
        try expectEqual(
            ArcProjectCard.size(for: project, status: status, logs: logs, isCollapsed: true).height,
            CollapsedCardMetrics.height,
            "six lines of log under a one-line card is not a card"
        )
    }

    await run.test("the collapsed panel is a different shape, not just a shorter one") {
        try expect(CollapsedCardMetrics.cornerRadius < DeckTheme.cornerRadius)
        try expect(
            CollapsedCardMetrics.cornerRadius * 2 < CollapsedCardMetrics.height,
            "a radius that meets itself in the middle draws a pill"
        )
    }

    run.section("Cards - the log tray")

    await run.test("a tray keeps the last lines and drops the noise between them") {
        let output = "starting\n\n\u{1B}[32mready\u{1B}[0m in 612 ms\r  \rGET / 200\nGET /admin 302\n"
        let lines = LogTail.lines(from: output, limit: 3)
        try expectEqual(lines, ["ready in 612 ms", "GET / 200", "GET /admin 302"],
                        "newest three, no colour escapes, no blanks")
        try expectEqual(LogTail.lines(from: "   \n\n"), [], "nothing but whitespace is nothing")
    }

    await run.test("progress drawn with carriage returns is not one enormous line") {
        // What `docker compose` and every npm progress bar do. Split on \r as well as \n or the
        // whole run arrives as a single unreadable ribbon.
        let output = "Pulling 10%\rPulling 60%\rPulling 100%\ndone"
        try expectEqual(LogTail.lines(from: output, limit: 2), ["Pulling 100%", "done"])
    }

    await run.test("escape stripping leaves ordinary brackets alone") {
        try expectEqual(LogTail.strippingEscapes("[web] \u{1B}[1;31merror\u{1B}[0m: no port"),
                        "[web] error: no port")
        try expectEqual(LogTail.strippingEscapes("plain"), "plain")
    }

    await run.test("the tray costs the card an honest number of points") {
        let empty = LogLines(detail: "nothing logged yet")
        try expectEqual(CardLogTray.height(for: nil), 0, "a closed tray costs nothing")
        try expectEqual(CardLogTray.height(for: empty), CardLogTray.height(lineCount: 1),
                        "an empty tray still says so on one line")
        try expect(CardLogTray.height(lineCount: 6) > CardLogTray.height(lineCount: 3))
        try expectEqual(CardLogTray.height(lineCount: 20), CardLogTray.height(lineCount: LogTail.lineLimit),
                        "and it never grows past what it draws")
    }

    await run.test("a card grows by exactly its tray") {
        let project = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let status = LocalStackStatus(state: .running, branch: "main")
        let logs = LogLines(lines: ["one", "two", "three"], source: "docker logs x")

        let closed = ArcProjectCard.size(for: project, status: status)
        let open = ArcProjectCard.size(for: project, status: status, logs: logs)
        try expectEqual(open.height - closed.height, CardLogTray.height(lineCount: 3),
                        "the panel and the card have to agree on this exactly")
    }

    run.section("Cards - the palette")

    await run.test("a chip wears its hue mixed back towards the text colour") {
        // The chips carry the only colour left in the meta block, so the mix has to keep the
        // hue recognisable while stopping five of them reading as a paint chart.
        let ink = try expectNotNil(NSColor(DeckTheme.chipInk(DeckTheme.green)).usingColorSpace(NSColorSpace.sRGB), "ink")
        let hue = try expectNotNil(NSColor(DeckTheme.green).usingColorSpace(NSColorSpace.sRGB), "hue")
        let text = try expectNotNil(NSColor(DeckTheme.value).usingColorSpace(NSColorSpace.sRGB), "text")

        try expect(ink.redComponent > hue.redComponent, "lighter than the hue on its own")
        try expect(ink.redComponent < text.redComponent, "but still not plain text")
        try expect(ink.greenComponent > ink.blueComponent, "and still green")
        try expect(
            abs(ink.redComponent - (hue.redComponent * 0.55 + text.redComponent * 0.45)) < 0.001,
            "mixed 55/45, which is the number the design settles on"
        )
    }

    await run.test("blending is a straight line between two colours") {
        func red(_ color: Color) throws -> Double {
            let resolved = try expectNotNil(NSColor(color).usingColorSpace(NSColorSpace.sRGB), "sRGB")
            return Double(resolved.redComponent)
        }
        try expectEqual(try red(DeckTheme.blend(DeckTheme.green, with: DeckTheme.value, amount: 1)),
                        try red(DeckTheme.green), "all of the first colour")
        try expectEqual(try red(DeckTheme.blend(DeckTheme.green, with: DeckTheme.value, amount: 0)),
                        try red(DeckTheme.value), "and none of it")
    }

    run.section("Cards - the control row")

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

    run.section("Accounts - stored shape")

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


private func sampleRequest(id: String, isReviewRequest: Bool, pipeline: PipelineState) -> MergeRequestSummary {
    MergeRequestSummary(
        id: id,
        iid: Int(id) ?? 1,
        title: "One",
        project: "acme/web",
        url: URL(string: "https://git.acme.io/acme/web/-/merge_requests/\(id)")!,
        isDraft: false,
        hasConflicts: false,
        updatedAt: Date(timeIntervalSince1970: 0),
        pipeline: pipeline,
        approvalsLeft: 0,
        unresolvedThreads: 0,
        isReviewRequest: isReviewRequest
    )
}
