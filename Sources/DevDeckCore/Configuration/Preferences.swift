import Foundation

/// Key-value backing store for preferences.
///
/// A protocol rather than `UserDefaults` directly so the suite can run against an
/// in-memory store without touching the user's real defaults.
public protocol PreferencesBackend: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func hasValue(forKey key: String) -> Bool
    func set(_ data: Data?, forKey key: String)
    func set(_ string: String?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
}

extension UserDefaults: PreferencesBackend, @unchecked @retroactive Sendable {
    public func hasValue(forKey key: String) -> Bool {
        object(forKey: key) != nil
    }

    public func set(_ data: Data?, forKey key: String) {
        set(data as Any?, forKey: key)
    }

    public func set(_ string: String?, forKey key: String) {
        set(string as Any?, forKey: key)
    }
}

public final class InMemoryPreferences: PreferencesBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? { read(key) as? Data }
    public func string(forKey key: String) -> String? { read(key) as? String }
    public func bool(forKey key: String) -> Bool { read(key) as? Bool ?? false }
    public func hasValue(forKey key: String) -> Bool { read(key) != nil }

    public func set(_ data: Data?, forKey key: String) { write(data, key) }
    public func set(_ string: String?, forKey key: String) { write(string, key) }
    public func set(_ value: Bool, forKey key: String) { write(value, key) }

    private func read(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    private func write(_ value: Any?, _ key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }
}

/// Typed access to everything the app remembers between launches.
///
/// Secrets are deliberately absent - those live in the Keychain via `TokenStore`.
public final class Preferences: @unchecked Sendable {
    private let backend: PreferencesBackend

    public init(backend: PreferencesBackend = UserDefaults.standard) {
        self.backend = backend
    }

    // MARK: Cards

    private static let cardLayoutKey = "cards.layout"

    /// Card visibility and order. Falls back to the catalog defaults when unset or corrupt,
    /// so a bad write can never leave the user with an empty desktop.
    public var cardLayout: CardLayout {
        get {
            guard let data = backend.data(forKey: Self.cardLayoutKey),
                  let layout = try? JSONDecoder().decode(CardLayout.self, from: data)
            else { return .default }
            return layout
        }
        set {
            backend.set(try? JSONEncoder().encode(newValue), forKey: Self.cardLayoutKey)
        }
    }

    // MARK: Placement

    public var displayMode: DisplayMode {
        get { DisplayMode(rawValue: backend.string(forKey: "panels.mode") ?? "") ?? .desktop }
        set { backend.set(newValue.rawValue, forKey: "panels.mode") }
    }

    public var isLocked: Bool {
        get { backend.bool(forKey: "panels.locked") }
        set { backend.set(newValue, forKey: "panels.locked") }
    }

    /// Where a panel lives: a display, and an offset on it.
    ///
    /// The offset is to the **top-left** corner, not AppKit's bottom-left origin. Cards change
    /// height as their data arrives, and anchoring on the bottom made every launch place the
    /// card lower than the user left it: the panel is created short, so its top starts below
    /// where it was, and then it grows downwards from there. The top edge is the edge a person
    /// lines panels up by, so that is what is stored.
    ///
    /// Under its own key, and a value written by a build that only knew global coordinates is
    /// ignored rather than migrated. There is nothing to migrate it *to*: the old point means
    /// "somewhere in the arrangement as it stood then", and which display that was is exactly
    /// the information it never recorded.
    public func placement(for card: CardID) -> PanelPlacement? {
        guard let raw = backend.string(forKey: "panels.\(card.rawValue).placement") else { return nil }
        return PanelPlacement(storage: raw)
    }

    public func setPlacement(_ placement: PanelPlacement?, for card: CardID) {
        backend.set(placement?.storage, forKey: "panels.\(card.rawValue).placement")
    }

    /// Whether ⌥Space raises the deck while it is held.
    ///
    /// On by default, and a plain switch rather than a configurable combination: one key that
    /// needs no permission is the whole feature, and a key picker is a settings screen for
    /// something most people press twice a day.
    public var summonEnabled: Bool {
        // Stored as a string because the backend's `bool` cannot tell "off" from "never asked",
        // and this one defaults to on.
        get { backend.string(forKey: "panels.summon") != "0" }
        set { backend.set(newValue ? "1" : "0", forKey: "panels.summon") }
    }

    /// Saved arrangements of the deck, by name.
    public var arrangements: [DeckArrangement] {
        get {
            guard let data = backend.data(forKey: "panels.arrangements"),
                  let decoded = try? JSONDecoder().decode([DeckArrangement].self, from: data)
            else { return [] }
            return decoded
        }
        set { backend.set(try? JSONEncoder().encode(newValue), forKey: "panels.arrangements") }
    }

