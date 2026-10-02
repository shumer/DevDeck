import DevDeckCore
import Foundation
import GitHubKit
import GitLabKit

/// Credentials arrive only on the inherited stdin pipe. No environment or file fallback.
public struct WorkerRemoteAccount: Codable, Sendable {
    public let id: String
    public let label: String
    public let endpoint: String
    public let organizations: [String]
    public let repositories: [String]
    public let token: String?
    public let cacheScope: String?
    public init(id: String, label: String, endpoint: String, organizations: [String] = [], repositories: [String] = [], token: String? = nil, cacheScope: String? = nil) {
        self.id = id; self.label = label; self.endpoint = endpoint
        self.organizations = organizations; self.repositories = repositories; self.token = token
        self.cacheScope = cacheScope
    }
}
public struct WorkerRemoteRequest: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case pullRequests, inbox, actions, mergeRequests }
    public let cardID: String
    public let kind: Kind
    public let accounts: [WorkerRemoteAccount]
    public let threadIDs: [String]?
    public let lastReadAt: TimeInterval?
    public init(cardID: String, kind: Kind, accounts: [WorkerRemoteAccount], threadIDs: [String]? = nil, lastReadAt: TimeInterval? = nil) {
        self.cardID = cardID; self.kind = kind; self.accounts = accounts
        self.threadIDs = threadIDs; self.lastReadAt = lastReadAt
    }
}
public struct WorkerRemoteRow: Codable, Sendable {
    public let id: String
    public let accountID: String
    public let title: String
    public let repository: String
    public let url: String?
    public let health: String
    public let detail: String
    public let needsReview: Bool
    public var statusCode: String? = nil
    public var updatedAt: TimeInterval? = nil
    public var isUnread: Bool = true
    public var ticketKey: String? = nil
    public var subject: String? = nil
}
public struct WorkerRemoteAccountFailure: Codable, Sendable {
    public let accountID: String?
    public let kind: String
    public var resetAt: TimeInterval? = nil
    public init(accountID: String?, kind: String, resetAt: TimeInterval? = nil) {
        self.accountID = accountID; self.kind = kind; self.resetAt = resetAt
    }
}
public struct WorkerRemoteSnapshot: Codable, Sendable {
    public let cardID: String
    public let kind: WorkerRemoteRequest.Kind
    public let total: Int
    public let blocked: Int
    public let successRate: Double?
    public let rows: [WorkerRemoteRow]
    public let failures: [WorkerRemoteAccountFailure]
    public let capped: Bool
    public var attention: [WorkerRemoteAttention] = []
    public var pollIntervalSeconds: TimeInterval? = nil
    public var signals: WorkerAttentionSnapshot? = nil
    public var repositoryCount: Int = 0
    public var namespaceCount: Int = 0
    public var reviewCount: Int = 0
    public var actionableCount: Int = 0
    public var runningCount: Int = 0
    public var windowDays: Int = 7
    public var averageDurationSeconds: TimeInterval? = nil
    public var watchedRepositories: [String] = []
    public var followsPullRequests: Bool = false
    public init(cardID: String, kind: WorkerRemoteRequest.Kind, total: Int, blocked: Int, successRate: Double?, rows: [WorkerRemoteRow], failures: [WorkerRemoteAccountFailure], capped: Bool) {
        self.cardID = cardID; self.kind = kind; self.total = total; self.blocked = blocked; self.successRate = successRate
        self.rows = rows; self.failures = failures; self.capped = capped
    }
}
public struct WorkerRemoteAttention: Codable, Sendable {
    public let id: String
    public let key: String
    public let accountID: String
    public let kind: String
    public let title: String
    public let url: String?
}
public struct WorkerRemoteError: Error, Sendable {
    public let code: String
    public let message: String
    public var failures: [WorkerRemoteAccountFailure] = []
}

/// All query, merge, pagination and health rules stay in the existing shared workspaces.
public struct WorkerRemoteService: Sendable {
    private let http: any HTTPClient
    private let cache = WorkerRemoteCache()
    public init(http: any HTTPClient = URLSessionHTTPClient.makeDefault()) { self.http = http }

