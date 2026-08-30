import DevDeckCore
import Foundation

/// What one account returned. Not a `Result`: the failure side is a report for the card to
/// show, not an error anyone throws.
private enum AccountOutcome: Sendable {
    case value(MergeRequestsSnapshot)
    case failure(AccountFailure)
}

/// Every configured GitLab instance, fetched together and merged into one card.
///
/// The same rule as the GitHub side: the card fails only when *every* account fails. One
/// expired token out of two leaves the other instance's merge requests on screen with a line
/// saying which one is missing, because blanking a card over one account is how a deck stops
/// being trusted.
public struct GitLabWorkspace: Sendable {
    public typealias ClientFactory = @Sendable (GitLabAccount) -> GitLabClient

    private let accounts: [GitLabAccount]
    private let limit: Int
    private let makeClient: ClientFactory

    public init(accounts: [GitLabAccount], tokenStore: any TokenStore, limit: Int = 20) {
        self.accounts = accounts
        self.limit = limit
        self.makeClient = { account in
            GitLabClient.makeDefault(account: account, tokenStore: tokenStore)
        }
    }

    /// Injection point for the suite: the caller decides what each account's client talks to.
    public init(accounts: [GitLabAccount], limit: Int = 20, clientFactory: @escaping ClientFactory) {
        self.accounts = accounts
        self.limit = limit
        self.makeClient = clientFactory
    }

    public var isEmpty: Bool { accounts.isEmpty }

    public func mergeRequests() async throws -> MergeRequestsSnapshot {
        guard !accounts.isEmpty else { throw APIError.missingToken("GitLab") }

        var values: [MergeRequestsSnapshot] = []
        var failures: [AccountFailure] = []

        await withTaskGroup(of: AccountOutcome.self) { group in
            for account in accounts {
                let client = makeClient(account)
                let limit = self.limit
                group.addTask {
                    do {
                        let snapshot = try await MergeRequestsService(
                            client: client,
                            accountID: account.id,
                            limit: limit
                        ).fetch()
                        return .value(snapshot)
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

        if values.isEmpty, let first = failures.first {
            throw APIError.forbidden(
                accounts.count == 1 ? first.message : "\(failures.count) accounts failed: \(first.message)"
            )
        }
        return MergeRequestsSnapshot.merging(values, failures: failures)
    }
}