    /// Repositories the Actions card watches, as `owner/name`.
    ///
    /// Empty means "follow my open pull requests", which is the right default for one person's
    /// deck and costs no configuration. It lives here rather than in `GitHubSettings` because
    /// that type is the services' knobs and has to stay testable without a preferences backend.
    public var actionsRepositories: [String] {
        get {
            guard let data = backend.data(forKey: "github.actions.repositories"),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }
        set { backend.set(try? JSONEncoder().encode(newValue), forKey: "github.actions.repositories") }
    }

    /// Whether the stored tokens have been rewritten with an access control list that survives
    /// a rebuild. One pass, once, and then never again.
    public var hasRepairedKeychain: Bool {
        get { backend.bool(forKey: "keychain.repaired") }
        set { backend.set(newValue, forKey: "keychain.repaired") }
    }

    /// Whether DevDeck may notify you at all.
    ///
    /// The master switch, and nothing more: *what* you are told about is a property of each
    /// account, because one token is your own work and another is a customer's. This one exists
    /// because turning it on is what asks macOS for permission, and asking at first launch,
    /// before the app has done anything for anybody, is what people uninstall an app over.
    public var notificationsEnabled: Bool {
        // Falls back to the switch this replaced, so a deck that already had review-request
        // banners on keeps them.
        get { backend.string(forKey: "notify.enabled").map { $0 == "1" } ?? backend.bool(forKey: "notify.reviews") }
        set { backend.set(newValue ? "1" : "0", forKey: "notify.enabled") }
    }

    /// What has already been announced, so a restart does not repeat it. Ids, newest last.
    public var announcedAlerts: [String] {
        get {
            guard let data = backend.data(forKey: "notify.seen"),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }
        set { backend.set(try? JSONEncoder().encode(newValue), forKey: "notify.seen") }
    }

    /// Whether the deck keeps its columns closed up by itself.
    ///
    /// Off by default, and it has to be: it is the one setting that moves cards the user placed.
    /// With it on, a card growing a line pushes the column back into shape and a deliberate gap
    /// inside a column cannot survive. That is a fair deal when the deck *is* a column, and the
    /// wrong one for a deck scattered across the desktop, which is why it is a switch rather
    /// than a behaviour.
    public var packsColumns: Bool {
        get { backend.bool(forKey: "panels.pack") }
        set { backend.set(newValue, forKey: "panels.pack") }
    }

    /// The combination that raises the deck. Anything unreadable in storage falls back to the
    /// default rather than leaving the app with no shortcut at all.
    public var summonHotKey: HotKeyCombo {
        get {
            guard let raw = backend.string(forKey: "panels.summon.key"),
                  let combo = HotKeyCombo(storage: raw), combo.isValid
            else { return .optionSpace }
            return combo
        }
        set { backend.set(newValue.storage, forKey: "panels.summon.key") }
    }

    /// Whether the screen dims while the deck is up.
    public var summonDims: Bool {
        get { backend.string(forKey: "panels.summon.dim") != "0" }
        set { backend.set(newValue ? "1" : "0", forKey: "panels.summon.dim") }
    }

    /// Whether this card is folded down to one row.
    ///
    /// Per card rather than per deck: the point of collapsing is that the two projects you are
    /// not working on today take one row each while the one you are stays whole.
    public func isCollapsed(_ card: CardID) -> Bool {
        backend.bool(forKey: "panels.\(card.rawValue).collapsed")
    }

    public func setCollapsed(_ value: Bool, for card: CardID) {
        backend.set(value, forKey: "panels.\(card.rawValue).collapsed")
    }

    /// The height a card last settled at.
    ///
    /// Panels open before their data arrives, so a card would come up at its empty height and
    /// then grow - shoving whatever sits beneath it down the screen on every launch. Starting
    /// at the remembered height means the growth is usually nothing at all.
    public func height(for card: CardID) -> Double? {
        guard let raw = backend.string(forKey: "panels.\(card.rawValue).height"),
              let value = Double(raw), value > 0
        else { return nil }
        return value
    }

    public func setHeight(_ value: Double?, for card: CardID) {
        backend.set(value.map { String($0) }, forKey: "panels.\(card.rawValue).height")
    }

    // MARK: Refresh

    public var refreshIntervalSeconds: TimeInterval {
        get {
            guard let raw = backend.string(forKey: "refresh.interval"),
                  let value = TimeInterval(raw), value > 0
            else { return 120 }
            return value
        }
        set { backend.set(String(newValue), forKey: "refresh.interval") }
    }
}
