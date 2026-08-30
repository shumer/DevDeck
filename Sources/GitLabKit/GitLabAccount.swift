import DevDeckCore
import Foundation

/// One GitLab identity with its own token.
///
/// Plural for a different reason than GitHub's. There, several accounts exist because a
/// fine-grained token is approved per organisation; here it is because GitLab is routinely
/// self-hosted, so one person can have a token on gitlab.com and another on a customer's
/// instance, and neither can see the other's merge requests. The host is therefore part of the
/// account rather than a deck-wide setting.
public struct GitLabAccount: Sendable, Equatable, Codable, Identifiable {
    /// Stable slug used in the Keychain account name. Never shown, never changed after
    /// creation: renaming it would orphan the stored token.
    public let id: String
    /// What the settings window and the failure line call this account.
    public var label: String
    /// The instance itself, `https://gitlab.com` or a company's own. The API lives under
    /// `/api/graphql`, and links come back from the API as absolute URLs, so this is only ever
    /// used for the request.
    public var host: URL
    public var isEnabled: Bool
    /// Whether this account may interrupt you. Per account rather than per app: one token is
    /// your own work and another is a customer's, and being told about both at nine in the
    /// evening is not the same request.
    public var notifies: Bool
    /// Where this account's links open. A customer's GitLab and your own are usually two
    /// different browser profiles, for the same reason two GitHub accounts are.
    public var browser: BrowserChoice

    public init(
        id: String,
        label: String,
        host: URL = GitLabAccount.gitlabDotCom,
        isEnabled: Bool = true,
        notifies: Bool = true,
        browser: BrowserChoice = .systemDefault
    ) {
        self.id = id
        self.label = label
        self.host = host
        self.isEnabled = isEnabled
        self.notifies = notifies
        self.browser = browser
    }

    /// Accounts stored before a field existed decode without it rather than failing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        host = try container.decodeIfPresent(URL.self, forKey: .host) ?? Self.gitlabDotCom
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        notifies = try container.decodeIfPresent(Bool.self, forKey: .notifies) ?? true
        browser = try container.decodeIfPresent(BrowserChoice.self, forKey: .browser) ?? .systemDefault
    }

    public static let gitlabDotCom = URL(string: "https://gitlab.com")!
    public static let defaultID = "default"
    public static let `default` = GitLabAccount(id: defaultID, label: "GitLab")

    /// Where this account's token lives. Never the same key as a GitHub account's, whatever the
    /// two are called.
    public var tokenKey: TokenKey {
        TokenKey(account: id == Self.defaultID ? "gitlab" : "gitlab.\(id)")
    }

    /// The GraphQL endpoint for this instance.
    public var graphQLURL: URL {
        host.appendingPathComponent("api").appendingPathComponent("graphql")
    }

    /// The host as a person reads it, for the card's footer: `gitlab.com`, `git.acme.io`.
    public var displayHost: String {
        host.host ?? host.absoluteString
    }

    /// Turns a human label into a slug that is safe as a Keychain account name and stable
    /// enough to keep after the label is edited.
    public static func makeID(from label: String, existing: [String]) -> String {
        let allowed = CharacterSet.alphanumerics
        let base = label.lowercased().unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
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

/// Reads and writes the GitLab account list, in the same preferences domain as everything else.
public struct GitLabAccountsStore: Sendable {
    private let backend: any PreferencesBackend
    private static let key = "gitlab.accounts"

    public init(backend: any PreferencesBackend) {
        self.backend = backend
    }

    /// Empty when nothing has been configured, unlike GitHub's, which always answers with a
    /// default account. GitLab is opt-in: a deck that has never heard of it should not carry a
    /// card asking for a token to an instance nobody uses.
    public func accounts() -> [GitLabAccount] {
        guard
            let data = backend.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([GitLabAccount].self, from: data)
        else { return [] }
        return decoded
    }

    public func enabledAccounts() -> [GitLabAccount] {
        accounts().filter(\.isEnabled)
    }

    public func save(_ accounts: [GitLabAccount]) {
        backend.set(try? JSONEncoder().encode(accounts), forKey: Self.key)
    }
}
