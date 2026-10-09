import DevDeckCore
import DevDeckEngine
import Foundation
import ProjectKit
import TestHarness

// Where panels go, decided in the engine and checked without a window: the placement keeps its
// own frames, and these tests drive it the way the shell does, including the unplugged monitor
// that used to scatter the deck.

private let laptop = DisplayFrame(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))
private let external = DisplayFrame(id: "external", visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1410))

/// A deck with a placement over it, displays that can be unplugged, and every card the same size.
@MainActor
private final class Desk {
    let deck: Deck
    var displays: [DisplayFrame]
    var main: DisplayFrame
    var size = CGSize(width: 352, height: 200)
    lazy var placement = deck.runtime.placePanels(
        measure: { [unowned self] _ in self.size },
        displays: { [unowned self] in DeckDisplays(screens: self.displays, main: self.main, fallback: self.main) }
    )

    init(projects: [LocalProject], displays: [DisplayFrame] = [laptop, external], main: DisplayFrame = laptop) {
        deck = Deck(cards: Set(projects.map(\.cardID)), localProjects: projects)
        self.displays = displays
        self.main = main
        // Only the projects: the built-in cards are on by default and would make a longer deck.
        let list = deck.runtime.cards
        for descriptor in list.catalog where !projects.map(\.cardID).contains(descriptor.id) {
            list.setEnabled(false, for: descriptor.id)
        }
    }

    /// What the shell would see after applying the changes: frames by card.
    var frames: [CardID: CGRect] { placement.frames }
}

private func projects(_ count: Int) -> [LocalProject] {
    (1...count).map { LocalProject(id: "place\($0)", title: "Place \($0)", folder: "/tmp", startCommand: "npm run dev") }
}

