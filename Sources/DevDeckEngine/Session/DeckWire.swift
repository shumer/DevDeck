#if canImport(CoreGraphics)
import CoreGraphics
#endif
import DevDeckCore
import Foundation

// What crosses the pipe between the engine host and a shell that is not in the same process.
// One JSON object per line each way, protocol version 2. The shell sends intents and gets
// events; it never interprets a command, it sends back the one it was given. The whole contract
// is docs/engine-protocol.md.

/// A rectangle as four numbers, `[x, y, width, height]`, in the shell's own coordinates: y grows
/// downward, the way Windows counts.
public typealias DeckWireRect = [Double]

/// Something the shell tells the engine.
public struct DeckIntent: Decodable, Sendable {
    /// A display as the shell sees it.
    public struct Display: Decodable, Sendable, Equatable {
        /// Stable across unplugging and plugging back in: the monitor's own identity.
        public let id: String
        /// The work area, taskbar excluded.
        public let frame: DeckWireRect
        public let isPrimary: Bool
    }

    public let protocolVersion: Int
    /// Echoed on every event the intent causes directly.
    public let id: String
    public let intent: String
    /// `session.start`: the language the system prefers, `ru-RU` or `en`, for a deck whose
    /// language setting is the system's.
    public let systemLanguage: String?
    /// `session.start`, `displays.changed`.
    public let displays: [Display]?
    /// `card.measured`, `card.moved`, `logWindow.changed`.
    public let card: CardID?
    /// `card.measured`: `[width, height]` as drawn.
    public let size: [Double]?
    /// `card.moved`: where a person, or the system, put the panel.
    public let frame: DeckWireRect?
    /// `command`: exactly as an event carried it.
    public let command: DeckCommand?
    /// `logWindow.changed`.
    public let isOpen: Bool?
    /// `settings`.
    public let request: DeckSettingsRequest?
    /// `update.progress`: how much is downloaded, 0 to 1.
    public let fraction: Double?
    /// `update.failed`: what went wrong, in the shell's words, since only it knows.
    public let reason: String?

    public static let maximumSize = 1_048_576

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumSize else { throw EngineProtocolError.oversizedMessage }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.protocolVersion == 2, !value.id.isEmpty else { throw EngineProtocolError.invalidIntent }
        return value
    }
}

/// Something the engine tells the shell. Every field but the envelope is optional, and an event
/// carries the ones its name says.
public struct DeckEvent: Encodable, Sendable {
    public var protocolVersion = 2
    /// Counts every event of the session, so a shell can tell it missed one.
    public var revision: Int
    public var event: String
    /// The intent this answers, when it answers one.
    public var id: String?

    public var card: CardID?
    public var model: DeckCardModel?
    /// The card's context menu.
    public var menu: [DeckMenuEntry]?
    public var panels: [DeckWirePanel]?
    public var status: DeckStatusModel?
    public var deck: DeckWireDeck?
    public var effect: DeckWireEffect?
    public var notifications: [DeckWireNotification]?
    public var log: DeckWireLog?
    /// `settings.answered`.
    public var answer: DeckSettingsAnswer?
    /// `update.changed`: the settings page's update row.
    public var update: DeckUpdateRow?
    public var reason: String?

    init(revision: Int, event: String, id: String?) {
        self.revision = revision
        self.event = event
        self.id = id
    }
}

/// One thing to do to a panel, in the order given.
public struct DeckWirePanel: Encodable, Sendable, Equatable {
    public let card: CardID
    /// `open`, `place` or `close`.
    public let change: String
    /// Empty for `close`.
    public let frame: DeckWireRect
}

/// What every panel carries regardless of its card.
public struct DeckWireDeck: Encodable, Sendable, Equatable {
    /// Panels cannot be dragged.
    public let isLocked: Bool
    /// `desktop`: behind every window. `floating`: above them.
    public let displayMode: DisplayMode
}

