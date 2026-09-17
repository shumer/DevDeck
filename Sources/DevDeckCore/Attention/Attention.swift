import Foundation

/// How much a signal asks of the person reading it, in the order the menu lists them.
///
/// Four tiers rather than one "waiting" number. The number used to add review requests to inbox
/// mentions, count the same review twice, leave GitLab out and say nothing about a token that had
/// stopped working, so a red dot beside "1 waiting on you" answered none of who, what or where.
public enum AttentionTier: Int, Sendable, Equatable, Comparable, CaseIterable {
    /// A person is waiting on you: a review, a mention, an assignment, a security alert.
    case waiting
    /// Something broke that is fixed from here: a token, a project on this Mac, Docker under it.
    /// Above your stuck work, because it is usually one click and the stuck work waits on CI.
    case needsFixing
    /// Your own work cannot move: failed checks, requested changes, a conflict, a red pipeline.
    case stuck
    /// Worth knowing, never worth a badge: an update, work that exists only on this Mac.
    case goodToKnow

    public static func < (left: AttentionTier, right: AttentionTier) -> Bool {
        left.rawValue < right.rawValue
    }

    /// The menu's section header.
    public var title: String {
        switch self {
        case .waiting: return "Waiting on you"
        case .needsFixing: return "Needs fixing"
        case .stuck: return "Your work is stuck"
        case .goodToKnow: return "Good to know"
        }
    }

    /// Whether this tier puts a badge on the menu-bar icon at all.
    public var lightsIcon: Bool { self != .goodToKnow }
}

/// Which mark a row carries, so who is asking is answered before the words are read.
public enum AttentionMark: Sendable, Equatable {
    case github
    case gitlab
    case arc
    case ddev
    /// A plain project, by the raw value of its kind, so the row wears the card's own mark.
    case project(String)
    case docker
    case token
    case network
    case rateLimit
    case update
    case unpushed
    case noRemote
}

/// What choosing a row does. Each one is the next step the row's words promise.
public enum AttentionAction: Sendable, Equatable {
    /// Opens a page in the browser of the account it belongs to.
    case open(URL, service: AttentionService, account: String)
    /// Opens Settings on that account's form.
    case accountSettings(service: AttentionService, account: String)
    /// Brings the deck forward and opens the card's log.
    case showCard(CardID)
    case startDocker
    /// Opens a terminal in the checkout.
    case openTerminal(URL)
    case installUpdate
    /// Nothing to do: a row that only reports.
    case none
}

public enum AttentionService: String, Sendable, Equatable {
    case github
    case gitlab

    public var name: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        }
    }
}

/// One thing the deck wants a person to know, in the words the menu, the tooltip and a banner use.
public struct AttentionItem: Sendable, Equatable, Identifiable {
    /// Stable across refreshes for the same thing in the same state.
    public let id: String
    public let tier: AttentionTier
    public let mark: AttentionMark
    /// What happened, with the thing it happened to: `Review: Add the article feed`.
    public let title: String
    /// Where, who and why: `acme/portal #142 · review requested · Work`.
    public let subtitle: String
    /// When it started, for the age at the end of the row. Nil when there is no honest answer.
    public let since: Date?
    public let action: AttentionAction
    /// A row that reports and has nothing to click, such as an update waiting for a command.
    public let isEnabled: Bool
    /// Whether ⌥ offers to dismiss it. Only for what cannot clear itself by being fixed
    /// somewhere else, such as a project that stopped on its own.
    public let isDismissible: Bool
    /// The inbox notification behind the row, so ⌥ can mark it read.
    public let inboxThreadID: String?

    public init(
        id: String,
        tier: AttentionTier,
        mark: AttentionMark,
        title: String,
        subtitle: String,
        since: Date? = nil,
        action: AttentionAction,
        isEnabled: Bool = true,
        isDismissible: Bool = false,
        inboxThreadID: String? = nil
    ) {
        self.id = id
        self.tier = tier
        self.mark = mark
        self.title = title
        self.subtitle = subtitle
        self.since = since
        self.action = action
        self.isEnabled = isEnabled
        self.isDismissible = isDismissible
        self.inboxThreadID = inboxThreadID
    }
}

