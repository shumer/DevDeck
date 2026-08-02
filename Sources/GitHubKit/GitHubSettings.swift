import DevDeckCore
import Foundation

/// Knobs for the GitHub integration. Kept separate from `Preferences` so the services
/// stay testable without a preferences backend.
public struct GitHubSettings: Sendable, Equatable, Codable {
    public var apiBaseURL: URL
    /// Maximum pull requests fetched per refresh. The card shows the first few; the count
    /// on the card is the server-side total, not this slice.
    public var maxPullRequests: Int
    public var includeDrafts: Bool
    /// When non-empty, only these organisations are searched.
    public var organizations: [String]
    public var maxNotifications: Int
    /// Repositories the Actions card watches, as `owner/name`. When empty the card falls back
    /// to the repositories of the open pull requests, which is the right default for one
    /// person's deck and costs no configuration.
    public var actionsRepositories: [String]
    /// How far back the Actions success rate looks.
    public var actionsWindowDays: Int

    public init(
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        maxPullRequests: Int = 20,
        includeDrafts: Bool = true,
        organizations: [String] = [],
        maxNotifications: Int = 50,
        actionsRepositories: [String] = [],
        actionsWindowDays: Int = 7
    ) {
        self.apiBaseURL = apiBaseURL
        self.maxPullRequests = maxPullRequests
        self.includeDrafts = includeDrafts
        self.organizations = organizations
        self.maxNotifications = maxNotifications
        self.actionsRepositories = actionsRepositories
        self.actionsWindowDays = actionsWindowDays
    }

    public static let `default` = GitHubSettings()
}
