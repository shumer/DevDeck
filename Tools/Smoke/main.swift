import DevDeckCore
import Foundation
import GitHubKit

// A live check against the real API, using the same client the panels use.
//
// The suite is offline and deterministic by design, so this is the only thing that proves
// the GraphQL document is still valid and the token still works. It prints counts, never
// the token, and never anything that would leak a private repository name beyond what the
// operator already sees on their own screen.

let tokenStore = CompositeTokenStore.standard()

guard let token = try? tokenStore.token(for: .github), !token.isEmpty else {
    print("No GitHub token found.")
    print("Set GITHUB_TOKEN in the environment, or store one via DevDeck → Settings.")
    exit(2)
}

let client = GitHubClient.makeDefault(tokenStore: tokenStore)
let service = PullRequestsService(client: client)

do {
    let started = Date()
    let snapshot = try await service.fetch()
    let elapsed = Date().timeIntervalSince(started)

    print(String(format: "ok — %.2fs", elapsed))
    print("open pull requests: \(snapshot.totalCount) (fetched \(snapshot.pullRequests.count))")
    print("repositories: \(snapshot.repositoryCount)  organisations: \(snapshot.organizationCount)")
    print("blocked: \(snapshot.blockedCount)  ready: \(snapshot.readyCount)")
    print("")
    for pullRequest in snapshot.prioritized(limit: 5) {
        let health = pullRequest.health.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
        print("  \(health) \(pullRequest.shortLabel)  — \(pullRequest.statusLine)")
    }
    exit(0)
} catch let error as APIError {
    print("failed — \(error.displayMessage)")
    if case .graphQL(let messages) = error {
        for message in messages { print("  · \(message)") }
    }
    exit(1)
} catch {
    print("failed — \(error)")
    exit(1)
}
