import Foundation

/// What GitLab's pipeline says about the source branch.
public enum PipelineState: String, Sendable, Equatable, Codable {
    case success
    case failed
    case running
    case none

    public init(apiValue: String?) {
        switch apiValue {
        case "SUCCESS", "MANUAL": self = .success
        // A canceled pipeline is not a passing one, and neither is a failed job that the
        // project allows to fail. For a card, both mean "this will not merge as it stands".
        case "FAILED", "CANCELED", "CANCELLED": self = .failed
        case "RUNNING", "PENDING", "CREATED", "WAITING_FOR_RESOURCE", "PREPARING", "SCHEDULED":
            self = .running
        default: self = .none
        }
    }
}

/// The one thing the card colours a row by, in the same three words the GitHub card uses.
///
/// Deliberately the same vocabulary and the same order: the two cards sit on the same desktop,
/// and a reader who has learned what a red row means on one should not have to learn it twice.
public enum MergeRequestHealth: String, Sendable, Equatable, Codable {
    /// Cannot merge as it stands: the pipeline failed, or the branch conflicts.
    case blocked
    /// Waiting on somebody: approvals outstanding, a pipeline running, or a draft.
    case attention
    /// Approved, green, mergeable.
    case ready
}

public struct MergeRequestSummary: Sendable, Equatable, Codable, Identifiable {
    /// GitLab's global id, unique across projects and across instances.
    public let id: String
    /// The number people say out loud. Per project, not global, hence `!42` in GitLab's own
    /// shorthand rather than `#42`.
    public let iid: Int
    public let title: String
    /// Full path, `group/subgroup/project`, because the card is cross-project by definition.
    public let project: String
    public let url: URL
    public let isDraft: Bool
    public let hasConflicts: Bool
    public let updatedAt: Date
    public let pipeline: PipelineState
    /// How many approvals the merge request still needs, when the instance reports it.
    public let approvalsLeft: Int
    /// Unresolved discussion threads.
    public let unresolvedThreads: Int
    /// Which configured account this came from. Rows from several instances share one card.
    public let accountID: String
    /// Somebody else's merge request, waiting on a review from you.
    public let isReviewRequest: Bool
    /// Who opened it. GitLab does not say who asked for a review, so the author is who a
    /// review request is from.
    public let author: String?

    public init(
        id: String,
        iid: Int,
        title: String,
        project: String,
        url: URL,
        isDraft: Bool,
        hasConflicts: Bool,
        updatedAt: Date,
        pipeline: PipelineState,
        approvalsLeft: Int,
        unresolvedThreads: Int,
        accountID: String = GitLabAccount.defaultID,
        isReviewRequest: Bool = false,
        author: String? = nil
    ) {
        self.author = author
        self.id = id
        self.iid = iid
        self.title = title
        self.project = project
        self.url = url
        self.isDraft = isDraft
        self.hasConflicts = hasConflicts
        self.updatedAt = updatedAt
        self.pipeline = pipeline
        self.approvalsLeft = approvalsLeft
        self.unresolvedThreads = unresolvedThreads
        self.accountID = accountID
        self.isReviewRequest = isReviewRequest
    }

    /// The group a merge request belongs to, which is the first path component.
    public var group: String {
        String(project.split(separator: "/").first ?? "")
    }

    /// Nothing can move it: a red pipeline or a branch that will not merge. A draft is not
    /// blocked, it is unfinished, and those are different rows to look at.
    ///
    /// A review somebody is waiting on is never blocked, whatever its pipeline says: the thing
    /// outstanding is you, which is how the GitHub card has always read it. Calling it blocked
    /// put somebody else's red build into your count of stuck work.
    public var health: MergeRequestHealth {
        if isReviewRequest { return .attention }
        if hasConflicts || pipeline == .failed { return .blocked }
        if isDraft || pipeline == .running || approvalsLeft > 0 || unresolvedThreads > 0 {
            return .attention
        }
        return .ready
    }

    /// Two characters at the end of the row, in the GitHub card's vocabulary, because the two
    /// cards sit side by side and `CF` meaning conflicts on one and failed checks on the other
    /// was a code that had to be learned twice. The most blocking fact wins.
    ///
    ///     RV  waiting for your review    CF  pipeline failed     MC  merge conflict
    ///     DR  draft                      CP  pipeline running    A2  two approvals left
    ///     T3  three unresolved threads   AP  ready to merge
    public var statusCode: String {
        if isReviewRequest { return "RV" }
        // A conflict first: until it is resolved a pipeline result is about code that will not
        // be merged.
        if hasConflicts { return "MC" }
        if pipeline == .failed { return "CF" }
        if isDraft { return "DR" }
        if pipeline == .running { return "CP" }
        if approvalsLeft > 0 { return "A\(min(approvalsLeft, 9))" }
        if unresolvedThreads > 0 { return "T\(min(unresolvedThreads, 9))" }
        return "AP"
    }

    /// The whole row in one sentence, for the tooltip.
    public var statusLine: String {
        var parts: [String] = []
        if isReviewRequest { parts.append("waiting for your review") }
        if isDraft { parts.append("draft") }
        if hasConflicts { parts.append("conflicts") }
        switch pipeline {
        case .failed: parts.append("pipeline failed")
        case .running: parts.append("pipeline running")
        case .success: parts.append("pipeline passed")
        case .none: break
        }
        if approvalsLeft > 0 {
            parts.append("\(approvalsLeft) approval\(approvalsLeft == 1 ? "" : "s") left")
        }
        if unresolvedThreads > 0 {
            parts.append("\(unresolvedThreads) unresolved")
        }
        return parts.isEmpty ? "ready to merge" : parts.joined(separator: ", ")
    }

    /// `group/project!42`, which is how GitLab itself writes a merge request.
    public var shortLabel: String { "\(project)!\(iid)" }

    /// The project as the row shows it: the last path component, since the group repeats on
    /// every row and the project does not.
    public var shortProject: String {
        String(project.split(separator: "/").last ?? "")
    }

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
