import Foundation

/// What Azure DevOps says about merging the source branch into the target, reduced to what a
/// row needs to know.
public enum AzureMergeState: String, Sendable, Equatable, Codable {
    /// The service merged the branches without conflict.
    case succeeded
    case conflicts
    /// The merge is still being computed, or the service has not tried yet.
    case pending
    /// The merge failed for a reason that is not a conflict, or a policy rejected it.
    case failed

    public init(apiValue: String?) {
        switch apiValue {
        case "succeeded": self = .succeeded
        case "conflicts": self = .conflicts
        case "failure", "rejectedByPolicy": self = .failed
        default: self = .pending
        }
    }
}

/// The one thing the card colours a row by, in the same three words the GitHub card uses.
public enum AzurePullRequestHealth: String, Sendable, Equatable, Codable {
    /// Cannot merge as it stands: a conflict, a rejection, or a reviewer waiting for the author.
    case blocked
    /// Waiting on somebody: no approval yet, a merge being computed, or a draft.
    case attention
    /// Approved and mergeable.
    case ready
}

public struct AzurePullRequestSummary: Sendable, Equatable, Codable, Identifiable {
    /// Stable across refreshes and unique in the organization: `{repositoryID}/{number}`.
    public let id: String
    /// The number people say out loud. Unique per organization in Azure DevOps, unlike GitHub's.
    public let number: Int
    public let title: String
    /// The team project the repository lives in.
    public let project: String
    public let repository: String
    public let url: URL
    public let isDraft: Bool
    public let merge: AzureMergeState
    /// When it was opened. The list endpoint says nothing about when it was last touched, so
    /// this is the one date a row has.
    public let createdAt: Date
    /// Reviewers who approved, with or without suggestions.
    public let approvals: Int
    /// A reviewer asked for changes: waiting for the author, or rejected outright.
    public let hasChangesRequested: Bool
    /// Reviewers Azure DevOps lists as required who have not voted yet.
    public let requiredVotesMissing: Int
    /// Which configured account this came from. Rows from several organizations share one card.
    public let accountID: String
    /// Somebody else's pull request, waiting on a vote from you.
    public let isReviewRequest: Bool
    /// Who opened it. Azure DevOps does not say who added a reviewer, so the author is who a
    /// review request is from.
    public let author: String?

    public init(
        id: String,
        number: Int,
        title: String,
        project: String,
        repository: String,
        url: URL,
        isDraft: Bool,
        merge: AzureMergeState,
        createdAt: Date,
        approvals: Int,
        hasChangesRequested: Bool,
        requiredVotesMissing: Int,
        accountID: String = AzureAccount.defaultID,
        isReviewRequest: Bool = false,
        author: String? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.project = project
        self.repository = repository
        self.url = url
        self.isDraft = isDraft
        self.merge = merge
        self.createdAt = createdAt
        self.approvals = approvals
        self.hasChangesRequested = hasChangesRequested
        self.requiredVotesMissing = requiredVotesMissing
        self.accountID = accountID
        self.isReviewRequest = isReviewRequest
        self.author = author
    }

    public var hasConflicts: Bool { merge == .conflicts }

    /// Nothing can move it: a conflict, a failed merge, or a reviewer who said no. A draft is
    /// not blocked, it is unfinished.
    ///
    /// A review somebody is waiting on is never blocked, whatever its state: the thing
    /// outstanding is you, which is how the GitHub card has always read it.
    public var health: AzurePullRequestHealth {
        if isReviewRequest { return .attention }
        if merge == .conflicts || merge == .failed || hasChangesRequested { return .blocked }
        if isDraft || merge == .pending || approvals == 0 || requiredVotesMissing > 0 { return .attention }
        return .ready
    }

    /// Two characters at the end of the row, in the GitHub card's vocabulary, because the two
    /// cards sit side by side. The most blocking fact wins.
    ///
    ///     RV  waiting for your vote     MC  merge conflict      CR  changes requested
    ///     CF  merge failed              DR  draft               CP  merge being computed
    ///     A1  one required vote left    AP  approved            WR  waiting for review
    public var statusCode: String {
        if isReviewRequest { return "RV" }
        if merge == .conflicts { return "MC" }
        if merge == .failed { return "CF" }
        if hasChangesRequested { return "CR" }
        if isDraft { return "DR" }
        if merge == .pending { return "CP" }
        if requiredVotesMissing > 0 { return "A\(min(requiredVotesMissing, 9))" }
        if approvals > 0 { return "AP" }
        return "WR"
    }

    /// The whole row in one sentence, for the tooltip. Mirrors `statusCode` case for case.
    public var statusLine: String {
        if isReviewRequest { return "waiting for your vote" }
        if merge == .conflicts { return "merge conflict" }
        if merge == .failed { return "merge failed" }
        if hasChangesRequested { return "changes requested" }
        if isDraft { return "draft" }
        if merge == .pending { return "merge being computed" }
        if requiredVotesMissing == 1 { return "1 required vote left" }
        if requiredVotesMissing > 1 { return "\(requiredVotesMissing) required votes left" }
        if approvals > 0 { return "approved" }
        return "waiting for review"
    }

    /// `project/repository #42`, how the attention rows place it.
    public var place: String { "\(project)/\(repository) #\(number)" }

    /// `project/repository#42`, for the tooltip.
    public var shortLabel: String { "\(project)/\(repository)#\(number)" }

    /// A ticket key at the front of the title, split off so the row can put it in its own
    /// column. Same rule as the GitHub card, including the spaces.
    public static func splitTicket(from title: String) -> (key: String?, subject: String) {
        let pattern = #"^([A-Z][A-Z0-9]{1,9}-\d+)\s*[-–—:]\s+(.+)$"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: title,
                range: NSRange(title.startIndex..<title.endIndex, in: title)
            ),
            let keyRange = Range(match.range(at: 1), in: title),
            let subjectRange = Range(match.range(at: 2), in: title)
        else { return (nil, title) }
        return (String(title[keyRange]), String(title[subjectRange]))
    }

    public var ticket: (key: String?, subject: String) {
        Self.splitTicket(from: title)
    }
}
