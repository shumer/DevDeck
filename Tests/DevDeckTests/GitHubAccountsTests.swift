import DevDeckCore
import Foundation
import GitHubKit
import TestHarness

private func summary(
    id: String,
    repository: String = "editoria/ledwall",
    accountID: String,
    updatedAt: TimeInterval = 1_000
) -> PullRequestSummary {
    PullRequestSummary(
        id: id,
        number: 1,
        title: id,
        repository: repository,
        organization: String(repository.split(separator: "/")[0]),
        url: URL(string: "https://github.com/\(repository)/pull/1")!,
        isDraft: false,
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        reviewDecision: .none,
        checks: .success,
        unresolvedThreads: 0,
        accountID: accountID
    )
}

func runAccountsTests(_ run: TestRun) async {
    run.section("Accounts - identity")

    await run.test("the first account keeps the original token key") {
        try expectEqual(GitHubAccount.default.tokenKey, TokenKey.github,
                        "a token stored before accounts existed must keep working")
        let second = GitHubAccount(id: "editoria", label: "Editoria")
        try expectEqual(second.tokenKey, TokenKey(account: "github.editoria"))
    }

    await run.test("identifiers are slugged and never collide") {
        try expectEqual(GitHubAccount.makeID(from: "Editoria XP!", existing: []), "editoria-xp")
        try expectEqual(GitHubAccount.makeID(from: "  ", existing: []), "account")
        try expectEqual(GitHubAccount.makeID(from: "Work", existing: ["work"]), "work-2")
        try expectEqual(GitHubAccount.makeID(from: "Work", existing: ["work", "work-2"]), "work-3")
    }

    await run.test("account settings layer over the deck-wide ones") {
        let base = GitHubSettings(maxPullRequests: 30, organizations: ["fallback"])
        let account = GitHubAccount(
            id: "editoria",
            label: "Editoria",
            apiBaseURL: URL(string: "https://github.example.com/api/v3")!,
            organizations: ["editoria", "shumer"]
        )
        let settings = account.settings(basedOn: base)
        try expectEqual(settings.maxPullRequests, 30, "unrelated settings are kept")
        try expectEqual(settings.apiBaseURL.absoluteString, "https://github.example.com/api/v3")
        try expectEqual(settings.organizations, ["editoria", "shumer"])

        let openAccount = GitHubAccount(id: "open", label: "Open")
        try expectEqual(openAccount.settings(basedOn: base).organizations, ["fallback"],
                        "an account with no organisations does not clear the deck-wide list")
    }

    run.section("Accounts - storage")

    await run.test("an unconfigured deck still has one account") {
        let store = GitHubAccountsStore(backend: InMemoryPreferences())
        try expectEqual(store.accounts().count, 1)
        try expectEqual(store.accounts().first?.id, GitHubAccount.defaultID)
    }

    await run.test("accounts round trip and can be disabled") {
        let backend = InMemoryPreferences()
        let store = GitHubAccountsStore(backend: backend)
        store.save([
            GitHubAccount(id: "work", label: "Work"),
            GitHubAccount(id: "personal", label: "Personal", isEnabled: false),
        ])
        try expectEqual(store.accounts().count, 2)
        try expectEqual(store.enabledAccounts().map(\.id), ["work"])
    }

    await run.test("saving an empty list falls back to the default account") {
        let store = GitHubAccountsStore(backend: InMemoryPreferences())
        store.save([])
        try expectEqual(store.accounts().map(\.id), [GitHubAccount.defaultID])
    }

    await run.test("a corrupt list falls back rather than leaving no accounts") {
        let backend = InMemoryPreferences()
        backend.set(Data("nonsense".utf8), forKey: "github.accounts")
        try expectEqual(GitHubAccountsStore(backend: backend).accounts().count, 1)
    }

    run.section("Accounts - merging")

    await run.test("pull requests from two accounts land on one card") {
        let merged = PullRequestsSnapshot.merging([
            PullRequestsSnapshot(totalCount: 2, pullRequests: [
                summary(id: "a", accountID: "work"),
                summary(id: "b", accountID: "work"),
            ]),
            PullRequestsSnapshot(totalCount: 1, pullRequests: [
                summary(id: "c", repository: "shumer/tools", accountID: "personal"),
            ]),
        ])
        try expectEqual(merged.totalCount, 3)
        try expectEqual(merged.pullRequests.count, 3)
        try expectEqual(merged.repositoryCount, 2)
        try expect(merged.failures.isEmpty)
    }

    await run.test("a pull request visible to both accounts is counted once") {
        let merged = PullRequestsSnapshot.merging([
            PullRequestsSnapshot(totalCount: 1, pullRequests: [summary(id: "same", accountID: "work")]),
            PullRequestsSnapshot(totalCount: 1, pullRequests: [summary(id: "same", accountID: "personal")]),
        ])
        try expectEqual(merged.pullRequests.count, 1)
        try expectEqual(merged.totalCount, 1, "the total must match the list it summarises")
    }

    await run.test("the inbox takes the longest poll interval any server asked for") {
        let merged = InboxSnapshot.merging([
            InboxSnapshot(items: [], serverPollInterval: 60),
            InboxSnapshot(items: [], serverPollInterval: 300),
            InboxSnapshot(items: [], serverPollInterval: nil),
        ])
        try expectEqual(merged.serverPollInterval, 300)
    }

    await run.test("failure summaries read as a sentence") {
        let one = [AccountFailure(account: "Work", message: "Token rejected")]
        try expectEqual(one.summary, "Work: Token rejected")
        let two = one + [AccountFailure(account: "Personal", message: "Rate limited")]
        try expectEqual(two.summary, "2 accounts failed")
        try expectNil([AccountFailure]().summary)
    }

    run.section("Accounts - fan-out")

    await run.test("one broken account does not blank the card") {
        let workspace = GitHubWorkspace(
            accounts: [
                GitHubAccount(id: "work", label: "Work"),
                GitHubAccount(id: "personal", label: "Personal"),
            ],
            clientFactory: { account, settings in
                let responses: [Result<HTTPResponse, Error>] = account.id == "work"
                    ? [.success(.json(Fixtures.pullRequestSearch))]
                    : [.success(.status(401))]
                return GitHubClient(
                    transport: APITransport(
                        client: FakeHTTPClient(responses),
                        retryPolicy: .none,
                        sleeper: RecordingSleeper()
                    ),
                    tokenStore: InMemoryTokenStore(tokens: [account.tokenKey: "token"]),
                    settings: settings,
                    tokenKey: account.tokenKey
                )
            }
        )

        let snapshot = try await workspace.pullRequests()
        try expectEqual(snapshot.pullRequests.count, 5, "the healthy account still reports")
        try expectEqual(snapshot.failures.count, 1)
        try expectEqual(snapshot.failures.first?.account, "Personal")
        try expectEqual(snapshot.failures.first?.message, "Token rejected")
    }

    await run.test("rows carry the account they came from") {
        let workspace = GitHubWorkspace(
            accounts: [GitHubAccount(id: "work", label: "Work")],
            clientFactory: { account, settings in
                GitHubClient(
                    transport: APITransport(
                        client: FakeHTTPClient([.success(.json(Fixtures.pullRequestSearch))]),
                        retryPolicy: .none,
                        sleeper: RecordingSleeper()
                    ),
                    tokenStore: InMemoryTokenStore(tokens: [account.tokenKey: "token"]),
                    settings: settings,
                    tokenKey: account.tokenKey
                )
            }
        )
        let snapshot = try await workspace.pullRequests()
        try expect(snapshot.pullRequests.allSatisfy { $0.accountID == "work" })
    }

    await run.test("when every account fails the card fails") {
        let workspace = GitHubWorkspace(
            accounts: [GitHubAccount(id: "work", label: "Work")],
            clientFactory: { account, settings in
                GitHubClient(
                    transport: APITransport(
                        client: FakeHTTPClient([.success(.status(401))]),
                        retryPolicy: .none,
                        sleeper: RecordingSleeper()
                    ),
                    tokenStore: InMemoryTokenStore(tokens: [account.tokenKey: "token"]),
                    settings: settings,
                    tokenKey: account.tokenKey
                )
            }
        )
        let error = try await expectThrows {
            _ = try await workspace.pullRequests()
        }
        try expectEqual(error as? APIError, .forbidden("Token rejected"))
    }

    await run.test("actions ask only the accounts that own repositories") {
        let asked = Box<[String]>([])
        let workspace = GitHubWorkspace(
            accounts: [
                GitHubAccount(id: "work", label: "Work"),
                GitHubAccount(id: "personal", label: "Personal"),
            ],
            clientFactory: { account, settings in
                asked.mutate { $0.append(account.id) }
                return GitHubClient(
                    transport: APITransport(
                        client: FakeHTTPClient(routes: [
                            ("actions/runs", .success(.json(Fixtures.workflowRunsPrimary))),
                        ]),
                        retryPolicy: .none,
                        sleeper: RecordingSleeper()
                    ),
                    tokenStore: InMemoryTokenStore(tokens: [account.tokenKey: "token"]),
                    settings: settings,
                    tokenKey: account.tokenKey
                )
            }
        )

        let snapshot = try await workspace.actions(repositoriesByAccount: ["work": ["editoria/ledwall"]])
        try expectEqual(asked.value, ["work"], "an account with no repositories is not polled")
        try expectEqual(snapshot.runs.count, 4)
        try expect(snapshot.runs.allSatisfy { $0.accountID == "work" })
    }

    await run.test("actions with nothing to watch make no requests") {
        let workspace = GitHubWorkspace(
            accounts: [GitHubAccount(id: "work", label: "Work")],
            clientFactory: { _, _ in
                GitHubClient(
                    transport: APITransport(client: FakeHTTPClient([]), retryPolicy: .none),
                    tokenStore: InMemoryTokenStore()
                )
            }
        )
        let snapshot = try await workspace.actions(repositoriesByAccount: [:])
        try expect(snapshot.repositories.isEmpty)
    }
}
