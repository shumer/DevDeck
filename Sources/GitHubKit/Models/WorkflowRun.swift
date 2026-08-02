import Foundation

public enum RunStatus: String, Sendable, Equatable, Codable {
    case queued
    case inProgress
    case completed
    case other

    public init(apiValue: String) {
        switch apiValue {
        case "queued", "waiting", "pending", "requested": self = .queued
        case "in_progress": self = .inProgress
        case "completed": self = .completed
        default: self = .other
        }
    }

    public var isActive: Bool { self == .queued || self == .inProgress }
}

public enum RunConclusion: String, Sendable, Equatable, Codable {
    case success
    case failure
    case cancelled
    case skipped
    case none

    public init(apiValue: String?) {
        switch apiValue {
        case "success": self = .success
        // `timed_out` and `action_required` end the same way for the person looking at the
        // card: the workflow did not pass.
        case "failure", "timed_out", "action_required", "startup_failure": self = .failure
        case "cancelled": self = .cancelled
        case "skipped", "neutral": self = .skipped
        default: self = .none
        }
    }

    /// Whether this run says anything about the health of the pipeline. Cancelled and skipped
    /// runs do not — counting them would drag the success rate down for no reason.
    public var countsTowardSuccessRate: Bool {
        self == .success || self == .failure
    }
}

public struct WorkflowRun: Sendable, Equatable, Codable, Identifiable {
    public let id: Int
    public let name: String
    public let repository: String
    public let branch: String
    public let status: RunStatus
    public let conclusion: RunConclusion
    public let startedAt: Date
    public let updatedAt: Date
    public let url: URL?
    public let accountID: String

    public init(
        id: Int,
        name: String,
        repository: String,
        branch: String,
        status: RunStatus,
        conclusion: RunConclusion,
        startedAt: Date,
        updatedAt: Date,
        url: URL?,
        accountID: String = GitHubAccount.defaultID
    ) {
        self.accountID = accountID
        self.id = id
        self.name = name
        self.repository = repository
        self.branch = branch
        self.status = status
        self.conclusion = conclusion
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.url = url
    }

    /// Wall-clock duration of a finished run. Nil while it is still going, because
    /// `updated_at` is then just "a moment ago" and would report a meaningless number.
    public var durationSeconds: TimeInterval? {
        guard status == .completed else { return nil }
        let duration = updatedAt.timeIntervalSince(startedAt)
        return duration > 0 ? duration : nil
    }

    public var shortRepository: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}
