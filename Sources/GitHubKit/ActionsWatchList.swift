import Foundation

/// Which repositories the Actions card watches, and through which account.
///
/// A repository belongs to exactly one account, so the list has to be grouped rather than
/// broadcast: asking every account about every repository would spend most of the requests on
/// 404s.
public enum ActionsWatchList {
    /// Repositories that follow the open pull requests when nothing is configured. Five per
    /// account keeps the card useful with no configuration at all without costing a request
    /// per repository somebody once touched.
    public static let followedPerAccount = 5

    /// The configured list grouped by the account whose organisations own each repository,
    /// or, with nothing configured, the repositories of the open pull requests.
    ///
    /// A configured repository nobody's organisations claim goes to the first account: it is
    /// more likely a personal repository than a typo, and a 404 says which.
    public static func repositoriesByAccount(
        configured: [String],
        accounts: [GitHubAccount],
        pullRequests: PullRequestsSnapshot?
    ) -> [String: [String]] {
        if !configured.isEmpty {
            var grouped: [String: [String]] = [:]
            for repository in configured {
                let owner = String(repository.split(separator: "/").first ?? "")
                let account = accounts.first { $0.organizations.contains(owner) } ?? accounts.first
                guard let account else { continue }
                grouped[account.id, default: []].append(repository)
            }
            return grouped
        }

        guard let pullRequests else { return [:] }
        var grouped: [String: [String]] = [:]
        for pullRequest in pullRequests.prioritized() {
            var repositories = grouped[pullRequest.accountID] ?? []
            guard repositories.count < followedPerAccount,
                  !repositories.contains(pullRequest.repository)
            else { continue }
            repositories.append(pullRequest.repository)
            grouped[pullRequest.accountID] = repositories
        }
        return grouped
    }
}