/// Everything the deck wants attention for, sorted, sectioned and counted once.
public struct AttentionDigest: Sendable, Equatable {
    /// Rows per section before the rest go into a submenu. Three is what fits beside the rest of
    /// the menu on a 13-inch screen with a subtitle under every row.
    public static let rowsPerSection = 3
    /// Good to know is capped harder: it is the least urgent and it sits last.
    public static let rowsForGoodToKnow = 2

    public struct Section: Sendable, Equatable {
        public let tier: AttentionTier
        public let visible: [AttentionItem]
        public let overflow: [AttentionItem]

        /// The submenu row under a section that did not fit: `2 more stuck`.
        public var overflowTitle: String? {
            guard !overflow.isEmpty else { return nil }
            switch tier {
            case .waiting: return "\(overflow.count) more waiting on you"
            case .needsFixing: return "\(overflow.count) more to fix"
            case .stuck: return "\(overflow.count) more stuck"
            case .goodToKnow: return "\(overflow.count) more"
            }
        }
    }

    public let items: [AttentionItem]

    /// Deduplicated by id and sorted: tier first, then within a tier the order that tier is read
    /// in. Somebody waiting longest goes first; for everything else the newest goes first,
    /// because that is the one most likely to have been caused by what you just did.
    public init(items: [AttentionItem]) {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        self.items = unique.sorted { left, right in
            if left.tier != right.tier { return left.tier < right.tier }
            let leftDate = left.since ?? .distantPast
            let rightDate = right.since ?? .distantPast
            if leftDate != rightDate {
                return left.tier == .waiting ? leftDate < rightDate : leftDate > rightDate
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    public var isEmpty: Bool { items.isEmpty }

    /// The most urgent tier that lights the icon, or nil when the icon should stay plain.
    public var iconTier: AttentionTier? {
        items.map(\.tier).filter(\.lightsIcon).min()
    }

    public func count(_ tier: AttentionTier) -> Int {
        items.filter { $0.tier == tier }.count
    }

    public var sections: [Section] {
        AttentionTier.allCases.compactMap { tier in
            let rows = items.filter { $0.tier == tier }
            guard !rows.isEmpty else { return nil }
            let cap = tier == .goodToKnow ? Self.rowsForGoodToKnow : Self.rowsPerSection
            // A single leftover row is shown rather than folded: a submenu holding one row costs
            // the same line and hides the row behind a hover.
            guard rows.count > cap + 1 else { return Section(tier: tier, visible: rows, overflow: []) }
            return Section(tier: tier, visible: Array(rows.prefix(cap)), overflow: Array(rows.dropFirst(cap)))
        }
    }

    /// One line for the tooltip and for VoiceOver, counting things by what they are.
    public var summary: String {
        var parts: [String] = []
        let waiting = count(.waiting)
        let fixing = count(.needsFixing)
        let stuck = count(.stuck)
        if waiting > 0 { parts.append("\(waiting) waiting on you") }
        if fixing > 0 { parts.append("\(fixing) to fix") }
        if stuck > 0 { parts.append("\(stuck) stuck") }
        return parts.isEmpty ? "nothing needs you" : parts.joined(separator: ", ")
    }

    /// The age at the end of a row: `now`, `12m`, `5h`, `3d`.
    public static func age(since date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    /// `10:42`, the way every time on the deck is written.
    public static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// Words shared by every builder, so one thing has one name wherever it appears.
public enum AttentionWords {
    /// `Work` appended to a subtitle only when there is more than one account to tell apart.
    public static func withAccount(_ parts: [String], label: String?) -> String {
        (parts + [label].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// `ACME Shop and ACME News`, `ACME Shop, ACME News and 2 more`.
    public static func list(_ names: [String], limit: Int = 2) -> String {
        guard !names.isEmpty else { return "" }
        if names.count == 1 { return names[0] }
        if names.count <= limit { return names.dropLast().joined(separator: ", ") + " and " + names.last! }
        return names.prefix(limit).joined(separator: ", ") + " and \(names.count - limit) more"
    }

    /// A title cut to what a menu row can hold, at a word where one is near.
    public static func trimmed(_ text: String, to limit: Int = 48) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit - 1)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }
}
