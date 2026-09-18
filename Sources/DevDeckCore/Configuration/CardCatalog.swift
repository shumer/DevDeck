import Foundation

/// Stable identifier of a card. Raw values are persisted in preferences and in panel placement
/// keys, so they must never change.
public struct CardID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public extension CardID {
    static let githubPullRequests = CardID(rawValue: "github.pullRequests")
    static let githubInbox = CardID(rawValue: "github.inbox")
    static let githubActions = CardID(rawValue: "github.actions")
    static let gitlabMergeRequests = CardID(rawValue: "gitlab.mergeRequests")
    static let workInFlight = CardID(rawValue: "local.workInFlight")
    static let arcOrganizations = CardID(rawValue: "arc.organizations")
    static let localStack = CardID(rawValue: "local.stack")
}

/// Static description of a card: what it is called and whether it ships enabled by default.
public struct CardDescriptor: Sendable, Equatable {
    public let id: CardID
    public let title: String
    public let subtitle: String
    public let isImplemented: Bool
    public let isEnabledByDefault: Bool

    public init(id: CardID, title: String, subtitle: String, isImplemented: Bool, isEnabledByDefault: Bool) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isImplemented = isImplemented
        self.isEnabledByDefault = isEnabledByDefault
    }
}

/// Registry of every card the app knows about, in default display order.
///
/// Adding a card means adding a descriptor here; the settings UI and the stored card layout
/// pick it up automatically, and users who already have a layout keep their own ordering.
public enum CardCatalog {
    public static var all: [CardDescriptor] {[
        CardDescriptor(
            id: .githubPullRequests,
            title: L("card.title.pulls"),
            subtitle: L("card.catalog.pulls.subtitle"),
            isImplemented: true,
            isEnabledByDefault: true
        ),
        CardDescriptor(
            id: .githubInbox,
            title: L("card.title.inbox"),
            subtitle: L("card.catalog.inbox.subtitle"),
            isImplemented: true,
            isEnabledByDefault: true
        ),
        CardDescriptor(
            id: .githubActions,
            title: L("card.title.actions"),
            subtitle: L("card.catalog.actions.subtitle"),
            isImplemented: true,
            isEnabledByDefault: false
        ),
        // Off by default: a deck that has never heard of GitLab should not carry a card asking
        // for a token to an instance nobody uses. Adding an account in settings turns it on.
        CardDescriptor(
            id: .gitlabMergeRequests,
            // Named for its service, unlike "Pull requests", which was here first and alone.
            // Two entries called "Pull requests" and "Merge requests" side by side are two
            // things nobody can tell apart at a glance.
            title: L("card.title.merges.gitlab"),
            subtitle: L("card.catalog.pulls.subtitle"),
            isImplemented: true,
            isEnabledByDefault: false
        ),
        CardDescriptor(
            id: .workInFlight,
            title: L("card.title.workInFlight"),
            subtitle: L("card.catalog.wif.subtitle"),
            isImplemented: true,
            isEnabledByDefault: false
        ),
        CardDescriptor(
            id: .arcOrganizations,
            title: L("card.catalog.arc.title"),
            subtitle: L("card.catalog.arc.subtitle"),
            isImplemented: false,
            isEnabledByDefault: false
        ),
        CardDescriptor(
            id: .localStack,
            title: L("project.section.stack"),
            subtitle: L("card.catalog.stack.subtitle"),
            isImplemented: false,
            isEnabledByDefault: false
        ),
    ]}

    public static func descriptor(for id: CardID) -> CardDescriptor? {
        all.first { $0.id == id }
    }

    /// The catalog plus whatever cards the user's own configuration adds - one per Arc
    /// project, for instance. Layout and menu code always works against this, so a project
    /// added in settings becomes a card without any change here.
    public static func all(including dynamic: [CardDescriptor]) -> [CardDescriptor] {
        all.filter { descriptor in !dynamic.contains { $0.id == descriptor.id } } + dynamic
    }

    /// Project cards in the order the deck lays them out: Arc, then DDEV, then the plain ones,
    /// each group alphabetical.
    ///
    /// A rule rather than an accident. The order used to come from the stored settings, where a
    /// card was appended the first time it was switched on - so the deck ended up in the
    /// sequence the projects happened to be added in, and "Tidy panels" faithfully reproduced
    /// it. Kinds first because that is how the menu groups them and how someone thinks about
    /// them; alphabetical within a kind because any other rule needs remembering.
    public static func projectOrder(
        arc: [CardDescriptor],
        ddev: [CardDescriptor],
        plain: [CardDescriptor]
    ) -> [CardDescriptor] {
        sortedByTitle(arc) + sortedByTitle(ddev) + sortedByTitle(plain)
    }

    /// Compared the way a person reads a list: case-insensitively, and with numbers as numbers
    /// so `site2` comes before `site10`.
    public static func sortedByTitle(_ cards: [CardDescriptor]) -> [CardDescriptor] {
        cards.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
