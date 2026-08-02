import DevDeckCore
import Foundation
import GitHubKit

// A live check against the real API, using the same clients the panels use.
//
// The suite is offline and deterministic by design, so this is the only thing that proves the
// GraphQL document is still valid and the token still works. It prints counts, never the token.
//
// It checks the first account only. Extra accounts are stored in the app's own preferences
// domain, which a command-line process does not share.

let tokenStore = CompositeTokenStore.standard()

guard let token = try? tokenStore.token(for: .github), !token.isEmpty else {
    print("No GitHub token found.")
    print("Set GITHUB_TOKEN in the environment, or store one via DevDeck → Settings.")
    exit(2)
}

let client = GitHubClient.makeDefault(tokenStore: tokenStore)
var failed = false

// Top-level state in main.swift is main-actor isolated under Swift 6, so the reporter and the
// blocks it runs have to be too.
@MainActor
func report(_ name: String, _ body: @MainActor () async throws -> [String]) async {
    do {
        let started = Date()
        let lines = try await body()
        print(String(format: "%@ — ok, %.2fs", name, Date().timeIntervalSince(started)))
        for line in lines { print("  \(line)") }
    } catch let error as APIError {
        failed = true
        print("\(name) — failed: \(error.displayMessage)")
        if case .graphQL(let messages) = error {
            for message in messages { print("  · \(message)") }
        }
    } catch {
        failed = true
        print("\(name) — failed: \(error)")
    }
    print("")
}

var repositories: [String] = []

await report("pull requests") {
    let snapshot = try await PullRequestsService(client: client).fetch()
    repositories = Array(Set(snapshot.pullRequests.map(\.repository)).prefix(5))
    var lines = [
        "open: \(snapshot.totalCount) (fetched \(snapshot.pullRequests.count))",
        "repositories: \(snapshot.repositoryCount)  organisations: \(snapshot.organizationCount)",
        "blocked: \(snapshot.blockedCount)  ready: \(snapshot.readyCount)",
    ]
    for pullRequest in snapshot.prioritized(limit: 5) {
        let health = pullRequest.health.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
        lines.append("\(health) \(pullRequest.shortLabel) — \(pullRequest.statusLine)")
    }
    return lines
}

await report("inbox") {
    let snapshot = try await NotificationsService(client: client).fetch()
    var lines = [
        "unread: \(snapshot.unreadCount)  waiting on me: \(snapshot.actionableCount)",
        "poll interval asked for: \(snapshot.serverPollInterval.map { "\(Int($0))s" } ?? "none")",
    ]
    for item in snapshot.prioritized(limit: 5) {
        lines.append("\(item.reason.chip.padding(toLength: 9, withPad: " ", startingAt: 0)) \(item.shortRepository) — \(item.title)")
    }
    return lines
}

// The Actions card watches whatever the pull requests are in when nothing is configured,
// which is exactly what this reproduces.
await report("actions") {
    guard !repositories.isEmpty else { return ["no repositories to watch (no open pull requests)"] }
    let snapshot = try await ActionsService(client: client).fetch(repositories: repositories)
    let rate = snapshot.successRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "no decisive runs"
    return [
        "repositories: \(repositories.joined(separator: ", "))",
        "success rate over \(snapshot.windowDays)d: \(rate)",
        "running: \(snapshot.runningCount)  failed: \(snapshot.failedCount)",
    ]
}

exit(failed ? 1 : 0)
