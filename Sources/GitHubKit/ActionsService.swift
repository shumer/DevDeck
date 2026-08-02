import DevDeckCore
import Foundation

/// Workflow runs across the repositories the deck watches.
///
/// One request per repository, each with its own `ETag`, so a quiet repository costs nothing
/// on the next poll.
public struct ActionsService: Sendable {
    private let client: GitHubClient
    private let settings: GitHubSettings
    private let clock: any DateProvider

    public init(
        client: GitHubClient,
        settings: GitHubSettings = .default,
        clock: any DateProvider = SystemDateProvider()
    ) {
        self.client = client
        self.settings = settings
        self.clock = clock
    }

    /// Fetches runs for `repositories`, or for the configured list when none are given.
    ///
    /// A repository that answers 404 or 403 is skipped rather than failing the whole card:
    /// with several repositories on one card, one archived or newly-private repository would
    /// otherwise blank out everything else. The error only surfaces when every repository fails.
    public func fetch(repositories: [String]? = nil) async throws -> ActionsSnapshot {
        let names = repositories ?? settings.actionsRepositories
        guard !names.isEmpty else {
            return ActionsSnapshot(runs: [], windowDays: settings.actionsWindowDays, repositories: [])
        }

        let since = Self.windowStart(from: clock.now, days: settings.actionsWindowDays)

        var runs: [WorkflowRun] = []
        var failures: [APIError] = []

        await withTaskGroup(of: Result<[WorkflowRun], APIError>.self) { group in
            for name in names {
                group.addTask {
                    do {
                        return .success(try await fetchRepository(name, since: since))
                    } catch let error as APIError {
                        return .failure(error)
                    } catch {
                        return .failure(.transport(error.localizedDescription))
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let repositoryRuns): runs.append(contentsOf: repositoryRuns)
                case .failure(let error): failures.append(error)
                }
            }
        }

        if runs.isEmpty, failures.count == names.count, let first = failures.first {
            throw first
        }

        return ActionsSnapshot(
            runs: runs.sorted { $0.startedAt > $1.startedAt },
            windowDays: settings.actionsWindowDays,
            repositories: names
        )
    }

    private func fetchRepository(_ name: String, since: String) async throws -> [WorkflowRun] {
        let result: RESTResult<WorkflowRunsPayload> = try await client.get(
            path: "repos/\(name)/actions/runs",
            query: [
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "created", value: ">=\(since)"),
            ],
            cacheKey: "github.actions.\(name)"
        )
        return result.value.workflowRuns.map { Self.run(from: $0, repository: name) }
    }

    /// GitHub's `created` filter takes a plain date, in UTC.
    public static func windowStart(from now: Date, days: Int) -> String {
        let start = now.addingTimeInterval(-Double(max(days, 1)) * 86_400)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }

    static func run(from payload: WorkflowRunsPayload.Run, repository: String) -> WorkflowRun {
        WorkflowRun(
            id: payload.id,
            name: payload.name ?? "workflow",
            repository: repository,
            branch: payload.headBranch ?? "",
            status: RunStatus(apiValue: payload.status),
            conclusion: RunConclusion(apiValue: payload.conclusion),
            // `run_started_at` is absent on older runs; `created_at` is the next best anchor.
            startedAt: payload.runStartedAt ?? payload.createdAt,
            updatedAt: payload.updatedAt,
            url: payload.htmlURL
        )
    }
}

// MARK: - Wire format

public struct WorkflowRunsPayload: Decodable, Sendable {
    let totalCount: Int
    let workflowRuns: [Run]

    public struct Run: Decodable, Sendable {
        let id: Int
        let name: String?
        let headBranch: String?
        let status: String
        let conclusion: String?
        let createdAt: Date
        let runStartedAt: Date?
        let updatedAt: Date
        let htmlURL: URL?

        enum CodingKeys: String, CodingKey {
            case id, name, status, conclusion
            case headBranch = "head_branch"
            case createdAt = "created_at"
            case runStartedAt = "run_started_at"
            case updatedAt = "updated_at"
            case htmlURL = "html_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }
}
