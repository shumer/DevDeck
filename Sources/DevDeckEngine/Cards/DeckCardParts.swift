import DevDeckCore
import Foundation

// The parts every card model is built from. A model says what a card shows and what each click
// does, already decided and already in the reader's language; a shell only draws it. How a tone
// looks and which picture a glyph is are the shell's: the Mac paints them in its own colours and
// symbols, and Windows in its own. See docs/adr/0026-card-models-in-the-engine.md.

/// How much something wants to be noticed. The shell turns it into a colour.
public enum DeckTone: String, Sendable, Equatable, Codable {
    /// Working as it should.
    case good
    /// Somebody should look, soon: a review waiting, something in progress.
    case attention
    /// Blocked or broken: the one a sweep down the column should catch.
    case alert
    /// Nothing to say either way.
    case neutral
    /// Addressed to you by name: a mention, a review request, an assignment.
    case personal
}

/// A card's brand mark. The shell draws its own vector for each.
public enum DeckMark: String, Sendable, Equatable, Codable {
    case github, gitlab, arc, ddev, node, next, nest, bun, docker, make, project
}

/// What an icon means, not which picture it is.
public enum DeckGlyph: String, Sendable, Equatable, Codable {
    /// Somebody is waiting on your review.
    case review
    /// Opens something outside the deck, in the browser.
    case openExternal
    case start
    case stop
    case restart
    case terminal
    case folder
    /// The container runtime, for the button that launches it.
    case docker
}

/// What a project's lifecycle buttons ask for, whichever kind of project it is.
public enum DeckProjectAction: String, Sendable, Equatable, Codable {
    case start, stop, restart
}

/// An icon in a row: what it means, how loud it is, and what it says under the pointer.
public struct DeckIconModel: Sendable, Equatable, Codable {
    public let glyph: DeckGlyph
    public let tone: DeckTone
    public let help: String?

    public init(_ glyph: DeckGlyph, tone: DeckTone, help: String? = nil) {
        self.glyph = glyph
        self.tone = tone
        self.help = help
    }
}

/// The services whose links open in an account's own browser.
public enum DeckLinkService: String, Sendable, Equatable, Codable {
    case github, gitlab
}

/// What a click asks for. The runtime carries it out: it changes the deck, or it hands the shell
/// something only the platform can do. See `DeckRuntime.perform(_:)`.
public enum DeckCommand: Sendable, Equatable, Codable {
    /// A row's link, in the browser of the account it came from.
    case openLink(URL, account: String, service: DeckLinkService)
    /// The card's own page on the web.
    case openDashboard(CardID)
    /// Show every row, or go back to the first few.
    case toggleExpanded(CardID)
    /// Mark one inbox thread read.
    case markRead(threadID: String)
    /// Mark everything in the inbox that is not addressed to you read.
    case markRestRead
    /// Mark the whole inbox read.
    case markAllRead
    /// Open Settings on one field, for a card that points at what it needs.
    case openSetting(DeckSetting)
    /// Open a terminal in a checkout's folder.
    case openCheckout(id: String)
    /// A project card's link, in that project's own browser.
    case openProjectLink(CardID, URL)
    /// Start, stop or restart a project.
    case project(CardID, DeckProjectAction)
    /// Show a project's folder.
    case revealFolder(CardID)
    /// Open a terminal in a project's folder.
    case openTerminal(CardID)
    /// Launch the container runtime's app.
    case startDocker
    /// Open a project's log window, or close it.
    case toggleLogs(CardID)
}

/// The settings a card can point at.
public enum DeckSetting: String, Sendable, Equatable, Codable {
    /// The repositories the Actions card watches.
    case actionsRepositories
}

/// A link in place of words, as the inbox's footer has: what it says, and what it does.
public struct DeckLinkModel: Sendable, Equatable, Codable {
    public let title: String
    public let help: String
    public let command: DeckCommand
}

/// The words beside a card's count, and how loud they are.
public struct DeckPillModel: Sendable, Equatable, Codable {
    public let text: String
    public let tone: DeckTone

