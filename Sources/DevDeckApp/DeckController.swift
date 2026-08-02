import Combine
import DevDeckCore
import Foundation
import GitHubKit

/// Owns the data every panel renders and the loop that keeps it fresh.
///
/// One controller for the whole deck rather than one per card: the refresh cadence, the
/// token and the backoff after a failure are deck-wide concerns, and a card that is switched
/// off must not keep polling.
@MainActor
final class DeckController: ObservableObject {
    @Published private(set) var pullRequests = CardState<PullRequestsSnapshot>()

    private let preferences: Preferences
    private let tokenStore: any TokenStore
    private var settings: GitHubSettings
    private var loop: Task<Void, Never>?
    private var consecutiveFailures = 0

    /// Cards currently on screen. Nothing is fetched for a hidden card.
    private var activeCards: Set<CardID> = []

    init(preferences: Preferences, tokenStore: any TokenStore, settings: GitHubSettings = .default) {
        self.preferences = preferences
        self.tokenStore = tokenStore
        self.settings = settings
    }

    var refreshPolicy: RefreshPolicy {
        RefreshPolicy(interval: preferences.refreshIntervalSeconds)
    }

    func setActiveCards(_ cards: Set<CardID>) {
        activeCards = cards
        restart()
    }

    func start() {
        restart()
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Cancels the pending wait and refetches immediately.
    func refreshNow() {
        restart()
    }

    private func restart() {
        loop?.cancel()
        guard !activeCards.isEmpty else {
            loop = nil
            return
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.refreshOnce()
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }

    /// Runs one pass and returns how long to wait before the next one.
    private func refreshOnce() async -> TimeInterval {
        guard activeCards.contains(.githubPullRequests) else {
            return refreshPolicy.nextDelay(consecutiveFailures: 0)
        }

        pullRequests.beginRefresh()
        let service = PullRequestsService(
            client: GitHubClient.makeDefault(tokenStore: tokenStore, settings: settings),
            settings: settings
        )

        do {
            let snapshot = try await service.fetch()
            pullRequests.succeed(snapshot, at: Date())
            consecutiveFailures = 0
            return refreshPolicy.nextDelay(consecutiveFailures: 0)
        } catch let error as APIError {
            consecutiveFailures += 1
            pullRequests.fail(error)
            Log.refresh.error("Pull request refresh failed: \(error.displayMessage, privacy: .public)")
            return refreshPolicy.nextDelay(
                after: error,
                consecutiveFailures: consecutiveFailures,
                now: Date()
            )
        } catch {
            consecutiveFailures += 1
            pullRequests.fail(.transport(error.localizedDescription))
            return refreshPolicy.nextDelay(consecutiveFailures: consecutiveFailures)
        }
    }

    // MARK: Menu bar summary

    /// What the menu-bar item shows: the open count, or a dot when there is nothing to say.
    var statusSummary: (text: String, isAlert: Bool, isUnknown: Bool) {
        guard let snapshot = pullRequests.value else {
            return ("–", false, true)
        }
        return ("\(snapshot.totalCount)", snapshot.blockedCount > 0, false)
    }
}
