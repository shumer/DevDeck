import Foundation

/// Keeps a card from believing one bad answer.
///
/// A poll is a question asked over and over, and every so often it comes back wrong for a
/// second: Docker is busy and the daemon does not answer, `ddev list` is slow while a project
/// starts, the engine drops one request while it reloads. The card would flip to "stopped" or
/// "Docker is not running", and be right again a few seconds later. Watched for an hour that
/// reads as a deck that lies.
///
/// So a worse answer has to be said twice before it is believed. A better one is believed at
/// once: nobody was ever annoyed by a card that noticed something came up quickly.
public struct StateSettler: Sendable {
    /// Two in a row. One is a hiccup, two is a fact, and three would mean a stack you really
    /// did stop sits there claiming to run for most of a minute.
    public static let threshold = 2

    private var streaks: [String: Int] = [:]

    public init() {}

    /// Whether this answer should be shown.
    ///
    /// `wasGood` is what the card is showing now, so the very first answer about anything is
    /// always shown: there is nothing to protect yet.
    public mutating func shouldApply(isGood: Bool, wasGood: Bool, for id: String) -> Bool {
        guard !isGood else {
            streaks[id] = 0
            return true
        }
        guard wasGood else {
            // Already showing the bad news; nothing to hold back.
            streaks[id] = 0
            return true
        }

        let streak = (streaks[id] ?? 0) + 1
        streaks[id] = streak
        guard streak >= Self.threshold else { return false }
        streaks[id] = 0
        return true
    }

    /// Forgets what it knows about one thing, for when the answer is not coming from a poll:
    /// pressing Stop is not a hiccup, and the card should say so immediately.
    public mutating func reset(_ id: String) {
        streaks[id] = 0
    }
}
