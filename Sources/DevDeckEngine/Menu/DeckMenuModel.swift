import DevDeckCore
import Foundation
import GitHubKit

// The menus, decided. The menu-bar menu and a card's right-click menu are built here, with every
// title already in the reader's language, every checkmark, every disabled row and every ⌥ twin;
// a shell turns the entries into its own menus and sends the commands back. See
// docs/adr/0028-the-menu-in-the-engine.md.

/// One row of a menu.
public struct DeckMenuItem: Sendable, Equatable {
    /// What the row's picture means; the shell draws it.
    public enum Image: Sendable, Equatable {
        case attention(AttentionMark)
        /// Nothing needs you.
        case calm
        /// The rest of a tier, in a submenu.
        case more
    }

    /// The row a held ⌥ turns this one into.
    public struct Alternate: Sendable, Equatable {
        public let title: String
        public let command: DeckCommand
        public var isEnabled = true

        public init(title: String, command: DeckCommand, isEnabled: Bool = true) {
            self.title = title
            self.command = command
            self.isEnabled = isEnabled
        }
    }

    public var title: String
    /// The second line. A shell without one puts it in the tooltip rather than losing it.
    public var subtitle: String?
    /// How long ago, at the trailing edge.
    public var badge: String?
    public var image: Image?
    public var isOn = false
    public var isEnabled = true
    public var help: String?
    public var keyEquivalent = ""
    /// Under a heading rather than in a submenu, so set in from the edge.
    public var isIndented = false
    public var command: DeckCommand?
    /// Asked before the command is sent, for the one row that stops everything at once.
    public var confirmation: DeckConfirmation?
    public var alternate: Alternate?

    public init(_ title: String, command: DeckCommand? = nil) {
        self.title = title
        self.command = command
    }
}

/// A question to answer before a command goes ahead.
public struct DeckConfirmation: Sendable, Equatable {
    public let title: String
    public let detail: String
    public let confirm: String
    public let cancel: String
}

public indirect enum DeckMenuEntry: Sendable, Equatable {
    case header(String)
    case item(DeckMenuItem)
    case separator
    case submenu(DeckMenuItem, [DeckMenuEntry])
    /// The saved arrangements, which the shell fills in until placement moves into the engine.
    case arrangements(String)
}

/// What the menu-bar item shows: which tier lights the icon, and the words behind it.
public struct DeckStatusModel: Sendable, Equatable {
    public let tier: AttentionTier?
    public let tooltip: String
    /// For VoiceOver: a bare icon belongs to nothing in particular.
    public let accessibilityValue: String

    /// Before the first answer.
    public static var checking: DeckStatusModel {
        DeckStatusModel(tier: nil, tooltip: L("attention.tooltip", L("menu.checking")), accessibilityValue: L("menu.checking"))
    }
}

/// The offer of a newer build, as the updater describes it, for the menu's own tier.
public struct DeckUpdateOffer: Sendable, Equatable {
    public let item: AttentionItem
    public let version: String

    public init(item: AttentionItem, version: String) {
        self.item = item
        self.version = version
    }
}

extension DeckRuntime {
    /// The menu-bar item's icon tier and words.
    public func status() -> DeckStatusModel {
        let digest = attention(update: nil)
        return DeckStatusModel(
            tier: digest.iconTier,
            tooltip: L("attention.tooltip", digest.summary),
            accessibilityValue: digest.summary
        )
    }