    public func fetch(_ request: WorkerRemoteRequest) async throws -> WorkerRemoteSnapshot {
        try Self.validate(request)
        let tokens = InMemoryTokenStore()
        let githubAccounts = request.accounts.map {
            GitHubAccount(id: $0.id, label: $0.label, apiBaseURL: URL(string: $0.endpoint)!, organizations: $0.organizations)
        }
        let gitlabAccounts = request.accounts.map {
            GitLabAccount(id: $0.id, label: $0.label, host: URL(string: $0.endpoint)!)
        }
        for (index, account) in request.accounts.enumerated() {
            try tokens.setToken(account.token, for: request.kind == .mergeRequests ? gitlabAccounts[index].tokenKey : githubAccounts[index].tokenKey)
        }
        let http = self.http
        var transports: [String: APITransport] = [:]
        for account in request.accounts {
            transports[account.id] = await cache.transport(account: account, provider: request.kind == .mergeRequests ? "gitlab" : "github", http: http)
        }
        let accountTransports = transports
        let github = GitHubWorkspace(accounts: githubAccounts, clientFactory: { account, settings in
            GitHubClient(transport: accountTransports[account.id]!, tokenStore: tokens, settings: settings, tokenKey: account.tokenKey)
        })
        let follows = Set(request.accounts.filter { $0.repositories.isEmpty }.map(\.id))
        let fallback = GitHubWorkspace(accounts: githubAccounts.filter { follows.contains($0.id) }, clientFactory: { account, settings in
            GitHubClient(transport: accountTransports[account.id]!, tokenStore: tokens, settings: settings, tokenKey: account.tokenKey)
        })
        let gitlab = GitLabWorkspace(accounts: gitlabAccounts, clientFactory: { account in
            GitLabClient(transport: accountTransports[account.id]!, tokenStore: tokens, account: account)
        })
        return try await snapshot(request, github: github, gitlab: gitlab, fallback: fallback)
    }

