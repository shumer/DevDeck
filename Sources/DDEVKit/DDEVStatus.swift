import Foundation

/// What DDEV says a project is doing.
///
/// `paused` is its own state, not a flavour of stopped: DDEV pauses containers without
/// tearing them down, and calling that "stopped" would make the card lie about what a start
/// is going to do.
public enum DDEVState: String, Sendable, Equatable, Codable {
    case running
    case paused
    case stopped
    /// A command issued from the card is still going.
    case working
    /// DDEV does not know this project — usually the folder moved.
    case unknown

    public init(apiValue: String) {
        switch apiValue.lowercased() {
        case "running": self = .running
        case "paused": self = .paused
        case "stopped": self = .stopped
        default: self = .unknown
        }
    }

    public var isUp: Bool { self == .running }
}

/// One project as `ddev list` reports it.
public struct DDEVListEntry: Sendable, Equatable {
    public let name: String
    public let approot: String
    public let type: String
    public let state: DDEVState
    public let statusDescription: String?
    public let primaryURL: URL?
    public let mailpitURL: URL?
    public let xhguiURL: URL?
    public let mutagenEnabled: Bool
    public let mutagenStatus: String?

    public init(
        name: String,
        approot: String,
        type: String,
        state: DDEVState,
        statusDescription: String? = nil,
        primaryURL: URL? = nil,
        mailpitURL: URL? = nil,
        xhguiURL: URL? = nil,
        mutagenEnabled: Bool = false,
        mutagenStatus: String? = nil
    ) {
        self.name = name
        self.approot = approot
        self.type = type
        self.state = state
        self.statusDescription = statusDescription
        self.primaryURL = primaryURL
        self.mailpitURL = mailpitURL
        self.xhguiURL = xhguiURL
        self.mutagenEnabled = mutagenEnabled
        self.mutagenStatus = mutagenStatus
    }
}

/// Everything a DDEV card draws.
public struct DDEVStatus: Sendable, Equatable {
    public var state: DDEVState
    public var entry: DDEVListEntry?
    public var config: DDEVConfig
    public var branch: String?
    /// What the project is built on, from composer.lock — `drupal 11.4.4`.
    public var framework: String?
    /// What is happening, or why the last command failed.
    public var detail: String?
    public var checkedAt: Date?

    public init(
        state: DDEVState,
        entry: DDEVListEntry? = nil,
        config: DDEVConfig = DDEVConfig(),
        branch: String? = nil,
        framework: String? = nil,
        detail: String? = nil,
        checkedAt: Date? = nil
    ) {
        self.state = state
        self.entry = entry
        self.config = config
        self.branch = branch
        self.framework = framework
        self.detail = detail
        self.checkedAt = checkedAt
    }

    /// What to call the project in the footer.
    ///
    /// The lock file first: DDEV's `type` is a setting nobody updates after an upgrade, so it
    /// happily says `drupal9` about a Drupal 11 site.
    public var frameworkLabel: String? {
        framework ?? entry?.type ?? config.type
    }

    public var isRunning: Bool { state == .running }
    public var isBusy: Bool { state == .working }

    /// `php 8.4 · mysql 8.0` — the line that answers most "works on mine" questions.
    public var versionsLine: String? {
        let parts = [config.phpVersion.map { "php \($0)" }, config.databaseLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Only worth saying when it is not fine: a broken sync means edits never reach the
    /// container, and nothing else on screen would hint at that.
    public var mutagenWarning: String? {
        guard let entry, entry.mutagenEnabled else { return nil }
        guard let status = entry.mutagenStatus?.lowercased(), status != "ok" else { return nil }
        return "mutagen \(status)"
    }
}

/// What the card's buttons and the menu can ask DDEV to do.
public enum DDEVAction: String, Sendable, CaseIterable {
    case start
    case stop
    case restart

    public var title: String {
        switch self {
        case .start: return "Start"
        case .stop: return "Stop"
        case .restart: return "Restart"
        }
    }

    public var progressText: String {
        switch self {
        case .start: return "starting…"
        case .stop: return "stopping…"
        case .restart: return "restarting…"
        }
    }

    public var command: String {
        switch self {
        case .start: return "ddev start"
        case .stop: return "ddev stop"
        case .restart: return "ddev restart"
        }
    }
}
