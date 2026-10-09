import DevDeckCore
import DevDeckEngine
import Foundation
import GitHubKit
import ProjectKit
import TestHarness

// The menus, decided in the engine and checked without AppKit: what each row says, whether it
// is on, off or disabled, what it does, and what ⌥ turns it into.

/// Every item in a menu, submenus included, in order.
private func items(_ entries: [DeckMenuEntry]) -> [DeckMenuItem] {
    entries.flatMap { entry -> [DeckMenuItem] in
        switch entry {
        case .item(let item): return [item]
        case .submenu(let item, let children): return [item] + items(children)
        case .header, .separator, .arrangements: return []
        }
    }
}

private func item(_ title: String, in entries: [DeckMenuEntry]) -> DeckMenuItem? {
    items(entries).first { $0.title == title }
}

@MainActor
func runMenuModelTests(_ run: TestRun) async {
    run.section("Menu model - the menu-bar menu")

    await run.test("with nothing to say the menu says so, then the cards and the things you do") {
        let deck = Deck(cards: [.githubPullRequests])
        let entries = deck.runtime.menu(update: nil)
        guard case .item(let calm)? = entries.first else {
            throw TestFailure(message: "the menu should open on a row", file: #filePath, line: #line)
        }
        try expectEqual(calm.title, L("menu.calm"))
        try expect(!calm.isEnabled)
        try expectEqual(calm.image, .calm)
        try expect(entries.contains(.header(L("menu.cards"))))
        try expect(entries.contains(.arrangements(L("menu.arrangements"))))
        try expectEqual(items(entries).last?.command, .quit)
        try expectEqual(items(entries).last?.keyEquivalent, "q")
    }

    await run.test("built-in cards sit at the top, projects in a submenu that counts what is shown") {
        let project = LocalProject(id: "menu-site", title: "Site", folder: "/tmp", startCommand: "npm run dev")
        let deck = Deck(cards: [.githubPullRequests], localProjects: [project])
        let entries = deck.runtime.menu(update: nil)
        let pulls = try expectNotNil(items(entries).first { $0.command == .toggleCard(.githubPullRequests) }, "pull requests row")
        try expect(pulls.isIndented)
        let group = entries.compactMap { entry -> (DeckMenuItem, [DeckMenuEntry])? in
            if case .submenu(let item, let children) = entry { return (item, children) }
            return nil
        }.first
        let (title, children) = try expectNotNil(group, "the projects group")
        let shown = deck.runtime.cards.isEnabled(project.cardID) ? 1 : 0
        try expectEqual(title.title, L("menu.group.count", L("menu.group.projects"), shown, 1))
        try expectEqual(items(children).map(\.command), [.toggleCard(project.cardID)])
        try expectNil(item(L("menu.ddev.powerOff"), in: entries), "no DDEV cards, no power-off")
    }

    await run.test("the lock is a checkmark that follows the preference") {
        let deck = Deck(cards: [])
        try expect(item(L("menu.lock"), in: deck.runtime.menu(update: nil))?.isOn == deck.runtime.isLocked)
        deck.runtime.perform(.toggleLock)
        try expect(item(L("menu.lock"), in: deck.runtime.menu(update: nil))?.isOn == deck.runtime.isLocked)
        try expectEqual(deck.effects.last, .lockChanged)
    }

    await run.test("an inbox row can be marked read with ⌥, from the menu") {
        let deck = Deck(cards: [.githubInbox], http: FakeHTTPClient(routes: [
            ("/notifications", .success(.json(Fixtures.notifications))),
        ]))
        _ = await deck.runtime.refreshOnce()
        let rows = items(deck.runtime.menu(update: nil)).filter {
            if case .markRead? = $0.alternate?.command { return true }
            return false
        }
        try expect(!rows.isEmpty, "a thread for you should be in the menu with its ⌥ twin")
    }

    await run.test("the menu-bar tooltip names what is waiting") {
        let deck = Deck(cards: [])
        let digest = deck.runtime.attention(update: nil)
        try expectEqual(deck.runtime.status().tooltip, L("attention.tooltip", digest.summary))
        try expectEqual(deck.runtime.status().tier, digest.iconTier)
    }

    run.section("Menu model - a card's own menu")

    await run.test("a project's menu is titled with its name, not its identifier") {
        let project = LocalProject(id: "menu-title", title: "Feed", folder: "/tmp", startCommand: "npm run dev")
        let deck = Deck(cards: [project.cardID], localProjects: [project])
        guard case .item(let header)? = deck.runtime.cardMenu(for: project.cardID).first else {
            throw TestFailure(message: "the menu should open on its title", file: #filePath, line: #line)
        }
        try expectEqual(header.title, "Feed")
        try expect(!header.isEnabled)
    }

    await run.test("a parked card says so instead of offering to fold, and a folded one has no log") {
        let project = LocalProject(id: "menu-park", title: "Park", folder: "/tmp", startCommand: "npm run dev")
        let deck = Deck(cards: [project.cardID], localProjects: [project])
        deck.runtime.setParked([project.cardID])
        let parked = try expectNotNil(item(L("menu.card.parked"), in: deck.runtime.cardMenu(for: project.cardID)), "parked row")
        try expect(!parked.isEnabled)
        let log = try expectNotNil(item(L("menu.card.showLog"), in: deck.runtime.cardMenu(for: project.cardID)), "log row")
        try expect(!log.isEnabled, "a folded card keeps no log")
    }

    await run.test("the inbox's menu reads the rest, or all of it when only one kind is left, and ⌥ reads all") {
        let deck = Deck(cards: [.githubInbox], http: FakeHTTPClient(routes: [
            ("/notifications", .success(.json(Fixtures.notifications))),
        ]))
        _ = await deck.runtime.refreshOnce()
        let menu = deck.runtime.cardMenu(for: .githubInbox)
        let rest = try expectNotNil(items(menu).first { $0.command == .markRestRead }, "rest row")
        try expect(rest.isEnabled)
        try expectEqual(rest.help, L("card.inbox.readRest.help"))
        try expectEqual(rest.alternate, DeckMenuItem.Alternate(title: L("card.inbox.readAll.capped"), command: .markAllRead))
    }

    await run.test("hiding a card takes it off the deck and tells the shell") {
        let deck = Deck(cards: [.githubPullRequests])
        let before = deck.runtime.cards.isEnabled(.githubPullRequests)
        deck.runtime.perform(.toggleCard(.githubPullRequests))
        try expectEqual(deck.runtime.cards.isEnabled(.githubPullRequests), !before)
        try expectEqual(deck.effects.last, .cardsChanged)
    }

    await run.test("Open pull requests uses the first account's browser") {
        let deck = Deck(cards: [])
        deck.runtime.perform(.openPullRequestsPage)
        try expectEqual(deck.effects.last, .openURL(URL(string: "https://github.com/pulls")!, .systemDefault))
    }

    run.section("Menu model - banners")

    await run.test("three or more at once become one line that opens the menu") {
        func alert(_ id: String) -> DeckAlert {
            DeckAlert(id: id, kind: .reviewRequest, source: .github, title: id, subtitle: "", body: "", subject: "", target: .menu, isQuiet: false)
        }
        try expectEqual(DeckRuntime.banners(for: [alert("a"), alert("b")]).count, 2)
        let grouped = DeckRuntime.banners(for: [alert("a"), alert("b"), alert("c")])
        try expectEqual(grouped.count, 1)
        try expectEqual(grouped.first?.target, .menu)
        try expectEqual(grouped.first?.source, .github)
    }
}
