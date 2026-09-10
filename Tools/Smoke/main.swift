import DevDeckCore
import Foundation
import GitHubKit
import GitLabKit

// A live check against the real APIs, using the same clients the panels use.
//
// The suite is offline and deterministic by design, so this is the only thing that proves the
// GraphQL documents are still valid and the tokens still work. It prints counts, never a token.
//
// GitHub checks the first account only, whose token has a name in the environment as well as
// in the Keychain. GitLab checks every instance in the app's settings, because an instance is
// routinely self-hosted and there is no default host to fall back on; with none configured it
// tries gitlab.com with GITLAB_TOKEN.

/// The app's own preferences domain, which is where the instances are. Readable from here:
/// a suite name is a file under ~/Library/Preferences, not something a process owns.
let appDefaults = UserDefaults(suiteName: "com.shumer.devdeck") ?? .standard
let tokenStore = CompositeTokenStore.standard()
var failed = false

// Top-level state in main.swift is main-actor isolated under Swift 6, so the reporter and the
// blocks it runs have to be too.
@MainActor
func report(_ name: String, _ body: @MainActor () async throws -> [String]) async {
    do {
        let started = Date()
        let lines = try await body()
        print(String(format: "%@ - ok, %.2fs", name, Date().timeIntervalSince(started)))
        for line in lines { print("  \(line)") }
    } catch let error as APIError {
        failed = true
        print("\(name) - failed: \(error.displayMessage)")
        if case .graphQL(let messages) = error {
            for message in messages { print("  · \(message)") }
        }
    } catch {
        failed = true
        print("\(name) - failed: \(error)")
    }
    print("")
}

// MARK: GitHub

if let token = try? tokenStore.token(for: .github), !token.isEmpty {
    let client = GitHubClient.makeDefault(tokenStore: tokenStore)
    var repositories: [String] = []

    await report("GitHub pull requests") {
        let snapshot = try await PullRequestsService(client: client).fetch()
        repositories = Array(Set(snapshot.pullRequests.map(\.repository)).prefix(5))
        var lines = [
            "open: \(snapshot.totalCount) (fetched \(snapshot.pullRequests.count))",
            "repositories: \(snapshot.repositoryCount)  organisations: \(snapshot.organizationCount)",
            "blocked: \(snapshot.blockedCount)  ready: \(snapshot.readyCount)",
        ]
        for pullRequest in snapshot.prioritized(limit: 5) {
            let health = pullRequest.health.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
            lines.append("\(health) \(pullRequest.shortLabel) - \(pullRequest.statusLine)")
        }
        return lines
    }

    await report("GitHub inbox") {
        let snapshot = try await NotificationsService(client: client).fetch()
        var lines = [
            "unread: \(snapshot.unreadCount)  waiting on me: \(snapshot.actionableCount)",
            "poll interval asked for: \(snapshot.serverPollInterval.map { "\(Int($0))s" } ?? "none")",
        ]
        for item in snapshot.prioritized(limit: 5) {
            lines.append("\(item.reason.chip.padding(toLength: 9, withPad: " ", startingAt: 0)) \(item.shortRepository) - \(item.title)")
        }
        return lines
    }

    // The Actions card watches whatever the pull requests are in when nothing is configured,
    // which is exactly what this reproduces.
    await report("GitHub actions") {
        guard !repositories.isEmpty else { return ["no repositories to watch (no open pull requests)"] }
        let snapshot = try await ActionsService(client: client).fetch(repositories: repositories)
        let rate = snapshot.successRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "no decisive runs"
        return [
            "repositories: \(repositories.joined(separator: ", "))",
            "success rate over \(snapshot.windowDays)d: \(rate)",
            "running: \(snapshot.runningCount)  failed: \(snapshot.failedCount)",
        ]
    }
} else {
    print("GitHub - skipped: no token. Set GITHUB_TOKEN, or store one via DevDeck → Settings.\n")
}

// MARK: GitLab

var instances = GitLabAccountsStore(backend: appDefaults).enabledAccounts()
if instances.isEmpty, let token = try? tokenStore.token(for: TokenKey(account: "gitlab")), !token.isEmpty {
    instances = [GitLabAccount(id: GitLabAccount.defaultID, label: "GitLab", host: URL(string: "https://gitlab.com")!)]
}

if instances.isEmpty {
    print("GitLab - skipped: no instance in Settings and no GITLAB_TOKEN.\n")
}

for instance in instances {
    await report("GitLab merge requests on \(instance.displayHost)") {
        let client = GitLabClient.makeDefault(account: instance, tokenStore: tokenStore)
        let snapshot = try await MergeRequestsService(client: client, accountID: instance.id).fetch()
        var lines = [
            "open: \(snapshot.totalCount) (fetched \(snapshot.mergeRequests.count))",
            "projects: \(snapshot.projectCount)  groups: \(snapshot.groupCount)",
            "blocked: \(snapshot.blockedCount)  ready: \(snapshot.readyCount)  waiting on me: \(snapshot.reviewRequestCount)",
        ]
        for mergeRequest in snapshot.prioritized(limit: 5) {
            let health = mergeRequest.health.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
            lines.append("\(health) \(mergeRequest.shortLabel) - \(mergeRequest.statusLine)")
        }
        return lines
    }
}

exit(failed ? 1 : 0)
