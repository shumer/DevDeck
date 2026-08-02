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
    @Published private(set) var inbox = CardState<InboxSnapshot>()
    @Published private(set) var actions = CardState<ActionsSnapshot>()

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

    private var client: GitHubClient {
        GitHubClient.makeDefault(tokenStore: tokenStore, settings: settings)
    }

    /// Runs one pass over every active card and returns how long to wait before the next one.
    ///
    /// The cards refresh concurrently but share one failure counter: when the token is bad or
    /// the network is down, everything fails together and the deck should back off as a whole
    /// rather than three times over.
    private func refreshOnce() async -> TimeInterval {
        let client = self.client
        var errors: [APIError] = []
        var serverHint: TimeInterval?

        if activeCards.contains(.githubPullRequests) {
            pullRequests.beginRefresh()
            do {
                let snapshot = try await PullRequestsService(client: client, settings: settings).fetch()
                pullRequests.succeed(snapshot, at: Date())
            } catch {
                let apiError = Self.apiError(from: error)
                pullRequests.fail(apiError)
                errors.append(apiError)
            }
        }

        if activeCards.contains(.githubInbox) {
            inbox.beginRefresh()
            do {
                let snapshot = try await NotificationsService(client: client, settings: settings).fetch()
                inbox.succeed(snapshot, at: Date())
                // GitHub states how often it wants to be polled on this endpoint; ignoring it
                // is the fastest way to get a token throttled.
                serverHint = snapshot.serverPollInterval
            } catch {
                let apiError = Self.apiError(from: error)
                inbox.fail(apiError)
                errors.append(apiError)
            }
        }

        if activeCards.contains(.githubActions) {
            actions.beginRefresh()
            do {
                let snapshot = try await ActionsService(client: client, settings: settings)
                    .fetch(repositories: actionsRepositories)
                actions.succeed(snapshot, at: Date())
            } catch {
                let apiError = Self.apiError(from: error)
                actions.fail(apiError)
                errors.append(apiError)
            }
        }

        guard let firstError = errors.first else {
            consecutiveFailures = 0
            return refreshPolicy.nextDelay(consecutiveFailures: 0, serverHint: serverHint)
        }

        consecutiveFailures += 1
        Log.refresh.error("Refresh failed: \(firstError.displayMessage, privacy: .public)")
        return refreshPolicy.nextDelay(
            after: firstError,
            consecutiveFailures: consecutiveFailures,
            now: Date()
        )
    }

    /// Repositories the Actions card watches: the configured list, or the ones the open pull
    /// requests are in. Falling back keeps the card useful with no configuration at all.
    private var actionsRepositories: [String] {
        guard settings.actionsRepositories.isEmpty else { return settings.actionsRepositories }
        guard let snapshot = pullRequests.value else { return [] }
        var seen: [String] = []
        for pullRequest in snapshot.prioritized() where !seen.contains(pullRequest.repository) {
            seen.append(pullRequest.repository)
            if seen.count == 5 { break }
        }
        return seen
    }

    private static func apiError(from error: Error) -> APIError {
        (error as? APIError) ?? .transport(error.localizedDescription)
    }

    // MARK: Menu bar summary

    /// What the menu-bar item shows: open pull requests, and unread notifications when that
    /// card is on. `–` while nothing has loaded yet.
    var statusSummary: (text: String, isAlert: Bool, isUnknown: Bool) {
        var parts: [String] = []
        var isAlert = false
        var isUnknown = true

        if activeCards.contains(.githubPullRequests) {
            if let snapshot = pullRequests.value {
                parts.append("◆ \(snapshot.totalCount)")
                isAlert = isAlert || snapshot.blockedCount > 0
                isUnknown = false
            } else {
                parts.append("◆ –")
            }
        }

        if activeCards.contains(.githubInbox) {
            if let snapshot = inbox.value {
                parts.append("✉ \(snapshot.unreadCount)")
                isAlert = isAlert || snapshot.actionableCount > 0
                isUnknown = false
            } else {
                parts.append("✉ –")
            }
        }

        if parts.isEmpty { parts.append("◆") }
        return (parts.joined(separator: "  "), isAlert, isUnknown)
    }
}
