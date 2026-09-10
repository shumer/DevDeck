import Foundation

/// One remote card's share of a refresh pass.
public struct RefreshSource: Sendable {
    public let card: CardID
    /// Fetches, keeps the card's own state, and returns the interval the server asked to be
    /// polled at, when it asked for one. Throws to say the card failed; what it threw is what
    /// the pass backs off on.
    public let refresh: @Sendable () async throws -> TimeInterval?

    public init(card: CardID, refresh: @escaping @Sendable () async throws -> TimeInterval?) {
        self.card = card
        self.refresh = refresh
    }
}

/// One card that did not answer on this pass.
public struct RefreshFailure: Sendable, Equatable {
    public let card: CardID
    public let error: APIError

    public init(card: CardID, error: APIError) {
        self.card = card
        self.error = error
    }
}

/// Runs the remote cards, one pass at a time, and says how long to wait before the next.
///
/// The cards share one failure counter on purpose: when the token is bad or the network is
/// down, everything fails together and the deck should back off as a whole rather than four
/// times over. A hidden card is never asked. The server's own poll interval is honoured
/// upwards and never downwards, which is `RefreshPolicy`'s rule; this only carries it.
///
/// A class rather than a struct: the count of consecutive failures has to survive between
/// passes, and a mutating async call on an actor-isolated stored property is not something
/// Swift allows.
public final class RefreshCycle {
    /// What one pass did.
    public struct Pass: Sendable, Equatable {
        /// The cards that were asked and answered, in the order they were asked.
        public let refreshed: [CardID]
        /// The cards that were asked and did not, in the same order.
        public let failures: [RefreshFailure]
        /// How long to wait before the next pass.
        public let delay: TimeInterval

        public init(refreshed: [CardID], failures: [RefreshFailure], delay: TimeInterval) {
            self.refreshed = refreshed
            self.failures = failures
            self.delay = delay
        }
    }

    public private(set) var consecutiveFailures = 0

    public init() {}

    /// Asks every active source in order and works out the wait.
    ///
    /// In order rather than concurrently: the sources hold the same token and the same rate
    /// limit, and four requests fired at once against a limit that is already spent produce
    /// four failures rather than one.
    public func run(
        _ sources: [RefreshSource],
        active: Set<CardID>,
        policy: RefreshPolicy,
        now: Date
    ) async -> Pass {
        var refreshed: [CardID] = []
        var failures: [RefreshFailure] = []
        var serverHint: TimeInterval?

        for source in sources where active.contains(source.card) {
            do {
                if let hint = try await source.refresh() {
                    serverHint = max(serverHint ?? 0, hint)
                }
                refreshed.append(source.card)
            } catch {
                failures.append(RefreshFailure(card: source.card, error: APIError.wrapping(error)))
            }
        }

        guard let first = failures.first else {
            consecutiveFailures = 0
            return Pass(
                refreshed: refreshed,
                failures: [],
                delay: policy.nextDelay(consecutiveFailures: 0, serverHint: serverHint)
            )
        }

        consecutiveFailures += 1
        return Pass(
            refreshed: refreshed,
            failures: failures,
            delay: policy.nextDelay(after: first.error, consecutiveFailures: consecutiveFailures, now: now)
        )
    }
}

public extension APIError {
    /// Whatever a service threw, as something a card can render. The services throw
    /// `APIError` already; anything else is the transport under them.
    static func wrapping(_ error: Error) -> APIError {
        (error as? APIError) ?? .transport(error.localizedDescription)
    }
}
