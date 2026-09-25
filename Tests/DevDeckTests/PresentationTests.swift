import AppKit
import ArcKit
import DDEVKit
import DevDeckCore
import DevDeckUI
import SwiftUI
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit
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

    run.section("Panels - parking the deck")

    // The deck from the report: five cards in two columns on a 27-inch external, and the laptop
    // the only screen left when it is unplugged.
    let bigExternal = DisplayFrame(id: "external", visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415))
    let laptopAlone = DisplayFrame(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949))
    let folded = CGSize(width: 352, height: CollapsedCardMetrics.height)
    func parkedCard(_ name: String, _ x: Double, _ y: Double, on display: String = "external") -> DeckParking.Card {
        DeckParking.Card(
            id: CardID(rawValue: name),
            placement: PanelPlacement(displayID: display, offset: CGPoint(x: x, y: y)),
            size: folded
        )
    }
    // Given out of order on purpose: the layout reads the offsets, not the list.
    let reported = [
        parkedCard("inbox", 40, 560), parkedCard("actions", 40, 300), parkedCard("dmi", 415, 300),
        parkedCard("pulls", 40, 40), parkedCard("media24", 415, 40),
    ]
    func frames(_ points: [CardID: CGPoint], size: CGSize) -> [CGRect] {
        points.values.map { CGRect(x: $0.x, y: $0.y - size.height, width: size.width, height: size.height) }
    }
    func overlapping(_ rects: [CGRect]) -> Bool {
        for (index, first) in rects.enumerated() {
            for second in rects[(index + 1)...] where first.intersects(second) { return true }
        }
        return false
    }
    func topDown(_ points: [CardID: CGPoint], _ names: [String]) -> [String] {
        names.map { CardID(rawValue: $0) }
            .sorted { (points[$0]?.y ?? 0) > (points[$1]?.y ?? 0) }
            .map(\.rawValue)
    }

    await run.test("a parked deck is one column of rows, in reading order, at the side it stood on") {
        let points = DeckParking.layout(reported, on: laptopAlone, gap: 12)
        try expectEqual(points.count, 5)
        try expect(!overlapping(frames(points, size: folded)), "nothing lies on anything else")
        try expect(frames(points, size: folded).allSatisfy { laptopAlone.visibleFrame.contains($0) },
                   "and nothing hangs off the screen")
        try expect(points.values.allSatisfy { $0.x == 40 }, "one column, the same distance in from the left")
        try expectEqual(points[CardID(rawValue: "pulls")]?.y, 949 - 40, "the same distance down from the top")
        try expectEqual(
            topDown(points, reported.map(\.id.rawValue)),
            ["pulls", "actions", "inbox", "media24", "dmi"],
            "home's left column first, top to bottom, then the right one"
        )
    }

    await run.test("a deck on the right of a big display stays on the right of a small one") {
        let points = DeckParking.layout(
            [parkedCard("a", 2200, 40), parkedCard("b", 2200, 300)],
            on: laptopAlone,
            gap: 12
        )
        try expect(points.values.allSatisfy { $0.x == 1512 - 352 }, "against the right edge, not off it")
    }

    await run.test("a deck too tall for the screen wraps into a second column rather than piling up") {
        let many = (0..<30).map { parkedCard("card-\($0)", 40, Double(40 + $0 * 260)) }
        let points = DeckParking.layout(many, on: laptopAlone, gap: 12)
        let rects = frames(points, size: folded)
        try expectEqual(points.count, 30)
        try expect(!overlapping(rects))
        try expect(rects.allSatisfy { laptopAlone.visibleFrame.contains($0) })
        try expectEqual(Set(points.values.map(\.x)).count, 2, "two columns")
    }

    await run.test("the plan takes every card home the moment its display is back, exactly") {
        let atHome = DeckParking.plan(reported, displays: [bigExternal, laptopAlone], fallback: laptopAlone, gap: 12)
        try expectEqual(atHome.home.count, 5)
        try expect(atHome.parked.isEmpty)
        try expectEqual(atHome.home[CardID(rawValue: "dmi")], CGPoint(x: 415, y: 1415 - 300))

        let away = DeckParking.plan(reported, displays: [laptopAlone], fallback: laptopAlone, gap: 12)
        try expect(away.home.isEmpty, "nothing is home while the external is unplugged")
        try expectEqual(away.parked.count, 5)
        try expectEqual(
            away.parked,
            DeckParking.plan(reported.reversed(), displays: [laptopAlone], fallback: laptopAlone, gap: 12).parked,
            "the parked column does not depend on the order the cards come in"
        )

        let back = DeckParking.plan(reported, displays: [bigExternal, laptopAlone], fallback: laptopAlone, gap: 12)
        try expectEqual(back, atHome, "the placements were never touched, so home is where it was")
    }

    await run.test("a card whose display is here stays home while the others are parked") {
        let mixed = reported + [parkedCard("load", 24, 25, on: "laptop")]
        let plan = DeckParking.plan(mixed, displays: [laptopAlone], fallback: laptopAlone, gap: 12)
        try expectEqual(plan.home[CardID(rawValue: "load")], CGPoint(x: 24, y: 949 - 25))
        try expectEqual(plan.parked.count, 5)
    }

    await run.test("the window server's shove is not a drag") {
        let a = CardID(rawValue: "a"), b = CardID(rawValue: "b")
        var moves = PendingMoves(quietPeriod: 0.15)
        // The timeline the probe recorded: two moves, then the screens changed 8 ms later.
        moves.moved(a, at: 10.000)
        moves.moved(b, at: 10.003)
        try expectEqual(moves.settled(at: 10.007), [], "nothing is believed yet")
        try expectEqual(Set(moves.screensChanged()), Set([a, b]), "both moves were the window server's")
        try expect(moves.isEmpty)
        try expectNil(moves.nextDue)
    }

    await run.test("a move the screens keep quiet after is the user's") {
        let a = CardID(rawValue: "a")
        var moves = PendingMoves(quietPeriod: 0.15)
        moves.moved(a, at: 20)
        try expectEqual(moves.nextDue, 20.15)
        try expectEqual(moves.settled(at: 20.1), [], "not yet")
        try expectEqual(moves.settled(at: 20.15), [a], "150 ms of quiet and it counts")
        try expect(moves.isEmpty)

        // A drag is a hundred moves and one save.
        for step in 0..<20 { moves.moved(a, at: 30 + Double(step) * 0.016) }
        try expectEqual(moves.settled(at: 30.4), [], "still dragging")
        try expectEqual(moves.settled(at: 30.46), [a])

        // Dragging a parked card after the screens changed is a decision like any other.
        moves.moved(a, at: 40)
        moves.screensChanged()
        moves.moved(a, at: 41)
        try expectEqual(moves.settled(at: 41.2), [a])
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

    await run.test("two groups share a line only if the second one fits on it whole") {
        // The real row: two hosted tools and the two local ones, on a card 324 points wide.
        // Squeezing one environment up beside the tools is what put `Local site` with the hosted
        // PageBuilder and `Local PageBuilder` alone underneath it.
        let tools = [104.0, 92.0]
        let environments = [90.0, 135.0]
        let grouped = CardChipFlow.groupedWidths(tools: tools, environments: environments, available: 324)
        try expectEqual(grouped.breakBefore, 2, "the divider becomes the break")
        try expectEqual(grouped.widths, tools + environments,
                        "and stops being drawn: a separator between two lines is a tick in the margin")
        try expectEqual(
            CardChipFlow.lineCount(widths: grouped.widths, available: 324, breakBefore: grouped.breakBefore),
            2,
            "and it costs nothing: the line was going to happen anyway"
        )
    }

    await run.test("groups that fit side by side are left alone") {
        let grouped = CardChipFlow.groupedWidths(tools: [60], environments: [70, 60], available: 324)
        try expectNil(grouped.breakBefore, "a break here would spend a line to say nothing")
        try expectEqual(grouped.widths.count, 4, "so the divider is drawn, which is its whole job")
        try expectEqual(CardChipFlow.lineCount(widths: grouped.widths, available: 324), 1)
    }

    await run.test("a group too wide for a line of its own is not worth breaking for") {
        // Four environments that wrap however they are placed. Breaking at the divider would
        // spend a third line on a block that was always going to need two.
        let grouped = CardChipFlow.groupedWidths(
            tools: [80],
            environments: [120, 120, 120, 120],
            available: 324
        )
        try expectNil(grouped.breakBefore)
        try expectEqual(CardChipFlow.lineCount(widths: grouped.widths, available: 324), 3,
                        "three lines either way, and a break would have made it four")
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

    await run.test("the icon wears the most urgent tier that lights it") {
        try expectEqual(DeckIconState(tier: .waiting), .waiting, "a person is waiting, whatever else is true")
        try expectEqual(DeckIconState(tier: .needsFixing), .needsFixing)
        try expectEqual(DeckIconState(tier: .stuck), .stuck)
        try expectEqual(DeckIconState(tier: .goodToKnow), .calm, "good to know is never a badge")
        try expectEqual(DeckIconState(tier: nil), .calm)
    }

    await run.test("only the state that carries red opts out of being a template") {
        try expect(DeckIcon.statusItemImage(.calm).isTemplate)
        try expect(DeckIcon.statusItemImage(.stuck).isTemplate,
                   "the ring is the bar's own ink, so the bar keeps tinting it")
        try expect(DeckIcon.statusItemImage(.needsFixing).isTemplate)
        try expect(!DeckIcon.statusItemImage(.waiting).isTemplate, "a template image has no colour")
        try expectEqual(DeckIcon.statusItemImage(.calm).size, DeckIcon.size,
                        "every state occupies the same slot, so the tray does not reshuffle")
        try expectEqual(DeckIcon.statusItemImage(.waiting).size, DeckIcon.size)
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

    run.section("One bad answer is not news")

    await run.test("a card does not flip on a single failed poll") {
        var settler = StateSettler()
        // Up, and the poll misses once: the card keeps saying up.
        try expect(!settler.shouldApply(isGood: false, wasGood: true, for: "arc.tempo"))
        // It misses twice: now it is a fact.
        try expect(settler.shouldApply(isGood: false, wasGood: true, for: "arc.tempo"))
    }

    await run.test("good news is believed at once, and it clears the count") {
        var settler = StateSettler()
        try expect(!settler.shouldApply(isGood: false, wasGood: true, for: "a"))
        try expect(settler.shouldApply(isGood: true, wasGood: false, for: "a"),
                   "nobody was ever annoyed by a card that noticed something came up")
        try expect(!settler.shouldApply(isGood: false, wasGood: true, for: "a"),
                   "and the miss before it does not count towards the next one")
    }

    await run.test("nothing is held back when the card is already showing bad news") {
        var settler = StateSettler()
        try expect(settler.shouldApply(isGood: false, wasGood: false, for: "a"),
                   "including the very first answer about anything")
    }

    await run.test("things are counted apart from each other") {
        var settler = StateSettler()
        try expect(!settler.shouldApply(isGood: false, wasGood: true, for: "arc.tempo"))
        try expect(!settler.shouldApply(isGood: false, wasGood: true, for: "ddev.shop"),
                   "one project missing a poll says nothing about another")
    }

    await run.test("pressing a button is a decision, not a poll") {
        var settler = StateSettler()
        try expect(!settler.shouldApply(isGood: false, wasGood: true, for: "arc.tempo"))
        settler.reset("arc.tempo")
        try expect(!settler.shouldApply(isGood: false, wasGood: true, for: "arc.tempo"),
                   "the count starts again, so a stop shows immediately and is not confirmed by a stale miss")
    }

    run.section("Being told")

    let review = DeckAlert(
        id: "review:1", kind: .reviewRequest, source: .gitlab, title: "Your review is requested",
        subtitle: "acme/web !41", body: "Drop the poller. Click to open it.", subject: "Drop the poller",
        target: .url(URL(string: "https://git.acme.io/acme/web/-/merge_requests/41")!, account: "work"),
        isQuiet: false
    )
    let blocked = DeckAlert(
        id: "blocked:2:CF", kind: .blocked, source: .gitlab, title: "Pipeline failed on your merge request",
        subtitle: "acme/web !42", body: "Rebase. Click to see the failed jobs.", subject: "Rebase",
        target: .url(URL(string: "https://git.acme.io")!, account: "work"),
        isQuiet: true
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
        try expectEqual(fresh.map(\.id), ["blocked:2:CF"])
    }

    await run.test("what was seen is remembered, and the memory has a floor and a ceiling") {
        let after = NotificationDigest.remembering(["a", "b"], in: ["b", "c"])
        try expectEqual(after, ["c", "a", "b"], "moved to the end rather than duplicated")

        let many = (1...NotificationDigest.memory + 50).map(String.init)
        let trimmed = NotificationDigest.remembering(many, in: [])
        try expectEqual(trimmed.count, NotificationDigest.memory)
        try expectEqual(trimmed.last, String(NotificationDigest.memory + 50), "the newest survive")
    }

    await run.test("a handful becomes one line that counts them by kind and names them") {
        try expectNil(NotificationDigest.summary(for: [review, blocked]), "two are just two banners")
        let summary = try expectNotNil(
            NotificationDigest.summary(for: [review, review, blocked]),
            "summary"
        )
        try expectEqual(summary.title, "2 reviews waiting, 1 stuck")
        try expectEqual(summary.body, "Drop the poller, Drop the poller and 1 more. Click to see them in the menu.")
    }

    await run.test("only the two things worth interrupting somebody for become merge request banners") {
        let snapshot = MergeRequestsSnapshot(totalCount: 3, mergeRequests: [
            sampleRequest(id: "1", isReviewRequest: true, pipeline: .success),
            sampleRequest(id: "2", isReviewRequest: false, pipeline: .failed),
            sampleRequest(id: "3", isReviewRequest: false, pipeline: .success),
        ])
        let alerts = GitLabAttention.alerts(mergeRequests: snapshot, labels: [:])
        try expectEqual(alerts.map(\.kind), [.reviewRequest, .blocked],
                        "a review request is somebody waiting on you, a red pipeline of yours is stuck work")
        try expect(!alerts.contains { $0.id.contains(":3") }, "a merge request that is simply fine is not news")
        try expect(!alerts[0].isQuiet, "a person waiting is worth a sound")
        try expect(alerts[1].isQuiet, "your own stuck work is worth a banner and no more")
    }

    await run.test("something broken, fixed and broken again is said twice") {
        let first = sampleRequest(id: "9", isReviewRequest: false, pipeline: .failed)
        let later = MergeRequestSummary(
            id: "9", iid: 9, title: "One", project: "acme/web",
            url: URL(string: "https://git.acme.io")!, isDraft: false, hasConflicts: true,
            updatedAt: Date(timeIntervalSince1970: 0), pipeline: .success,
            approvalsLeft: 0, unresolvedThreads: 0
        )
        let before = GitLabAttention.alerts(mergeRequests: MergeRequestsSnapshot(totalCount: 1, mergeRequests: [first]), labels: [:])
        let after = GitLabAttention.alerts(mergeRequests: MergeRequestsSnapshot(totalCount: 1, mergeRequests: [later]), labels: [:])
        try expect(before.first?.id != after.first?.id,
                   "the state is part of the identity, so the second failure is news again")
    }

    await run.test("a banner carries the service's own mark, not the app's") {
        // macOS puts the application icon on every notification and will not be talked out of
        // it. The attachment is the only place "who is asking" can be answered.
        for source in [DeckAlert.Source.github, .gitlab, .arc, .ddev, .docker, .project] {
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

    await run.test("a folded project keeps its controls, and drops the note to fit them") {
        let project = ArcProject(id: "p", title: "Libero", organization: "acme", folder: "/tmp")
        // A view is main-actor work even when all that is asked of it is arithmetic, so the
        // answers are taken over there and compared here.
        let (running, showsNote, stopped) = await MainActor.run {
            let up = ArcProjectCard(project: project, status: LocalStackStatus(state: .running, containers: 10))
            let down = ArcProjectCard(project: project, status: LocalStackStatus(state: .stopped))
            return (up.collapsedActionTitles, up.showsCollapsedNote, down.collapsedActionTitles)
        }

        // Four squares take 108 points of the 324 a row has. The note is what pays for them:
        // `10 containers` is 78, and the dot has already said running.
        try expectEqual(running, ["Stop", "Restart", "Terminal", "Open the site"])
        try expect(!showsNote, "the dot carries the state; the count is detail")

        // Stopped: no restart worth offering and nothing to open, so the row is two live
        // squares rather than four with two dead ones.
        try expectEqual(stopped, ["Start", "Terminal"])
    }

    await run.test("a collapsed card is one row, whatever else is open") {
        let project = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let status = LocalStackStatus(state: .running)
        try expectEqual(
            ArcProjectCard.size(for: project, status: status, isCollapsed: true).height,
            CollapsedCardMetrics.height,
            "a card folded to a row is a row"
        )
    }

    await run.test("the collapsed panel is a different shape, not just a shorter one") {
        try expect(CollapsedCardMetrics.cornerRadius < DeckTheme.cornerRadius)
        try expect(
            CollapsedCardMetrics.cornerRadius * 2 < CollapsedCardMetrics.height,
            "a radius that meets itself in the middle draws a pill"
        )
    }

    run.section("Cards - the log")

    await run.test("a log keeps the last lines and drops the noise between them") {
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

    await run.test("a window asks for a log worth reading, a card for a glance") {
        let output = (1...600).map { "line \($0)" }.joined(separator: "\n")
        let card = LogTail.lines(from: output)
        try expectEqual(card.count, LogTail.lineLimit, "the card takes what it can show")
        try expectEqual(card.last, "line 600", "and the newest is the last of them")

        let window = LogTail.lines(from: output, limit: LogTail.windowLineLimit)
        try expectEqual(window.count, LogTail.windowLineLimit, "the window takes a screenful and then some")
        try expectEqual(window.first, "line 201")
        try expectEqual(window.last, "line 600", "newest last, both times")
        try expect(LogTail.windowTailBytes > LogTail.fileTailBytes,
                   "and it reads enough of the file to have that many")
    }

    await run.test("a log on screen costs the card nothing") {
        // It used to be a tray inside the card, 120 points of it, and the column under the card
        // moved every time somebody opened one. The window is the whole point.
        let project = ArcProject(id: "p", title: "P", organization: "o", folder: "/tmp")
        let status = LocalStackStatus(state: .running, branch: "main")
        let height = ArcProjectCard.size(for: project, status: status).height
        // The tray was another 120 points on top of this, and the column under the card moved
        // every time one opened. Nothing a log does may change this number.
        try expect(height < 260, "a project card stays a card: \(height)")

        let ddev = DDEVProject(id: "d", name: "shop", folder: "/tmp")
        try expect(DDEVProjectCard.size(for: ddev, status: DDEVStatus(state: .running)).height < 260)

        let local = LocalProject(id: "l", title: "feed", folder: "/tmp", startCommand: "npm run dev")
        try expect(LocalProjectCard.size(for: local, status: LocalProjectStatus(state: .running)).height < 260)
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

    run.section("Cards - the header toggles")

    await run.test("a popover closed by a click elsewhere tells the card it closed") {
        // It used to be bound to a constant: the popover went away on the click, the card still
        // thought it was open, and the redraw that click caused opened it again. Pressing any
        // other button on the card brought the QR code back every time.
        var isShowing = true
        let toggle = CardHeaderToggle(
            id: "phone",
            isOn: true,
            systemImage: "qrcode",
            help: "open this on your phone",
            popover: AnyView(EmptyView()),
            dismiss: { isShowing = false }
        ) { isShowing.toggle() }

        let binding = toggle.presentation()
        try expect(binding.wrappedValue, "it is open")
        binding.wrappedValue = false
        try expect(!isShowing, "and the card was told it closed")
        // Twice, because a dismissal can arrive again before the card is drawn: closing has to
        // mean closed, not the other way round.
        binding.wrappedValue = false
        try expect(!isShowing, "a second dismissal leaves it closed")
    }

    await run.test("a toggle with nothing to show never presents anything") {
        var presses = 0
        let logs = CardHeaderToggle(isOn: true, help: "hide the log") { presses += 1 }
        let binding = logs.presentation()
        try expect(!binding.wrappedValue, "the log tray lives in the card, not in a popover")
        binding.wrappedValue = false
        try expectEqual(presses, 0, "so there is nothing to dismiss")
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

    await run.test("a row too full to fit gives up whole words rather than cutting every label") {
        let crowded = [
            CardAction("Start Docker", systemImage: "shippingbox.fill", isProminent: true),
            CardAction("Restart", systemImage: "arrow.clockwise"),
            CardAction("Terminal", systemImage: "terminal"),
            CardAction("Folder", systemImage: "folder"),
            CardAction("Logs", systemImage: "doc.text"),
        ]
        let places = CardActionRow.layout(for: crowded)
        let total = places.map(\.width).reduce(0, +) + CardActionRow.spacing * Double(crowded.count - 1)
        try expect(total <= CardChromeMetrics.contentWidth + 0.5, "it fits, whatever it costs")
        try expect(places.allSatisfy { $0.width > 30 }, "and nothing collapses")
        try expect(!places.contains { $0.showsLabel && $0.width < 44 }, "a word that stayed is a word you can read")
        try expect(places[0].showsLabel, "the action the card is offering keeps its word")
        try expect(!places[4].showsLabel, "the ones it can do without are the quiet ones, from the right")
    }

    await run.test("a translation that does not fit costs the words, not the row") {
        // The Russian labels: four of them need more than the card is wide, where the English
        // four fit with room to spare.
        let english = [
            CardAction("Start", systemImage: "play.fill", isProminent: true),
            CardAction("Restart", systemImage: "arrow.clockwise"),
            CardAction("Terminal", systemImage: "terminal"),
            CardAction("Folder", systemImage: "folder"),
        ]
        try expect(CardActionRow.layout(for: english).allSatisfy(\.showsLabel), "English keeps all four")

        let russian = [
            CardAction("Запустить", systemImage: "play.fill", isProminent: true),
            CardAction("Перезапустить", systemImage: "arrow.clockwise"),
            CardAction("Терминал", systemImage: "terminal"),
            CardAction("Папка", systemImage: "folder"),
        ]
        let places = CardActionRow.layout(for: russian)
        let total = places.map(\.width).reduce(0, +) + CardActionRow.spacing * 3
        try expectEqual(total.rounded(), CardChromeMetrics.contentWidth.rounded(), "the row still fills the card")
        try expect(places[0].showsLabel, "the one you came for keeps its word")
        try expect(places.contains { !$0.showsLabel }, "and something gave its up")
    }

    run.section("Cards - Actions")

    await run.test("an empty Actions card says why it is empty, not that it is missing something") {
        // "no repos" read as a card nobody had set up. With no list of its own the card follows
        // the open pull requests, so empty means there are none, which is a quiet, normal state.
        try expectEqual(ActionsCard.quietReason(followsPullRequests: true), "no open PRs")
        try expect(ActionsCard.quietReason(followsPullRequests: true) != L("card.actions.noRepos"),
                   "the pill names the reason")
    }

    await run.test("a card with nothing run says what it watched, by name") {
        try expectEqual(ActionsCard.watchedNames(["acme/site", "acme/web", "other/api"]), "site, web and 1 more")
        try expectEqual(ActionsCard.watchedNames(["acme/site"]), "site")
        try expectEqual(LN("card.actions.quiet.title", 7), "No runs in the last 7 days")

        Strings.use(.russian, lookingIn: localisationRoot)
        try expectEqual(LN("card.actions.quiet.title", 7), "За 7 дней запусков не было")
        try expectEqual(LN("card.actions.quiet.title", 3), "За 3 дня запусков не было")
        try expectEqual(ActionsCard.watchedNames(["a/site", "a/web"]), "site и web")
        Strings.use(.english, lookingIn: localisationRoot)
    }

    await run.test("the footer says where the repositories came from") {
        try expectEqual(ActionsCard.watching(3, followsPullRequests: true), "3 repos from your PRs")
        try expectEqual(ActionsCard.watching(1, followsPullRequests: false), "1 repo from your list")

        Strings.use(.russian, lookingIn: localisationRoot)
        try expectEqual(ActionsCard.watching(2, followsPullRequests: true), "2 репозитория из ваших PR")
        try expectEqual(ActionsCard.watching(5, followsPullRequests: false), "5 репозиториев из вашего списка")
        Strings.use(.english, lookingIn: localisationRoot)
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
