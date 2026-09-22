import DevDeckCore
import Foundation

/// Why GitHub put a notification in the inbox.
///
/// The set is closed on GitHub's side but grows over time, so anything unrecognised becomes
/// `.other` rather than being dropped - a notification nobody can explain is still a
/// notification worth showing.
public enum NotificationReason: String, Sendable, Equatable, Codable {
    case reviewRequested
    case mention
    case teamMention
    case assigned
    case ciActivity
    case stateChange
    case comment
    case author
    case subscribed
    case securityAlert
    case other

    public init(apiValue: String) {
        switch apiValue {
        case "review_requested": self = .reviewRequested
        case "mention": self = .mention
        case "team_mention": self = .teamMention
        case "assign": self = .assigned
        case "ci_activity": self = .ciActivity
        case "state_change": self = .stateChange
        case "comment": self = .comment
        case "author": self = .author
        case "subscribed": self = .subscribed
        case "security_alert": self = .securityAlert
        default: self = .other
        }
    }

    /// Short chip text for the card, in the interface's language. Long enough to be
    /// unambiguous, short enough for a row.
    public var chip: String {
        switch self {
        case .reviewRequested: return L("card.inbox.chip.review")
        case .mention: return L("card.inbox.chip.mention")
        case .teamMention: return L("card.inbox.chip.team")
        case .assigned: return L("card.inbox.chip.assigned")
        case .ciActivity: return L("card.inbox.chip.ci")
        case .stateChange: return L("card.inbox.chip.state")
        case .comment: return L("card.inbox.chip.comment")
        case .author: return L("card.inbox.chip.yours")
        case .subscribed: return L("card.inbox.chip.watching")
        case .securityAlert: return L("card.inbox.chip.security")
        case .other: return L("card.inbox.chip.other")
        }
    }

    /// Waiting on you personally: a security alert, a review request, a mention, an assignment.
    /// Everything else is something you are merely subscribed to.
    public var isForYou: Bool { priority <= 3 }

    /// Lower sorts first. Things that block someone else outrank things that merely happened.
    public var priority: Int {
        switch self {
        case .securityAlert: return 0
        case .reviewRequested: return 1
        case .mention, .teamMention: return 2
        case .assigned: return 3
        case .ciActivity: return 4
        case .author, .comment: return 5
        case .stateChange: return 6
        case .subscribed, .other: return 7
        }
    }
}

public struct InboxItem: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let reason: NotificationReason
    public let title: String
    public let repository: String
    public let updatedAt: Date
    public let isUnread: Bool
    /// Where a click goes. Nil when the subject has no addressable web page.
    public let url: URL?
    public let accountID: String

    public init(
        id: String,
        reason: NotificationReason,
        title: String,
        repository: String,
        updatedAt: Date,
        isUnread: Bool,
        url: URL?,
        accountID: String = GitHubAccount.defaultID
    ) {
        self.accountID = accountID
        self.id = id
        self.reason = reason
        self.title = title
        self.repository = repository
        self.updatedAt = updatedAt
        self.isUnread = isUnread
        self.url = url
    }

    public var shortRepository: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }

    /// Turns a notification subject's API URL into the page a human can open.
    ///
    /// The notifications endpoint only ever returns API URLs
    /// (`https://api.github.com/repos/o/r/pulls/1`), and there is no field carrying the HTML
    /// one. The rewrite is mechanical, but `pulls` → `pull` is easy to miss and produces a
    /// 404 that looks like a permissions problem.
    public static func webURL(fromSubject apiURL: URL?) -> URL? {
        guard let apiURL else { return nil }
        var text = apiURL.absoluteString
        guard let range = text.range(of: "://api.github.com/repos/") else { return apiURL }
        text.replaceSubrange(range, with: "://github.com/")
        text = text.replacingOccurrences(of: "/pulls/", with: "/pull/")
        // Release and commit subjects already line up; only the check-suite form has no page.
        return URL(string: text)
    }
}