    private static func validate(_ request: WorkerRemoteRequest) throws {
        guard Self.validID(request.cardID), !request.accounts.isEmpty, request.accounts.count <= 32,
              Set(request.accounts.map(\.id)).count == request.accounts.count else { throw Self.invalid() }
        for account in request.accounts {
            guard Self.validID(account.id), !account.label.isEmpty, account.label.utf8.count <= 256,
                  !account.label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  Self.validEndpoint(account.endpoint), account.organizations.count <= 64, account.repositories.count <= 64,
                  account.organizations.allSatisfy({ Self.validSlug($0) }),
                  account.repositories.allSatisfy({ $0.split(separator: "/", omittingEmptySubsequences: false).count == 2 && $0.split(separator: "/").allSatisfy { Self.validSlug(String($0)) } }),
                  account.cacheScope.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) } }) ?? true,
                  account.token.map({ !$0.isEmpty && $0.utf8.count <= 2560 && !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }) ?? true
            else { throw Self.invalid() }
        }
    }

    private func snapshot(_ request: WorkerRemoteRequest, github: GitHubWorkspace, gitlab: GitLabWorkspace, fallback: GitHubWorkspace) async throws -> WorkerRemoteSnapshot {
        // Only sanitized kinds cross the pipe; upstream error bodies can contain credentials.
        func failures(_ values: [AccountFailure]) -> [WorkerRemoteAccountFailure] {
            values.map { WorkerRemoteAccountFailure(accountID: $0.accountID, kind: $0.kind.rawValue, resetAt: $0.resetAt?.timeIntervalSince1970) }
        }
        func attention(_ items: [AttentionItem], rows: [WorkerRemoteRow], service: String) -> [WorkerRemoteAttention] {
            items.compactMap { item in
                let url: URL?
                let accountID: String
                let row: WorkerRemoteRow?
                if case .open(let address, _, let account) = item.action {
                    url = address; accountID = account
                    row = rows.first { $0.accountID == account && $0.url == address.absoluteString }
                } else {
                    guard let matching = rows.first(where: { item.id == "inbox:" + $0.id }) else { return nil }
                    row = matching; accountID = matching.accountID; url = nil
                }
                let kind = item.id.hasPrefix("review:") || row?.needsReview == true ? "review" : item.id.hasPrefix("run:") ? "run" : item.id.hasPrefix("stuck:") ? "blocked" : "inbox"
                if kind == "review", let url { return WorkerRemoteAttention(id: item.id, key: service + ":review:" + url.absoluteString, accountID: accountID, kind: kind, title: row?.title ?? "Remote item", url: url.absoluteString) }
                return WorkerRemoteAttention(id: item.id, key: service + ":" + item.id, accountID: accountID, kind: kind, title: row?.title ?? "Remote item", url: url?.absoluteString)
            }
        }
        do {
            switch request.kind {
            case .pullRequests:
                let value = try await github.pullRequests()
                var result = WorkerRemoteSnapshot(cardID: request.cardID, kind: request.kind, total: value.totalCount, blocked: value.blockedCount, successRate: nil,
                    rows: value.prioritized().map { WorkerRemoteRow(id: $0.id, accountID: $0.accountID, title: $0.title, repository: $0.repository, url: $0.url.absoluteString,
                        health: $0.health.rawValue, detail: $0.statusLine, needsReview: $0.isReviewRequest, statusCode: $0.statusCode,
                        updatedAt: $0.updatedAt.timeIntervalSince1970, ticketKey: $0.ticket.key, subject: $0.ticket.subject) }, failures: failures(value.failures), capped: value.totalCount > value.pullRequests.count)
                result.repositoryCount = value.repositoryCount; result.namespaceCount = value.organizationCount; result.reviewCount = value.reviewRequestCount
                result.attention = attention(GitHubAttention.items(pullRequests: value, inbox: nil, actions: nil, labels: [:]), rows: result.rows, service: "github")
                result.signals = WorkerAttentionSnapshot(scope: request.cardID, items: GitHubAttention.items(pullRequests: value, inbox: nil, actions: nil, labels: Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0.label) })), alerts: GitHubAttention.alerts(pullRequests: value, labels: Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0.label) })))
                return result
            case .mergeRequests:
                let value = try await gitlab.mergeRequests()
                var result = WorkerRemoteSnapshot(cardID: request.cardID, kind: request.kind, total: value.totalCount, blocked: value.blockedCount, successRate: nil,
                    rows: value.prioritized().map { WorkerRemoteRow(id: $0.id, accountID: $0.accountID, title: $0.title, repository: $0.project, url: $0.url.absoluteString,
                        health: $0.health.rawValue, detail: $0.statusLine, needsReview: $0.isReviewRequest, statusCode: $0.statusCode,
                        updatedAt: $0.updatedAt.timeIntervalSince1970, ticketKey: $0.ticket.key, subject: $0.ticket.subject) }, failures: failures(value.failures), capped: value.totalCount > value.mergeRequests.count)
                result.repositoryCount = value.projectCount; result.namespaceCount = value.groupCount; result.reviewCount = value.reviewRequestCount
                result.attention = attention(GitLabAttention.items(mergeRequests: value, labels: [:]), rows: result.rows, service: "gitlab")
                result.signals = WorkerAttentionSnapshot(scope: request.cardID, items: GitLabAttention.items(mergeRequests: value, labels: Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0.label) })), alerts: GitLabAttention.alerts(mergeRequests: value, labels: Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0.label) })))
                return result
            case .inbox:
                let value = try await github.inbox()
                var result = WorkerRemoteSnapshot(cardID: request.cardID, kind: request.kind, total: value.unreadCount, blocked: 0, successRate: nil,
                    rows: value.prioritized().map { WorkerRemoteRow(id: $0.id, accountID: $0.accountID, title: $0.title, repository: $0.repository, url: $0.url?.absoluteString,
                        health: $0.reason.isForYou ? "attention" : "ready", detail: $0.reason.rawValue, needsReview: $0.reason == .reviewRequested,
                        updatedAt: $0.updatedAt.timeIntervalSince1970, isUnread: $0.isUnread) }, failures: failures(value.failures), capped: value.isCapped)
                result.repositoryCount = value.repositoryCount; result.actionableCount = value.actionableCount
                let projected = WorkerInboxAttention.project(value, request: request)
                result.attention = projected.attention
                result.signals = projected.signals
                if let interval = value.serverPollInterval, interval.isFinite, interval > 0 {
                    result.pollIntervalSeconds = max(60, min(86400, interval))
                }
                return result
            case .actions:
                var repositories = Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0.repositories) })
                var fallbackFailures: [AccountFailure] = []
                if request.accounts.contains(where: { $0.repositories.isEmpty }) {
                    do {
                        let pullRequests = try await fallback.pullRequests()
                        fallbackFailures = pullRequests.failures
                        let followed = ActionsWatchList.repositoriesByAccount(configured: [], accounts: [], pullRequests: pullRequests)
                        for account in request.accounts where account.repositories.isEmpty { repositories[account.id] = followed[account.id] ?? [] }
                    } catch let error as APIError {
                        if case .accounts(let values) = error { fallbackFailures = values }
                        else { throw error }
                    }
                }
                if repositories.values.allSatisfy({ $0.isEmpty }), fallbackFailures.count == request.accounts.count {
                    throw APIError.accounts(fallbackFailures)
                }
                let value = try await github.actions(repositoriesByAccount: repositories)
                // Keep card-relevant failures/active runs inside the transport ceiling, even when
                // many more recent successful runs exist across watched repositories.
                let prioritizedRuns = value.recentFailures() + value.active() + value.runs.filter { $0.conclusion != .failure && !$0.status.isActive }
                var result = WorkerRemoteSnapshot(cardID: request.cardID, kind: request.kind, total: value.runs.count, blocked: value.failedCount, successRate: value.successRate,
                    rows: prioritizedRuns.prefix(100).map { WorkerRemoteRow(id: String($0.id), accountID: $0.accountID, title: $0.name, repository: $0.repository, url: $0.url?.absoluteString,
                        health: $0.conclusion == .failure ? "blocked" : $0.status.isActive ? "attention" : "ready", detail: $0.branch + " · " + $0.conclusion.rawValue, needsReview: false,
                        updatedAt: $0.updatedAt.timeIntervalSince1970) }, failures: failures(fallbackFailures + value.failures), capped: value.runs.count > 100)
                result.repositoryCount = value.repositories.count; result.watchedRepositories = value.repositories
                result.windowDays = value.windowDays; result.averageDurationSeconds = value.averageDurationSeconds; result.runningCount = value.runningCount
                result.followsPullRequests = request.accounts.allSatisfy { $0.repositories.isEmpty }
                result.attention = attention(GitHubAttention.items(pullRequests: nil, inbox: nil, actions: value, labels: [:]), rows: result.rows, service: "github")
                result.signals = WorkerAttentionSnapshot(scope: request.cardID, items: GitHubAttention.items(pullRequests: nil, inbox: nil, actions: value, labels: Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0.label) })), alerts: GitHubAttention.alerts(actions: value, labels: Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0.label) })))
                return result
            }
        } catch let error as APIError {
            if case .accounts(let values) = error {
                // Do not turn an all-account failure into a successful empty deck.
                let rejected = values.allSatisfy { $0.kind == .rejected }
                throw WorkerRemoteError(code: rejected ? "credentialsRejected" : "remoteUnavailable",
                    message: rejected ? "Account tokens are missing or rejected. Update them in Settings." : "Remote accounts could not be refreshed. Check permissions, rate limits or network.", failures: failures(values))
            }
            throw WorkerRemoteError(code: "remoteUnavailable", message: "Remote refresh failed. Check account permissions or network.")
        }
    }
    private struct EmptyVariables: Encodable, Sendable {}
    public func markRead(_ request: WorkerRemoteRequest, rest: Bool, onProgress: (@Sendable (String) -> Void)? = nil) async throws {
        try Self.validate(request)
        guard request.kind == .inbox, request.accounts.count == 1, let account = request.accounts.first,
              let token = account.token else { throw Self.invalid() }
        let ids = request.threadIDs ?? []
        guard rest || (!ids.isEmpty && ids.count <= 50 && ids.allSatisfy { !$0.isEmpty && $0.utf8.count <= 32 && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }) else { throw Self.invalid() }
        let model = GitHubAccount(id: account.id, label: account.label, apiBaseURL: URL(string: account.endpoint)!, organizations: account.organizations)
        let tokens = InMemoryTokenStore(tokens: [model.tokenKey: token])
        await cache.invalidate(account: account, provider: "github")
        // The shared bulk helper replenishes its queue after every completion. Preserve the
        // worker's cancellation boundary before a cancelled child delegates another request.
        struct ReadAdmissionHTTP: HTTPClient {
            let base: any HTTPClient
            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                try Task.checkCancellation()
                return try await base.send(request)
            }
        }
        let client = GitHubClient(transport: APITransport(client: ReadAdmissionHTTP(base: http)), tokenStore: tokens, settings: model.settings(basedOn: .default), tokenKey: model.tokenKey)
        let service = NotificationsService(client: client, accountID: account.id)
        do {
            let targets: [String]
            if rest { onProgress?("gathering"); targets = try await service.unreadThreads().filter { $0.isUnread && !$0.reason.isForYou }.map(\.id) }
            else { targets = ids }
            guard targets.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 32 && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }) else { throw Self.invalid() }
            try Task.checkCancellation()
            let failures = await service.markRead(targets, concurrency: 6) { done in
                onProgress?("marking:\(done):\(targets.count)")
            }
            try Task.checkCancellation()
            if let refusal = failures.values.first { throw refusal }
        } catch {
            throw WorkerRemoteError(code: "remoteActionFailed", message: "GitHub could not mark notifications as read. Check notification permissions and refresh; some threads may already be read.")
        }
    }
    public func markAllRead(_ request: WorkerRemoteRequest, onProgress: (@Sendable (String) -> Void)? = nil) async throws {
        try Self.validate(request)
        guard request.kind == .inbox, request.accounts.count == 1, request.threadIDs == nil,
              let account = request.accounts.first, let token = account.token,
              let cutoff = request.lastReadAt, cutoff.isFinite, cutoff > 0,
              cutoff <= Date().timeIntervalSince1970 + 300 else { throw Self.invalid() }
        let model = GitHubAccount(id: account.id, label: account.label, apiBaseURL: URL(string: account.endpoint)!, organizations: account.organizations)
        let tokens = InMemoryTokenStore(tokens: [model.tokenKey: token])
        await cache.invalidate(account: account, provider: "github")
        let client = GitHubClient(transport: APITransport(client: http), tokenStore: tokens, settings: model.settings(basedOn: .default), tokenKey: model.tokenKey)
        do {
            try Task.checkCancellation(); onProgress?("markingAll")
            try await NotificationsService(client: client, accountID: account.id).markAllRead(upTo: Date(timeIntervalSince1970: cutoff))
        } catch { throw WorkerRemoteError(code: "remoteActionFailed", message: "GitHub could not mark notifications as read. Check notification permissions and refresh.") }
    }
    private struct GitHubIdentity: Decodable, Sendable { struct User: Decodable, Sendable { let login: String }; let viewer: User? }
    private struct GitLabIdentity: Decodable, Sendable { struct User: Decodable, Sendable { let username: String }; let currentUser: User? }
    public func verify(_ request: WorkerRemoteRequest) async throws {
        try Self.validate(request)
        guard request.accounts.count == 1, let account = request.accounts.first, let token = account.token else {
            throw WorkerRemoteError(code: "credentialsRejected", message: "Enter a token for this account.")
        }
        let tokens = InMemoryTokenStore()
        do {
            if request.kind == .mergeRequests {
                let model = GitLabAccount(id: account.id, label: account.label, host: URL(string: account.endpoint)!)
                try tokens.setToken(token, for: model.tokenKey)
                let client = GitLabClient(transport: APITransport(client: http), tokenStore: tokens, account: model)
                let value: GitLabIdentity = try await client.graphQL(query: "query DevDeckVerify { currentUser { username } }", variables: EmptyVariables())
                guard let user = value.currentUser, !user.username.isEmpty else { throw APIError.unauthorized }
            } else {
                let model = GitHubAccount(id: account.id, label: account.label, apiBaseURL: URL(string: account.endpoint)!)
                try tokens.setToken(token, for: model.tokenKey)
                let client = GitHubClient(transport: APITransport(client: http), tokenStore: tokens, settings: model.settings(basedOn: .default), tokenKey: model.tokenKey)
                let value: GitHubIdentity = try await client.graphQL(query: "query DevDeckVerify { viewer { login } }", variables: EmptyVariables())
                guard let user = value.viewer, !user.login.isEmpty else { throw APIError.unauthorized }
            }
        } catch {
            throw WorkerRemoteError(code: "credentialsRejected", message: "Token verification failed. Check the token, endpoint, permissions or network; the token was not saved.")
        }
    }
    private static func validID(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 128 && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private static func validSlug(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 128 && text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }
    }
    private static func validEndpoint(_ text: String) -> Bool {
        guard let parts = URLComponents(string: text), parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil, text.utf8.count <= 2048 else { return false }
        return true
    }
    private static func invalid() -> WorkerRemoteError {
        WorkerRemoteError(code: "invalidRemote", message: "Remote card requires stable account IDs, HTTPS endpoints and valid organization/repository names.")
    }
}