    /// The menu-bar menu, as it should be the moment it opens.
    ///
    /// What the badge is about comes first, as the things themselves; then the cards; then the
    /// things you do. What the deck is (where panels sit, whether ⌥Space raises them) lives in
    /// Settings: a menu that mixes the two grows until the thing you came for is in the middle.
    ///
    /// - `samples`: rows of every tier with made-up names, for a screenshot of a busy menu.
    public func menu(update: DeckUpdateOffer?, samples: Bool = false) -> [DeckMenuEntry] {
        var entries = attentionEntries(update: update, samples: samples)

        entries.append(.header(L("menu.cards")))
        let list = cards
        let resolved = list.resolved
        let grouped = Set(list.groups.flatMap(\.cards))
        for card in resolved where !grouped.contains(card.id) {
            entries.append(.item(cardItem(card, isIndented: true)))
        }
        // Projects get their own groups: with several of them the built-in cards would
        // otherwise be lost in the middle of a list of site names. The count in the title says
        // how many are on the deck without opening it.
        for group in list.groups {
            let members = resolved.filter { group.cards.contains($0.id) }
            guard !members.isEmpty else { continue }
            let shown = members.filter(\.isEnabled).count
            entries.append(.submenu(
                DeckMenuItem(L("menu.group.count", group.title, shown, members.count)),
                members.map { .item(cardItem($0, isIndented: false)) }
            ))
        }
        if resolved.contains(where: { list.isDDEV($0.id) }) {
            var powerOff = DeckMenuItem(L("menu.ddev.powerOff"), command: .powerOffDDEV)
            powerOff.help = L("menu.ddev.powerOff.tooltip")
            // The one item in this menu that stops everything at once, a line away from Refresh.
            powerOff.confirmation = DeckConfirmation(
                title: L("menu.ddev.confirm.title"),
                detail: L("menu.ddev.confirm.detail"),
                confirm: L("button.powerOff"),
                cancel: L("button.cancel")
            )
            entries.append(.item(powerOff))
        }

        entries.append(.separator)
        entries.append(.item(DeckMenuItem(L("menu.openPulls"), command: .openPullRequestsPage)))

        entries.append(.separator)
        entries.append(.arrangements(L("menu.arrangements")))
        entries.append(.item(lockItem))
        entries.append(.item(DeckMenuItem(L("menu.tidy"), command: .tidy)))
        entries.append(.item(DeckMenuItem(L("menu.refresh"), command: .refreshNow)))
        entries.append(.item(DeckMenuItem(L("menu.settings"), command: .openSettings)))

        entries.append(.separator)
        var quit = DeckMenuItem(L("menu.quit"), command: .quit)
        quit.keyEquivalent = "q"
        entries.append(.item(quit))
        return entries
    }

    /// A card's right-click menu: this card, then the two things you might want next. It used to
    /// answer with the whole deck's menu, card list and all, which is the same as not answering.
    public func cardMenu(for card: CardID) -> [DeckMenuEntry] {
        var entries: [DeckMenuEntry] = []
        let list = cards
        var header = DeckMenuItem(list.resolved.first { $0.id == card }?.descriptor.title ?? card.rawValue)
        header.isEnabled = false
        entries.append(.item(header))

        // A parked card is folded by the deck, and says so in place of the choice it cannot offer.
        var collapse = DeckMenuItem(
            isParked(card) ? L("menu.card.parked") : isCollapsed(card) ? L("menu.card.showWhole") : L("menu.card.collapse"),
            command: .toggleCollapsed(card)
        )
        collapse.isEnabled = !isParked(card)
        entries.append(.item(collapse))

        if hasLogSource(card) {
            var logs = DeckMenuItem(isShowingLogs(card) ? L("menu.card.hideLog") : L("menu.card.showLog"), command: .toggleLogs(card))
            logs.isEnabled = !isCollapsed(card)
            entries.append(.item(logs))
        }

        // The inbox's footer link, here as well: the same two readings, with ⌥ for the whole box
        // the way every other destructive twin in these menus is found.
        if card == .githubInbox, let box = inbox.value, box.unreadCount > 0 {
            let running = inboxProgress?.isRunning == true
            var rest = DeckMenuItem(LN("card.inbox.readRest", box.actionableCount), command: .markRestRead)
            rest.isEnabled = !running && (box.isCapped || !box.unreadNotForYou.isEmpty)
            // Only one kind left: the menu offers the whole box in the open, as the card does.
            if !rest.isEnabled, !running {
                rest.title = box.isCapped ? L("card.inbox.readAll.capped") : LN("card.inbox.readAll", box.unreadCount)
                rest.command = .markAllRead
                rest.isEnabled = true
            }
            rest.help = L("card.inbox.readRest.help")
            rest.alternate = DeckMenuItem.Alternate(title: L("card.inbox.readAll.capped"), command: .markAllRead, isEnabled: !running)
            entries.append(.item(rest))
        }

        entries.append(.item(DeckMenuItem(L("menu.card.hide"), command: .toggleCard(card))))
        // Straight to this card's own form, rather than a list of fifteen to find it in.
        entries.append(.item(DeckMenuItem(L("menu.card.settings"), command: .openCardSettings(card))))

        entries.append(.separator)
        entries.append(.item(lockItem))
        entries.append(.item(DeckMenuItem(L("menu.tidy"), command: .tidy)))
        entries.append(.item(DeckMenuItem(L("menu.refresh"), command: .refreshNow)))
        return entries
    }

