import DevDeckCore
import Foundation

/// What one account returned. Not a `Result`: the failure side is a report for the card to
/// show, not an error anyone throws.
private enum AccountOutcome<Value: Sendable>: Sendable {
    case value(Value)
    case failure(AccountFailure)
}

/// Every configured GitHub account, fetched together and merged into one snapshot per card.
///
/// The rule throughout: a card fails only when *every* account fails. One expired token out
/// of four leaves the other three on screen with a note saying which one is missing, because
/// blanking a card over one account is how a deck stops being trusted.
public struct GitHubWorkspace: Sendable {
    public typealias ClientFactory = @Sendable (GitHubAccount, GitHubSettings) -> GitHubClient

    private let accounts: [GitHubAccount]
    private let settings: GitHubSettings
    private let makeClient: ClientFactory

    public init(
        accounts: [GitHubAccount],
        tokenStore: any TokenStore,
        settings: GitHubSettings = .default
    ) {
        self.accounts = accounts
        self.settings = settings
        self.makeClient = { account, accountSettings in
            GitHubClient.makeDefault(
                tokenStore: tokenStore,
                settings: accountSettings,
                tokenKey: account.tokenKey
            )
        }
    }

    /// Injection point for the suite: the caller decides what each account's client talks to.
    public init(
        accounts: [GitHubAccount],
        settings: GitHubSettings = .default,
        clientFactory: @escaping ClientFactory
    ) {
        self.accounts = accounts
        self.settings = settings
        self.makeClient = clientFactory
    }

    public var isEmpty: Bool { accounts.isEmpty }

    // MARK: Cards

    public func pullRequests() async throws -> PullRequestsSnapshot {
        let gathered = try await gather { account, client, accountSettings in
            try await PullRequestsService(
                client: client,
                settings: accountSettings,
                accountID: account.id
            ).fetch()
        }
        return PullRequestsSnapshot.merging(gathered.values, failures: gathered.failures)
    }

    public func inbox() async throws -> InboxSnapshot {
        let gathered = try await gather { account, client, accountSettings in
            try await NotificationsService(
                client: client,
                settings: accountSettings,
                accountID: account.id
            ).fetch()
        }
        return InboxSnapshot.merging(gathered.values, failures: gathered.failures)
    }

    /// Actions are per repository, and a repository belongs to exactly one account — asking
    /// every account for every repository would spend most requests on 404s.
    public func actions(repositoriesByAccount: [String: [String]]) async throws -> ActionsSnapshot {
        let wanted = accounts.filter { !(repositoriesByAccount[$0.id] ?? []).isEmpty }
        guard !wanted.isEmpty else {
            return ActionsSnapshot(runs: [], windowDays: settings.actionsWindowDays, repositories: [])
        }

        let gathered = try await gather(accounts: wanted) { account, client, accountSettings in
            try await ActionsService(
                client: client,
                settings: accountSettings,
                accountID: account.id
            ).fetch(repositories: repositoriesByAccount[account.id] ?? [])
        }
        return ActionsSnapshot.merging(gathered.values, failures: gathered.failures)
    }

    // MARK: Fan-out

    private struct Gathered<Value: Sendable>: Sendable {
        var values: [Value]
        var failures: [AccountFailure]
    }

    private func gather<Value: Sendable>(
        accounts overrideAccounts: [GitHubAccount]? = nil,
        _ work: @Sendable @escaping (GitHubAccount, GitHubClient, GitHubSettings) async throws -> Value
    ) async throws -> Gathered<Value> {
        let accounts = overrideAccounts ?? self.accounts
        guard !accounts.isEmpty else { throw APIError.missingToken("GitHub") }

        var values: [Value] = []
        var failures: [AccountFailure] = []

        await withTaskGroup(of: AccountOutcome<Value>.self) { group in
            for account in accounts {
                let accountSettings = account.settings(basedOn: settings)
                let client = makeClient(account, accountSettings)
                group.addTask {
                    do {
                        return .value(try await work(account, client, accountSettings))
                    } catch let error as APIError {
                        return .failure(AccountFailure(account: account.label, message: error.displayMessage))
                    } catch {
                        return .failure(AccountFailure(account: account.label, message: error.localizedDescription))
                    }
                }
            }
            for await outcome in group {
                switch outcome {
                case .value(let value): values.append(value)
                case .failure(let failure): failures.append(failure)
                }
            }
        }

        // Every account failed: this is a real card failure, not a partial one. The first
        // account's error is representative — they are almost always the same cause.
        if values.isEmpty, let first = failures.first {
            throw APIError.forbidden(accounts.count == 1 ? first.message : "\(failures.count) accounts failed: \(first.message)")
        }

        return Gathered(values: values, failures: failures)
    }
}
