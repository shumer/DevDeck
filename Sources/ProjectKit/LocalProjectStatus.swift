import Foundation

/// What a plain project is doing.
public enum LocalProjectState: String, Sendable, Equatable, Codable {
    /// The health URL answered, or the started process is alive and there is nothing else to
    /// ask.
    case running
    /// The process we started is alive but nothing is serving yet — a dev server compiling,
    /// or a container still coming up.
    case starting
    case stopped
    /// A command issued from the card is still going.
    case working
    /// No folder or no start command, so there is nothing to run or check.
    case unavailable
}

/// Everything a plain project card draws.
public struct LocalProjectStatus: Sendable, Equatable {
    public var state: LocalProjectState
    /// What is happening, or why the last command failed.
    public var detail: String?
    public var checkedAt: Date?
    /// The process this app started, when there is one.
    public var pid: Int32?
    /// Branch the checkout is on — what the local site is actually serving.
    public var branch: String?
    /// The repository this checkout came from, when it has an origin.
    public var repositoryURL: URL?
    /// Whether a log from a previous start is on disk to open.
    public var hasLog: Bool

    public init(
        state: LocalProjectState,
        detail: String? = nil,
        checkedAt: Date? = nil,
        pid: Int32? = nil,
        branch: String? = nil,
        repositoryURL: URL? = nil,
        hasLog: Bool = false
    ) {
        self.state = state
        self.detail = detail
        self.checkedAt = checkedAt
        self.pid = pid
        self.branch = branch
        self.repositoryURL = repositoryURL
        self.hasLog = hasLog
    }

    public static let unavailable = LocalProjectStatus(
        state: .unavailable,
        detail: "Set a folder and a start command in settings"
    )

    public var isRunning: Bool { state == .running }
    public var isBusy: Bool { state == .working }
}

/// What the card's buttons can ask a plain project to do.
public enum LocalProjectAction: String, Sendable, CaseIterable {
    case start
    case stop
    case restart

    public var title: String {
        switch self {
        case .start: return "Start"
        case .stop: return "Stop"
        case .restart: return "Restart"
        }
    }

    public var progressText: String {
        switch self {
        case .start: return "starting…"
        case .stop: return "stopping…"
        case .restart: return "restarting…"
        }
    }
}
