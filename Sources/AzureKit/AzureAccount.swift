import DevDeckCore
import Foundation

/// One Azure DevOps organization with its own token.
///
/// Plural for the same reason the GitLab accounts are: a personal access token on Azure DevOps
/// is minted per organization, and one person routinely sits in a customer's organization and
/// their own. Neither token can see the other's pull requests, so the organization is part of
/// the account rather than a deck-wide setting. The cloud service only: `dev.azure.com` is the
/// one host, and an on-premises Azure DevOps Server is not something this card knows about.
public struct AzureAccount: Sendable, Equatable, Codable, Identifiable {
    /// Stable slug used in the Keychain account name. Never shown, never changed after
    /// creation: renaming it would orphan the stored token.
    public let id: String
    /// What the settings window and the failure line call this account.
    public var label: String
    /// The organization's name as it appears in `https://dev.azure.com/{organization}`.
    public var organization: String
    public var isEnabled: Bool
    /// Whether this account may interrupt you when somebody asks for your review.
    public var notifiesReviewRequests: Bool
    /// Whether this account may interrupt you when something of yours is blocked.
    public var notifiesBlocked: Bool
    /// Where this account's links open. A customer's organization and your own are usually two
    /// different browser profiles, for the same reason two GitHub accounts are.
    public var browser: BrowserChoice

    public init(
        id: String,
        label: String,
        organization: String = "",
        isEnabled: Bool = true,
        notifiesReviewRequests: Bool = true,
        notifiesBlocked: Bool = false,
        browser: BrowserChoice = .systemDefault
    ) {
        self.id = id
        self.label = label
        self.organization = organization
        self.isEnabled = isEnabled
        self.notifiesReviewRequests = notifiesReviewRequests
        self.notifiesBlocked = notifiesBlocked
        self.browser = browser
    }

    /// Accounts stored before a field existed decode without it rather than failing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        organization = try container.decodeIfPresent(String.self, forKey: .organization) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        notifiesReviewRequests = try container.decodeIfPresent(Bool.self, forKey: .notifiesReviewRequests) ?? true
        notifiesBlocked = try container.decodeIfPresent(Bool.self, forKey: .notifiesBlocked) ?? false
        browser = try container.decodeIfPresent(BrowserChoice.self, forKey: .browser) ?? .systemDefault
    }

    public static let host = URL(string: "https://dev.azure.com")!
    public static let defaultID = "default"

    /// Where this account's token lives. Never the same key as another service's, whatever the
    /// two are called.
    public var tokenKey: TokenKey {
        TokenKey(account: id == Self.defaultID ? "azure" : "azure.\(id)")
    }

    /// `https://dev.azure.com/{organization}`, the root every API path and every web page in the
    /// organization hangs off.
    public var organizationURL: URL {
        Self.host.appendingPathComponent(organization)
    }

    /// The organization as a person reads it, for the sidebar and the card's footer. The host
    /// when nothing has been typed yet, so a fresh account still says where it points.
    public var displayOrganization: String {
        organization.isEmpty ? "dev.azure.com" : organization
    }

    /// An organization typed by a person, turned into the one word the URL wants.
    ///
    /// People paste `https://dev.azure.com/acme/`, `acme.visualstudio.com`, the URL of a pull
    /// request they were looking at, or just `acme`. Every form comes down to the first path
    /// component, or the first label of the legacy host. Nil for what has no organization in it,
    /// which a form leaves alone rather than blanking the field over a typo.
    public static func normalizedOrganization(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : (trimmed.contains("/") || trimmed.contains(".") ? "https://\(trimmed)" : nil)
        guard let withScheme, let components = URLComponents(string: withScheme), let host = components.host else {
            return isOrganizationName(trimmed) ? trimmed : nil
        }
        // The legacy `{organization}.visualstudio.com` names the organization in the host.
        if host.hasSuffix(".visualstudio.com"), let label = host.split(separator: ".").first {
            return isOrganizationName(String(label)) ? String(label) : nil
        }
        let first = components.path.split(separator: "/").first.map(String.init) ?? ""
        return isOrganizationName(first) ? first : nil
    }

    /// Letters, digits and hyphens, which is all Azure DevOps allows in an organization name.
    private static func isOrganizationName(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
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

/// Reads and writes the Azure DevOps account list, in the same preferences domain as
/// everything else.
public struct AzureAccountsStore: Sendable {
    private let backend: any PreferencesBackend
    private static let key = "azure.accounts"

    public init(backend: any PreferencesBackend) {
        self.backend = backend
    }

    /// Empty when nothing has been configured, like GitLab's: Azure DevOps is opt-in, and a deck
    /// that has never heard of it should not carry a card asking for a token nobody has.
    public func accounts() -> [AzureAccount] {
        guard
            let data = backend.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([AzureAccount].self, from: data)
        else { return [] }
        return decoded
    }

    public func enabledAccounts() -> [AzureAccount] {
        accounts().filter(\.isEnabled)
    }

    public func save(_ accounts: [AzureAccount]) {
        backend.set(try? JSONEncoder().encode(accounts), forKey: Self.key)
    }
}
