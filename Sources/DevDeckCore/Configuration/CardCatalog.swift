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
            title: "My pull requests",
            subtitle: "Open PRs with checks, reviews and unresolved threads",
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
}
