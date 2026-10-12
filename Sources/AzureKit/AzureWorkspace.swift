import DevDeckCore
import Foundation

/// What one account returned. Not a `Result`: the failure side is a report for the card to
/// show, not an error anyone throws.
private enum AccountOutcome: Sendable {
    case value(AzurePullRequestsSnapshot)
    case failure(AccountFailure)
}

/// Every configured Azure DevOps organization, fetched together and merged into one card.
///
/// The same rule as the GitHub and GitLab sides: the card fails only when *every* account
/// fails. One expired token out of two leaves the other organization's pull requests on screen
/// with a line saying which one is missing.
public struct AzureWorkspace: Sendable {
    public typealias ClientFactory = @Sendable (AzureAccount) -> AzureClient

    private let accounts: [AzureAccount]
    private let limit: Int
    private let makeClient: ClientFactory

    public init(accounts: [AzureAccount], tokenStore: any TokenStore, limit: Int = 20) {
        self.accounts = accounts
        self.limit = limit
        self.makeClient = { account in
            AzureClient.makeDefault(account: account, tokenStore: tokenStore)
        }
    }

    /// Injection point for the suite: the caller decides what each account's client talks to.
    public init(accounts: [AzureAccount], limit: Int = 20, clientFactory: @escaping ClientFactory) {
        self.accounts = accounts
        self.limit = limit
        self.makeClient = clientFactory
    }

    public var isEmpty: Bool { accounts.isEmpty }

    public func pullRequests() async throws -> AzurePullRequestsSnapshot {
        guard !accounts.isEmpty else { throw APIError.missingToken("Azure DevOps") }

        var values: [AzurePullRequestsSnapshot] = []
        var failures: [AccountFailure] = []

        await withTaskGroup(of: AccountOutcome.self) { group in
            for account in accounts {
                let client = makeClient(account)
                let limit = self.limit
                group.addTask {
                    do {
                        let snapshot = try await AzurePullRequestsService(client: client, account: account, limit: limit).fetch()
                        return .value(snapshot)
                    } catch {
                        return .failure(AccountFailure(account: account.label, accountID: account.id, error: error))
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

        // Thrown whole, so the card says which organization and why instead of "Forbidden".
        if values.isEmpty, !failures.isEmpty {
            throw APIError.accounts(failures)
        }
        return AzurePullRequestsSnapshot.merging(values, failures: failures)
    }
}
