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
/// Secrets are deliberately absent — those live in the Keychain via `TokenStore`.
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

    /// Saved panel origin as an AppKit point string, or nil when the card has never been moved.
    public func origin(for card: CardID) -> String? {
        backend.string(forKey: "panels.\(card.rawValue).origin")
    }

    public func setOrigin(_ value: String?, for card: CardID) {
        backend.set(value, forKey: "panels.\(card.rawValue).origin")
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
