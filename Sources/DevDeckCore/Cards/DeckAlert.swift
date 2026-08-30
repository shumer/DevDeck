import Foundation

/// Something worth interrupting somebody for.
public struct DeckAlert: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        /// A person has asked you to review something.
        case reviewRequest
        /// Something of yours cannot move: checks failed, changes were requested, a branch
        /// conflicts.
        case blocked
    }

    /// Stable across refreshes, and different for the same item in two different states: a
    /// merge request that was announced as a review request and later goes red is worth saying
    /// twice, and the same request seen twice is not.
    public let id: String
    public let kind: Kind
    /// The line the banner leads with.
    public let title: String
    /// The line under it.
    public let body: String
    public let url: URL
    /// Which account it belongs to, so a click opens it in the right browser profile.
    public let accountID: String

    public init(id: String, kind: Kind, title: String, body: String, url: URL, accountID: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.url = url
        self.accountID = accountID
    }
}

/// What to announce, and what to keep quiet about.
///
/// The rules are here rather than beside the notification centre because they are the whole
/// feature: posting a banner is four lines, and deciding whether it should exist is the part
/// that makes the difference between being told and being nagged.
public enum NotificationDigest {
    /// How many announced items are remembered. Enough that a card's worth of rows cannot push
    /// out something still on screen, small enough to sit in preferences.
    public static let memory = 200
    /// More than this at once becomes one summary. Three banners is a wall, and a wall gets
    /// dismissed without being read.
    public static let summaryThreshold = 3

    /// The alerts worth posting now.
    ///
    /// `isFirstPass` is the rule that matters most: the first answer after launch is not news.
    /// Announcing it would mean every restart tells you about eight things you already knew,
    /// which is how a person learns to ignore an app's notifications.
    public static func newAlerts(
        from candidates: [DeckAlert],
        seen: Set<String>,
        isFirstPass: Bool
    ) -> [DeckAlert] {
        guard !isFirstPass else { return [] }
        var announced = Set<String>()
        return candidates.filter { alert in
            !seen.contains(alert.id) && announced.insert(alert.id).inserted
        }
    }

    /// The seen list after announcing these, newest last, trimmed to `memory`.
    ///
    /// Everything currently on the card is remembered, not only what was announced: a first pass
    /// announces nothing and must still record what it saw, or the second pass announces all of
    /// it.
    public static func remembering(_ ids: [String], in seen: [String]) -> [String] {
        var result = seen.filter { !ids.contains($0) }
        result.append(contentsOf: ids)
        return Array(result.suffix(memory))
    }

    /// One banner when there are a few, one summary when there are many.
    public static func summary(for alerts: [DeckAlert]) -> (title: String, body: String)? {
        guard alerts.count >= summaryThreshold else { return nil }
        let reviews = alerts.filter { $0.kind == .reviewRequest }.count
        let blocked = alerts.count - reviews

        var parts: [String] = []
        if reviews > 0 { parts.append("\(reviews) waiting for your review") }
        if blocked > 0 { parts.append("\(blocked) of yours blocked") }
        return ("DevDeck", parts.joined(separator: ", "))
    }
}