    // MARK: Pieces

    /// The lock, as a checkmark, in both menus: it is toggled in the middle of arranging cards,
    /// and a trip to a settings window for that is the one interruption the deck should not cost.
    private var lockItem: DeckMenuItem {
        var item = DeckMenuItem(L("menu.lock"), command: .toggleLock)
        item.isOn = isLocked
        item.help = L("menu.lock.tooltip")
        return item
    }

    private func cardItem(_ card: ResolvedCard, isIndented: Bool) -> DeckMenuItem {
        var item = DeckMenuItem(card.descriptor.title, command: .toggleCard(card.id))
        item.isOn = card.isEnabled
        item.isIndented = isIndented
        if !card.descriptor.isImplemented {
            item.isEnabled = false
            item.help = L("menu.notBuilt")
        }
        return item
    }

    /// What the badge is about, as the things themselves: each row names what happened and to
    /// what, and clicking it goes there. The line this replaced said "1 waiting on you" in grey,
    /// which in a menu reads as "nothing to do here".
    private func attentionEntries(update: DeckUpdateOffer?, samples: Bool) -> [DeckMenuEntry] {
        let now = self.now
        let digest = samples
            ? AttentionDigest(items: AttentionSamples.items(now: now))
            : attention(update: update?.item)

        guard !digest.isEmpty else {
            // Said rather than left out, so an empty menu is a confirmation and not a question.
            var calm = DeckMenuItem(L("menu.calm"))
            calm.isEnabled = false
            calm.image = .calm
            calm.subtitle = L("menu.checkedAt", AttentionDigest.clock(lastCheckedAt ?? now))
            return [.item(calm), .separator]
        }

        var entries: [DeckMenuEntry] = []
        for section in digest.sections {
            entries.append(.header(section.tier.title))
            entries += section.visible.map { .item(row($0, update: update, now: now)) }
            if let title = section.overflowTitle {
                // The rest in a submenu of the same rows, rather than "see the card": the rows
                // come from several cards, and some of them from none.
                var more = DeckMenuItem(title)
                more.image = .more
                entries.append(.submenu(more, section.overflow.map { .item(row($0, update: update, now: now)) }))
            }
        }
        entries.append(.separator)
        return entries
    }

    /// One attention row, and its ⌥ twin when it has one.
    private func row(_ item: AttentionItem, update: DeckUpdateOffer?, now: Date) -> DeckMenuItem {
        var row = DeckMenuItem(item.title, command: command(for: item.action))
        row.isEnabled = item.isEnabled && item.action != .none
        row.image = .attention(item.mark)
        // One line: a menu wraps a long subtitle, and a server's error message is long.
        row.subtitle = AttentionWords.trimmed(item.subtitle, to: 72)
        row.badge = AttentionDigest.age(since: item.since, now: now)
        if let thread = item.inboxThreadID {
            row.alternate = .init(title: L("menu.markRead", item.title), command: .markRead(threadID: thread))
        } else if item.isDismissible {
            row.alternate = .init(title: L("menu.dismiss", item.title), command: .dismissAttention(id: item.id))
        } else if item.action == .installUpdate, let version = update?.version {
            row.alternate = .init(title: L("menu.whatsNew", version), command: .openReleaseNotes)
        }
        return row
    }

    private func command(for action: AttentionAction) -> DeckCommand? {
        switch action {
        case .open(let url, let service, let account):
            return .openLink(url, account: account, service: service == .github ? .github : .gitlab)
        case .accountSettings(let service, let account):
            return .openAccountSettings(service, account: account.isEmpty ? nil : account)
        case .showCard(let card):
            return .showCard(card)
        case .startDocker:
            return .startDocker
        case .openTerminal(let folder):
            return .openTerminalAt(folder)
        case .installUpdate:
            return .installUpdate
        case .none:
            return nil
        }
    }
}
