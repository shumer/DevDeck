import Foundation

/// GitHub's own review verdict for a pull request.
public enum ReviewDecision: String, Sendable, Equatable, Codable {
    case approved
    case changesRequested
    case reviewRequired
    case none

    public init(apiValue: String?) {
        switch apiValue {
        case "APPROVED": self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        case "REVIEW_REQUIRED": self = .reviewRequired
        default: self = .none
        }
    }
}

/// Rolled-up state of the checks on the head commit.
public enum CheckState: String, Sendable, Equatable, Codable {
    case success
    case failure
    case pending
    case none

    public init(apiValue: String?) {
        switch apiValue {
        case "SUCCESS": self = .success
        // ERROR is a check that blew up rather than reported a verdict; for the card it is
        // indistinguishable from a failure — both mean "this will not merge as it stands".
        case "FAILURE", "ERROR": self = .failure
        case "PENDING", "EXPECTED": self = .pending
        default: self = .none
        }
    }
}

/// The one thing the card colours a row by: does this PR need me, is it stuck, or is it done.
public enum PullRequestHealth: String, Sendable, Equatable, Codable {
    /// Cannot merge without work: checks failed, or a reviewer asked for changes.
    case blocked
    /// Waiting on someone — review, running checks, or an open thread.
    case attention
    /// Approved, green and nothing unresolved.
    case ready
}

public struct PullRequestSummary: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let number: Int
    public let title: String
    /// Full `owner/name`, because the card is cross-repository by definition.
    public let repository: String
    public let organization: String
    public let url: URL
    public let isDraft: Bool
    public let updatedAt: Date
    public let reviewDecision: ReviewDecision
    public let checks: CheckState
    public let unresolvedThreads: Int
    /// Which configured account this came from. Rows from several accounts share one card.
    public let accountID: String

    public init(
        id: String,
        number: Int,
        title: String,
        repository: String,
        organization: String,
        url: URL,
        isDraft: Bool,
        updatedAt: Date,
        reviewDecision: ReviewDecision,
        checks: CheckState,
        unresolvedThreads: Int,
        accountID: String = GitHubAccount.defaultID
    ) {
        self.accountID = accountID
        self.id = id
        self.number = number
        self.title = title
        self.repository = repository
        self.organization = organization
        self.url = url
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.unresolvedThreads = unresolvedThreads
    }

    public var health: PullRequestHealth {
        if checks == .failure || reviewDecision == .changesRequested { return .blocked }
        if reviewDecision == .approved, checks != .pending, unresolvedThreads == 0 { return .ready }
        return .attention
    }

    /// The single most useful thing to say about this PR, in the order it matters.
    public var statusLine: String {
        if checks == .failure { return "checks failed" }
        if reviewDecision == .changesRequested { return "changes requested" }
        if isDraft { return "draft" }
        if checks == .pending { return "checks running" }
        if unresolvedThreads == 1 { return "1 unresolved thread" }
        if unresolvedThreads > 1 { return "\(unresolvedThreads) unresolved threads" }
        if reviewDecision == .approved { return "approved" }
        return "waiting for review"
    }

    /// Two-character code for the card, so the title gets the width instead of a sentence.
    ///
    /// Deliberately mirrors `statusLine` case for case — the full wording is what the row's
    /// tooltip shows, and the two drifting apart would be worse than either alone.
    ///
    ///     CF  checks failed        CP  checks running      T3  three unresolved threads
    ///     CR  changes requested    DR  draft
    ///     AP  approved             WR  waiting for review
    public var statusCode: String {
        if checks == .failure { return "CF" }
        if reviewDecision == .changesRequested { return "CR" }
        if isDraft { return "DR" }
        if checks == .pending { return "CP" }
        // More than nine open conversations is already the most blocked thing on the card;
        // the exact number stops mattering and would cost a third character.
        if unresolvedThreads > 0 { return "T\(min(unresolvedThreads, 9))" }
        if reviewDecision == .approved { return "AP" }
        return "WR"
    }

    /// Short branch-style label for the card: `repo #123`.
    public var shortLabel: String {
        let name = repository.split(separator: "/").last.map(String.init) ?? repository
        return "\(name) #\(number)"
    }
}
