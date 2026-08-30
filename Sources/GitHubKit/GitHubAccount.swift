import DevDeckCore
import Foundation

/// One GitHub identity with its own token.
///
/// Several are needed because a fine-grained token is approved per organisation: covering
/// four organisations can mean four tokens, and one of them being revoked must not take the
/// other three off the card.
public struct GitHubAccount: Sendable, Equatable, Codable, Identifiable {
    /// Stable slug used in the Keychain account name. Never shown, never changed after
    /// creation - renaming it would orphan the stored token.
    public let id: String
    /// What the settings window and the error line call this account.
    public var label: String
    public var apiBaseURL: URL
    /// Restricts the pull request search to these organisations. Empty means everything the
    /// token can see.
    public var organizations: [String]
    public var isEnabled: Bool
    /// Whether this account may interrupt you. Per account rather than per app: one token is
    /// your own work and another is a customer's, and being told about both at nine in the
    /// evening is not the same request.
    public var notifies: Bool
    /// Where this account's links open. One signed-in GitHub identity per browser profile is
    /// the whole reason accounts need their own browser.
    public var browser: BrowserChoice

    public init(
        id: String,
        label: String,
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        organizations: [String] = [],
        isEnabled: Bool = true,
        notifies: Bool = true,
        browser: BrowserChoice = .systemDefault
    ) {
        self.id = id
        self.label = label
        self.apiBaseURL = apiBaseURL
        self.organizations = organizations
        self.isEnabled = isEnabled
        self.notifies = notifies
        self.browser = browser
    }

    /// Accounts stored before browsers were configurable decode without the field.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        apiBaseURL = try container.decodeIfPresent(URL.self, forKey: .apiBaseURL)
            ?? URL(string: "https://api.github.com")!
        organizations = try container.decodeIfPresent([String].self, forKey: .organizations) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        notifies = try container.decodeIfPresent(Bool.self, forKey: .notifies) ?? true
        browser = try container.decodeIfPresent(BrowserChoice.self, forKey: .browser) ?? .systemDefault
    }

    public static let defaultID = "default"

    public static let `default` = GitHubAccount(id: defaultID, label: "GitHub")

    /// Where this account's token lives.
    ///
    /// The first account keeps the original un-suffixed key, so a token stored before accounts
    /// existed keeps working without a migration step.
    public var tokenKey: TokenKey {
        id == Self.defaultID ? .github : TokenKey(account: "github.\(id)")
    }

    /// Settings for this account, layered over the deck-wide ones.
    public func settings(basedOn base: GitHubSettings) -> GitHubSettings {
        var settings = base
        settings.apiBaseURL = apiBaseURL
        if !organizations.isEmpty { settings.organizations = organizations }
        return settings
    }

    /// Turns a human label into a slug that is safe as a Keychain account name and stable
    /// enough to keep after the label is edited.
    public static func makeID(from label: String, existing: [String]) -> String {
        let allowed = CharacterSet.alphanumerics
        let base = label.lowercased().unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                // Collapse runs of separators so "Editoria  XP!" does not become "editoria--xp-".
                if character == "-", result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let candidate = base.isEmpty ? "account" : base
        guard existing.contains(candidate) else { return candidate }

        var index = 2
        while existing.contains("\(candidate)-\(index)") { index += 1 }
        return "\(candidate)-\(index)"
    }
}

/// Reads and writes the account list.
///
/// Lives in GitHubKit rather than `Preferences` because the shape is GitHub's; it borrows the
/// same backend so everything still ends up in one `UserDefaults` domain.
public struct GitHubAccountsStore: Sendable {
    private let backend: any PreferencesBackend
    private static let key = "github.accounts"

    public init(backend: any PreferencesBackend) {
        self.backend = backend
    }

    /// The stored list, or a single default account. Never returns an empty list: a deck with
    /// no accounts could not even show the "add a token" prompt.
    public func accounts() -> [GitHubAccount] {
        guard
            let data = backend.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([GitHubAccount].self, from: data),
            !decoded.isEmpty
        else { return [.default] }
        return decoded
    }

    public func enabledAccounts() -> [GitHubAccount] {
        accounts().filter(\.isEnabled)
    }

    public func save(_ accounts: [GitHubAccount]) {
        let sanitized = accounts.isEmpty ? [GitHubAccount.default] : accounts
        backend.set(try? JSONEncoder().encode(sanitized), forKey: Self.key)
    }
}
