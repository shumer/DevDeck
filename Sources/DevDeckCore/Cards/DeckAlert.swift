import Foundation

/// Something worth interrupting somebody for.
public struct DeckAlert: Sendable, Equatable, Identifiable {
    /// Who is asking. The banner carries the source's own mark rather than the app's, because
    /// "somebody wants a review" is a different thought from "a project stopped".
    public enum Source: String, Sendable, Equatable {
        case github
        case gitlab
        case arc
        case ddev
        case project
        case docker
        /// The app itself: a token it cannot use, a new version.
        case devdeck
    }

    public enum Kind: String, Sendable, Equatable {
        /// A person has asked you to review something.
        case reviewRequest
        /// Something of yours cannot move: checks failed, changes were requested, a branch
        /// conflicts.
        case blocked
        /// A workflow on a repository's main branch failed and is still failing.
        case failedRun
        /// A project that was running stopped without anyone pressing Stop.
        case wentDown
        /// A start pressed from the card did not bring the project up.
        case startFailed
        /// A token stopped working, so a whole account went quiet.
        case cantCheck
    }

    /// Where a click on the banner goes.
    public enum Target: Sendable, Equatable {
        case url(URL, account: String)
        case card(CardID)
        case accountSettings(service: String, account: String)
        /// A summary of several: the menu lists them all.
        case menu
    }

    /// Stable across refreshes, and different for the same item in two different states: a
    /// merge request that was announced as a review request and later goes red is worth saying
    /// twice, and the same request seen twice is not.
    public let id: String
    public let kind: Kind
    public let source: Source
    /// What happened: `Your review is requested`.
    public let title: String
    /// Where: `acme/portal #142 · Work`.
    public let subtitle: String
    /// Which thing, and what a click does: `PROJ-142 Add the article feed. Click to open it.`
    public let body: String
    /// The thing's own name, for a summary that names what it is summarising.
    public let subject: String
    public let target: Target
    /// Without a sound: your own work and this machine are worth a banner, only a person
    /// waiting on you is worth a noise.
    public let isQuiet: Bool

    public init(
        id: String,
        kind: Kind,
        source: Source,
        title: String,
        subtitle: String,
        body: String,
        subject: String,
        target: Target,
        isQuiet: Bool
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.subject = subject
        self.target = target
        self.isQuiet = isQuiet
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
    ///
    /// The summary counts things by what they are and names the first of them, because
    /// "DevDeck: 3 waiting" named nothing, and a click on it opened whichever happened to be first.
    /// A click on this one opens the menu, which lists all of them.
    public static func summary(for alerts: [DeckAlert]) -> (title: String, body: String)? {
        guard alerts.count >= summaryThreshold else { return nil }

        func count(_ kind: DeckAlert.Kind) -> Int { alerts.filter { $0.kind == kind }.count }

        var parts: [String] = []
        if count(.reviewRequest) > 0 { parts.append(LN("alert.summary.reviews", count(.reviewRequest))) }
        if count(.cantCheck) > 0 { parts.append(LN("alert.summary.cantCheck", count(.cantCheck))) }
        if count(.wentDown) > 0 { parts.append(LN("alert.summary.wentDown", count(.wentDown))) }
        if count(.startFailed) > 0 { parts.append(LN("alert.summary.startFailed", count(.startFailed))) }
        if count(.blocked) > 0 { parts.append(LN("alert.summary.stuck", count(.blocked))) }
        if count(.failedRun) > 0 { parts.append(LN("alert.summary.failedRun", count(.failedRun))) }

        let names = alerts.map(\.subject)
        let named: String
        if names.count > 2 {
            named = L("alert.summary.named.more", names[0], names[1], names.count - 2)
        } else if names.count == 2 {
            named = L("attention.list.two", names[0], names[1])
        } else {
            named = names.first ?? ""
        }
        return (parts.joined(separator: ", "), L("alert.summary.body", named))
    }
}
