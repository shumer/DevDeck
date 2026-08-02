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

    public init(
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        maxPullRequests: Int = 20,
        includeDrafts: Bool = true,
        organizations: [String] = []
    ) {
        self.apiBaseURL = apiBaseURL
        self.maxPullRequests = maxPullRequests
        self.includeDrafts = includeDrafts
        self.organizations = organizations
    }

    public static let `default` = GitHubSettings()
}
