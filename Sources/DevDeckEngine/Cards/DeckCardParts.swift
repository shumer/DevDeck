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
    public let isEnabled: Bool
    public let command: DeckCommand

    public init(_ title: String, glyph: DeckGlyph? = nil, isEnabled: Bool = true, command: DeckCommand) {
        self.title = title
        self.glyph = glyph
        self.isEnabled = isEnabled
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

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