    public init(_ text: String, tone: DeckTone) {
        self.text = text
        self.tone = tone
    }
}

/// The line at the bottom of a card.
public struct DeckFooterModel: Sendable, Equatable, Codable {
    public let leading: String
    /// Said only when the data has stopped moving: since when.
    public let trailing: String?
    public let isStale: Bool
}

/// The row that grows and shrinks a list.
public struct DeckExpanderModel: Sendable, Equatable, Codable {
    public let label: String
    public let isExpanded: Bool
    public let command: DeckCommand
}

/// What a card shows before its first answer, or when it has none to show.
public struct DeckPlaceholderModel: Sendable, Equatable, Codable {
    public let message: String
    public let isFailure: Bool
    /// What to do about it, when there is something to do.
    public let hint: String?

    public init<Value: Sendable & Equatable>(_ state: CardState<Value>) {
        message = state.failure?.displayMessage ?? L("token.checking")
        isFailure = state.failure != nil
        if case .missingToken(let service) = state.failure {
            // A GitLab card has no token of its own until there is an instance to hold one.
            hint = service == "GitLab" ? L("card.addGitLab") : L("card.addToken", service)
        } else {
            hint = nil
        }
    }
}

/// One button on a card.
public struct DeckActionModel: Sendable, Equatable, Codable {
    public let title: String
    public let glyph: DeckGlyph?
    /// Nil for a quiet button; a tone for the one the state implies.
    public let tone: DeckTone?
    public let isEnabled: Bool
    /// The action that matters, which the row gives more room.
    public let isProminent: Bool
    public let command: DeckCommand

    public init(
        _ title: String,
        glyph: DeckGlyph? = nil,
        tone: DeckTone? = nil,
        isEnabled: Bool = true,
        isProminent: Bool = false,
        command: DeckCommand
    ) {
        self.title = title
        self.glyph = glyph
        self.tone = tone
        self.isEnabled = isEnabled
        self.isProminent = isProminent
        self.command = command
    }
}

/// A card folded down to one row.
public struct DeckCollapsedModel: Sendable, Equatable, Codable {
    public let mark: DeckMark?
    public let title: String
    /// The shortest true sentence about the card.
    public let note: String?
    public let tone: DeckTone
    public let actions: [DeckActionModel]
    public let help: String
}

/// The time words a card wears.
public enum DeckCardTime {
    /// The header's clock, or the failure when the last refresh broke: a clock that keeps ticking
    /// while the data is frozen is the worst of both.
    public static func header<Value: Sendable & Equatable>(for state: CardState<Value>) -> String {
        if let failure = state.failure { return failure.displayMessage }
        guard let updatedAt = state.updatedAt else { return L("card.neverUpdated") }
        return format(updatedAt, "HH:mm:ss")
    }

    /// `as of 14:05`, for a card whose data has stopped moving. It says since when, which a bare
    /// "stale" did not.
    public static func asOf<Value: Sendable & Equatable>(_ state: CardState<Value>) -> String {
        guard let updatedAt = state.updatedAt else { return L("card.notLoaded") }
        return L("card.asOf", format(updatedAt, "HH:mm"))
    }

    /// The header's clock for something checked rather than fetched, or a dash for never.
    public static func checked(_ date: Date?) -> String {
        guard let date else { return L("card.na") }
        return format(date, "HH:mm:ss")
    }

    /// Compact age for a row: `14m`, `3h`, `2d`. Rows are narrow, and "14 minutes ago" costs
    /// more width than it adds meaning.
    public static func age(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 90 { return L("attention.age.now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return L("attention.age.minutes", minutes) }
        let hours = minutes / 60
        if hours < 24 { return L("attention.age.hours", hours) }
        return L("attention.age.days", hours / 24)
    }

    /// Compact duration for a footer: `6m 12s`, `48s`.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return L("card.duration.seconds", total) }
        return L("card.duration.minutes", total / 60, total % 60)
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