/// Something only the platform can do. `kind` says which; the rest of the fields are the ones
/// that kind needs.
public struct DeckWireEffect: Encodable, Sendable, Equatable {
    /// `openURL`, `openTerminal`, `revealFolder`, `launchDocker`, `openLogs`, `closeLogs`,
    /// `openSettings`, `present`, `openMenu`, `installUpdate`, `quit`.
    public let kind: String
    public var url: String?
    public var browser: BrowserChoice?
    /// A folder in the platform's own spelling.
    public var folder: String?
    public var card: CardID?
    /// `openSettings`: the page, and the item on it.
    public var page: String?
    public var item: String?
    /// `installUpdate`: what to download.
    public var update: DeckWireUpdate?

    init(_ kind: String) {
        self.kind = kind
    }
}

/// A release to download and install, for the shell's installer.
public struct DeckWireUpdate: Encodable, Sendable, Equatable {
    public let version: String
    public let asset: String
    public let size: Int
    public let page: String
}

/// A banner. Clicking it sends `command` back.
public struct DeckWireNotification: Encodable, Sendable, Equatable {
    public let id: String
    /// Whose mark the banner carries: `github`, `gitlab`, `arc`, `ddev`, `project`, `docker`,
    /// `devdeck`.
    public let source: String
    public let title: String
    public let subtitle: String
    public let body: String
    /// No sound.
    public let isQuiet: Bool
    public let command: DeckCommand
}

/// The lines a log window shows.
public struct DeckWireLog: Encodable, Sendable, Equatable {
    public let lines: [String]
    public let source: String?
    public let detail: String?
}

// MARK: Card models on the wire

extension DeckCardModel: Codable {
    private enum Kind: String, CodingKey {
        case reviewList, inbox, actions, workInFlight, project
    }

    /// One key, named after the kind of card, holding its model.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Kind.self)
        switch self {
        case .reviewList(let model): try container.encode(model, forKey: .reviewList)
        case .inbox(let model): try container.encode(model, forKey: .inbox)
        case .actions(let model): try container.encode(model, forKey: .actions)
        case .workInFlight(let model): try container.encode(model, forKey: .workInFlight)
        case .project(let model): try container.encode(model, forKey: .project)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Kind.self)
        guard let kind = container.allKeys.first, container.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "One kind of card"))
        }
        switch kind {
        case .reviewList: self = .reviewList(try container.decode(ReviewListCardModel.self, forKey: kind))
        case .inbox: self = .inbox(try container.decode(InboxCardModel.self, forKey: kind))
        case .actions: self = .actions(try container.decode(ActionsCardModel.self, forKey: kind))
        case .workInFlight: self = .workInFlight(try container.decode(WorkInFlightCardModel.self, forKey: kind))
        case .project: self = .project(try container.decode(DeckProjectCardModel.self, forKey: kind))
        }
    }
}

// MARK: Coordinates

/// The engine places panels in the Mac's coordinates, y growing upward; a shell on the wire
/// counts y downward. Mirroring about y = 0 turns one into the other, both ways, and keeps
/// every distance, so placement decides the same thing in either.
enum DeckWireGeometry {
    static func rect(_ numbers: DeckWireRect) -> CGRect? {
        guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0,
              numbers.allSatisfy({ abs($0) <= 1_000_000 })
        else { return nil }
        return CGRect(x: numbers[0], y: -(numbers[1] + numbers[3]), width: numbers[2], height: numbers[3])
    }

    static func numbers(_ rect: CGRect) -> DeckWireRect {
        [Double(rect.minX), Double(-(rect.minY + rect.height)), Double(rect.width), Double(rect.height)]
    }

    static func panel(_ change: DeckPanelChange) -> DeckWirePanel {
        switch change {
        case .close(let card): return DeckWirePanel(card: card, change: "close", frame: [])
        case .open(let card, let rect): return DeckWirePanel(card: card, change: "open", frame: numbers(rect))
        case .place(let card, let rect): return DeckWirePanel(card: card, change: "place", frame: numbers(rect))
        }
    }
}
