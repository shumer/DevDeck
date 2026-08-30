import Foundation

/// Stable identifier of a card. Raw values are persisted in `config.json`, so they must never change.
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
/// Adding a card means adding a descriptor here; the settings UI and `config.json` merge logic
/// pick it up automatically, and users who already have a config keep their own ordering.
public enum CardCatalog {
    public static let all: [CardDescriptor] = [
        CardDescriptor(
            id: .githubPullRequests,
            title: "Pull requests",
            subtitle: "Yours, plus the ones waiting for your review",
            isImplemented: true,
            isEnabledByDefault: true
        ),
        CardDescriptor(
            id: .githubInbox,
            title: "GitHub inbox",
            subtitle: "Review requests, mentions and CI notifications",
            isImplemented: true,
            isEnabledByDefault: true
        ),
        CardDescriptor(
            id: .githubActions,
            title: "GitHub Actions",
            subtitle: "Workflow success rate and running jobs",
            isImplemented: true,
            isEnabledByDefault: false
        ),
        // Off by default: a deck that has never heard of GitLab should not carry a card asking
        // for a token to an instance nobody uses. Adding an account in settings turns it on.
        CardDescriptor(
            id: .gitlabMergeRequests,
            title: "Merge requests",
            subtitle: "Yours, plus the ones waiting for your review",
            isImplemented: true,
            isEnabledByDefault: false
        ),
        CardDescriptor(
            id: .arcOrganizations,
            title: "Arc XP organizations",
            subtitle: "Orgs, sites and live bundle versions",
            isImplemented: false,
            isEnabledByDefault: false
        ),
        CardDescriptor(
            id: .localStack,
            title: "Local stack",
            subtitle: "Local Fusion containers and ports",
            isImplemented: false,
            isEnabledByDefault: false
        ),
    ]

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
        byTitle(arc) + byTitle(ddev) + byTitle(plain)
    }

    /// Compared the way a person reads a list: case-insensitively, and with numbers as numbers
    /// so `site2` comes before `site10`.
    private static func byTitle(_ cards: [CardDescriptor]) -> [CardDescriptor] {
        cards.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