@MainActor
func runPlacementTests(_ run: TestRun) async {
    run.section("Placement - opening the deck")

    await run.test("cards with no position join the deck without overlapping, and are written down") {
        let desk = Desk(projects: projects(3))
        let changes = desk.placement.sync()
        try expectEqual(changes.filter { if case .open = $0 { return true }; return false }.count, 3)
        let frames = Array(desk.frames.values)
        try expectEqual(frames.count, 3)
        for (index, frame) in frames.enumerated() {
            try expect(laptop.visibleFrame.contains(frame), "on the screen: \(frame)")
            for other in frames[(index + 1)...] {
                try expect(!frame.intersects(other), "\(frame) overlaps \(other)")
            }
        }
        for card in desk.frames.keys {
            try expect(desk.deck.preferences.placement(for: card) != nil, "\(card) should be written down")
        }
    }

    await run.test("a card opens at the height it last settled at, not an empty card's") {
        let desk = Desk(projects: projects(1))
        let card = projects(1)[0].cardID
        desk.deck.preferences.setHeight(320, for: card)
        _ = desk.placement.sync()
        try expectEqual(desk.frames[card]?.height, 320)
    }

    await run.test("hiding a card closes the hole it leaves") {
        let all = projects(3)
        let desk = Desk(projects: all)
        _ = desk.placement.sync()
        // One column, a gap apart, as a person might have arranged it.
        for (index, card) in all.map(\.cardID).enumerated() {
            _ = desk.placement.moved(card, to: CGRect(x: 400, y: 700 - CGFloat(index) * 212, width: 352, height: 200), at: 10)
        }
        _ = desk.placement.settleMoves(at: 20)
        let ordered = desk.frames.sorted { $0.value.maxY > $1.value.maxY }
        let middle = ordered[1].key
        let bottomBefore = ordered[2].value
        desk.deck.runtime.cards.setEnabled(false, for: middle)
        let changes = desk.placement.sync()
        try expect(changes.contains(.close(middle)))
        let bottomAfter = try expectNotNil(desk.frames[ordered[2].key], "bottom card")
        try expectEqual(bottomAfter.maxY, bottomBefore.maxY + bottomBefore.height + CGFloat(CardMetrics.panelGap))
    }

    run.section("Placement - moves")

    await run.test("a drag is written down once the screens keep quiet after it") {
        let desk = Desk(projects: projects(1))
        let card = projects(1)[0].cardID
        _ = desk.placement.sync()
        let before = desk.deck.preferences.placement(for: card)
        let dragged = CGRect(x: 300, y: 300, width: 352, height: 200)
        let due = try expectNotNil(desk.placement.moved(card, to: dragged, at: 100), "a settle time")
        try expectEqual(desk.deck.preferences.placement(for: card), before, "not yet")
        _ = desk.placement.settleMoves(at: due)
        try expect(desk.deck.preferences.placement(for: card) != before, "the drag should be saved")
    }

    await run.test("the window server's shove before a screen change is never written down") {
        // The recorded order on an unplug: the window server moves the panel, then a moment later
        // says the screens changed. The move is not the user's.
        let card = projects(1)[0].cardID
        let desk = Desk(projects: projects(1))
        _ = desk.placement.sync()
        let before = desk.deck.preferences.placement(for: card)
        _ = desk.placement.moved(card, to: CGRect(x: 10, y: 10, width: 352, height: 200), at: 100)
        desk.placement.screensChanged()
        _ = desk.placement.settleMoves(at: 101)
        try expectEqual(desk.deck.preferences.placement(for: card), before)
    }

    run.section("Placement - a monitor unplugged and plugged back in")

    await run.test("cards on the unplugged display fold into a column on the laptop, and go home exactly") {
        let all = projects(2)
        let desk = Desk(projects: all)
        _ = desk.placement.sync()
        // Put both on the external display, as a person would, and let it settle.
        for (index, card) in all.map(\.cardID).enumerated() {
            let frame = CGRect(x: 2000, y: 1000 - CGFloat(index) * 220, width: 352, height: 200)
            _ = desk.placement.moved(card, to: frame, at: 10)
        }
        _ = desk.placement.settleMoves(at: 20)
        let home = desk.frames

        // Unplugged: the window server shoves the panels, then says the screens changed.
        for card in all.map(\.cardID) {
            _ = desk.placement.moved(card, to: CGRect(x: 100, y: 100, width: 352, height: 200), at: 30)
        }
        desk.displays = [laptop]
        desk.placement.screensChanged()
        _ = desk.placement.settleMoves(at: 31)
        _ = desk.placement.placeAfterScreensChanged()

        try expectEqual(desk.deck.runtime.parkedCards, Set(all.map(\.cardID)))
        for card in all.map(\.cardID) {
            let frame = try expectNotNil(desk.frames[card], "frame")
            try expect(laptop.visibleFrame.contains(frame), "\(card) should be on the laptop: \(frame)")
            try expectEqual(frame.height, CGFloat(CollapsedCardMetrics.height), "parked cards fold")
            try expectEqual(desk.deck.preferences.placement(for: card)?.displayID, "external", "parking is not a move")
        }

        // Plugged back in.
        desk.displays = [laptop, external]
        desk.placement.screensChanged()
        _ = desk.placement.placeAfterScreensChanged()
        try expect(desk.deck.runtime.parkedCards.isEmpty)
        for card in all.map(\.cardID) {
            try expectEqual(desk.frames[card]?.minX, home[card]?.minX)
            try expectEqual(desk.frames[card]?.maxY, home[card]?.maxY)
        }
    }

    await run.test("tidying while parked is a decision, and moves the cards for good") {
        let all = projects(1)
        let card = all[0].cardID
        let desk = Desk(projects: all)
        _ = desk.placement.sync()
        _ = desk.placement.moved(card, to: CGRect(x: 2000, y: 1000, width: 352, height: 200), at: 10)
        _ = desk.placement.settleMoves(at: 20)
        desk.displays = [laptop]
        _ = desk.placement.placeAfterScreensChanged()
        _ = desk.placement.tidy()
        try expectEqual(desk.deck.preferences.placement(for: card)?.displayID, "laptop")
    }

    run.section("Placement - sizes")

    await run.test("a card growing because its data arrived moves nothing under it") {
        let all = projects(2)
        let desk = Desk(projects: all)
        _ = desk.placement.sync()
        let ordered = desk.frames.sorted { $0.value.maxY > $1.value.maxY }
        let below = ordered[1].value
        desk.size = CGSize(width: 352, height: 260)
        _ = desk.placement.syncSizes()
        try expectEqual(desk.frames[ordered[1].key]?.maxY, below.maxY, "the deck settling is not a layout event")
        try expectEqual(desk.frames[ordered[0].key]?.maxY, ordered[0].value.maxY, "the top edge stays")
    }

    await run.test("a card somebody expanded makes room below it") {
        let all = projects(2)
        let desk = Desk(projects: all)
        _ = desk.placement.sync()
        let ordered = desk.frames.sorted { $0.value.maxY > $1.value.maxY }
        desk.deck.runtime.toggleExpanded(ordered[0].key)
        desk.size = CGSize(width: 352, height: 260)
        _ = desk.placement.syncSizes()
        let top = try expectNotNil(desk.frames[ordered[0].key], "top")
        let below = try expectNotNil(desk.frames[ordered[1].key], "below")
        try expectEqual(top.minY - below.maxY, CGFloat(CardMetrics.panelGap))
    }

    run.section("Placement - saved arrangements")

    await run.test("a saved deck is ticked while it is on screen, and a blank name saves nothing") {
        let all = projects(2)
        let desk = Desk(projects: all)
        _ = desk.placement.sync()
        desk.deck.runtime.perform(.saveArrangement(name: "   "))
        try expect(desk.deck.preferences.arrangements.isEmpty)
        desk.deck.runtime.perform(.saveArrangement(name: " Work "))
        try expectEqual(desk.deck.preferences.arrangements.map(\.name), ["Work"])

        let submenu = desk.deck.runtime.menu(update: nil).compactMap { entry -> [DeckMenuEntry]? in
            if case .submenu(let item, let children) = entry, item.title == L("menu.arrangements") { return children }
            return nil
        }.first ?? []
        guard case .item(let work)? = submenu.first else {
            throw TestFailure(message: "the saved deck should be offered", file: #filePath, line: #line)
        }
        try expect(work.isOn, "the deck on screen is the one saved")
        try expectEqual(work.alternate?.command, .forgetArrangement(name: "Work"))
    }

    await run.test("putting a deck back restores what is on, what is folded and where, then asks for the panels") {
        let all = projects(2)
        let desk = Desk(projects: all)
        _ = desk.placement.sync()
        let folded = all[0].cardID
        desk.deck.runtime.toggleCollapsed(folded)
        let placed = desk.deck.preferences.placement(for: folded)
        desk.deck.runtime.perform(.saveArrangement(name: "Folded"))

        desk.deck.runtime.toggleCollapsed(folded)
        desk.deck.runtime.cards.setEnabled(false, for: all[1].cardID)
        desk.deck.preferences.setPlacement(nil, for: folded)

        desk.deck.runtime.perform(.applyArrangement(name: "Folded"))
        try expect(desk.deck.runtime.isCollapsedByChoice(folded))
        try expect(desk.deck.runtime.cards.isEnabled(all[1].cardID))
        try expectEqual(desk.deck.preferences.placement(for: folded), placed)
        try expectEqual(desk.deck.effects.last, .arrangementApplied)

        desk.deck.runtime.perform(.forgetArrangement(name: "Folded"))
        try expect(desk.deck.preferences.arrangements.isEmpty)
    }
}
