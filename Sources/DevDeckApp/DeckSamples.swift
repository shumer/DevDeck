import ArcKit
import DDEVKit
import DevDeckCore
import Foundation
import GitHubKit
import GitLabKit
import ProjectKit

/// Everything a deck shows, made up, for `open -a DevDeck --args --deck sample`.
///
/// A screenshot of a real deck is a screenshot of somebody's clients, branches and sandboxes,
/// and a blurred one looks like a leak somebody tried to cover. This is a whole deck with
/// nothing real on it: two GitHub accounts, one GitLab, two Arc projects, two DDEV ones and a
/// plain one, with every card busy enough to show what it is for. Nothing is fetched and nothing
/// is written: the sample runs on in-memory preferences and forgets itself on quit.
struct DeckSample {
    var pullRequests: PullRequestsSnapshot
    var inbox: InboxSnapshot
    var actions: ActionsSnapshot
    var mergeRequests: MergeRequestsSnapshot
    var checkouts: [CheckoutState]
    var stackStatuses: [String: LocalStackStatus]
    var ddevStatuses: [String: DDEVStatus]
    var localStatuses: [String: LocalProjectStatus]
    var docker: DockerStatus
    var logs: [CardID: LogLines]
}

enum DeckSamples {
    static let workAccount = "github"
    static let actionsRepositories = ["acme/portal", "acme/site"]
    static let openSourceAccount = "github-oss"

    static let githubAccounts = [
        GitHubAccount(id: workAccount, label: "Work", organizations: ["acme"]),
        GitHubAccount(id: openSourceAccount, label: "Open source"),
    ]
    static let gitlabAccounts = [
        GitLabAccount(id: GitLabAccount.defaultID, label: "Studio"),
    ]

    /// A token for every sample account, so the settings list shows them as working. The
    /// values are nonsense and nothing ever sends them anywhere.
    static func tokenStore() -> InMemoryTokenStore {
        var tokens: [TokenKey: String] = [:]
        for account in githubAccounts { tokens[account.tokenKey] = "sample" }
        for account in gitlabAccounts { tokens[account.tokenKey] = "sample" }
        return InMemoryTokenStore(tokens: tokens)
    }

    static let arcProjects: [ArcProject] = {
        var links = ArcLink.defaults()
        links = links.map { link in
            var link = link
            if link.label == "Sandbox" {
                link.urlTemplate = "https://sandbox.acme-news.example"
                link.isEnabled = true
            }
            return link
        }
        return [
            ArcProject(id: "acme-news", title: "ACME News", organization: "acme", site: "acme-news", links: links, folder: "~/Projects/acme-news"),
            ArcProject(id: "acme-sports", title: "ACME Sports", organization: "acme", site: "acme-sports", folder: "~/Projects/acme-sports"),
        ]
    }()

    static let ddevProjects = [
        DDEVProject(id: "contrib-d11", name: "contrib-d11", title: "Drupal Contrib · 11.x", folder: "~/Projects/contrib-d11"),
        DDEVProject(id: "acme-shop", name: "acme-shop", title: "ACME Shop", folder: "~/Projects/acme-shop"),
    ]

    static let localProjects = [
        LocalProject(
            id: "storefront-api",
            title: "Storefront API",
            subtitle: "Node · Fastify",
            folder: "~/Projects/storefront-api",
            startCommand: "npm run dev",
            stopCommand: "",
            holdsProcess: true,
            healthURL: "http://localhost:4000/health",
            localSiteURL: "http://localhost:4000"
        ),
    ]

    /// Where the sample deck stands: three columns that fit a laptop screen, the code on the
    /// left, the pipelines and the checkouts in the middle, the projects on the right. The
    /// heights are not known until the cards are drawn, so the rows are placed loosely and the
    /// columns closed up afterwards.
    static func placements(on display: DisplayFrame) -> [CardID: PanelPlacement] {
        let columns: [[CardID]] = [
            [.githubPullRequests, .githubInbox, .gitlabMergeRequests],
            [.githubActions, .workInFlight] + localProjects.map(\.cardID),
            arcProjects.map(\.cardID) + ddevProjects.map(\.cardID),
        ]
        var result: [CardID: PanelPlacement] = [:]
        for (column, cards) in columns.enumerated() {
            for (row, card) in cards.enumerated() {
                result[card] = PanelPlacement(
                    displayID: display.id,
                    offset: CGPoint(x: 40 + 380 * Double(column), y: 40 + 240 * Double(row))
                )
            }
        }
        return result
    }

    static func deck(now: Date) -> DeckSample {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func url(_ text: String) -> URL { URL(string: text)! }

        let pullRequests = PullRequestsSnapshot(
            totalCount: 5,
            pullRequests: [
                PullRequestSummary(
                    id: "PR-490", number: 490, title: "Paywall redirect loop on shared links",
                    repository: "acme/portal", organization: "acme", url: url("https://github.com/acme/portal/pull/490"),
                    isDraft: false, updatedAt: ago(35), reviewDecision: .reviewRequired, checks: .success,
                    unresolvedThreads: 0, accountID: workAccount, isReviewRequest: true, author: "anna",
                    requestedBy: "anna", requestedAt: ago(120)
                ),
                PullRequestSummary(
                    id: "PR-479", number: 479, title: "Cache headers for AMP pages",
                    repository: "acme/portal", organization: "acme", url: url("https://github.com/acme/portal/pull/479"),
                    isDraft: false, updatedAt: ago(300), reviewDecision: .changesRequested, checks: .success,
                    unresolvedThreads: 3, accountID: workAccount
                ),
                PullRequestSummary(
                    id: "PR-482", number: 482, title: "PROJ-311 - Checkout redesign: address step",
                    repository: "acme/portal", organization: "acme", url: url("https://github.com/acme/portal/pull/482"),
                    isDraft: false, updatedAt: ago(50), reviewDecision: .reviewRequired, checks: .success,
                    unresolvedThreads: 2, accountID: workAccount
                ),
                PullRequestSummary(
                    id: "PR-91", number: 91, title: "Blue/green switch for the edge deploy",
                    repository: "acme/site", organization: "acme", url: url("https://github.com/acme/site/pull/91"),
                    isDraft: false, updatedAt: ago(8), reviewDecision: .none, checks: .pending,
                    unresolvedThreads: 0, accountID: workAccount
                ),
                PullRequestSummary(
                    id: "PR-310", number: 310, title: "Fix facet counts with nested documents",
                    repository: "drupal/search_api_solr", organization: "drupal", url: url("https://github.com/drupal/search_api_solr/pull/310"),
                    isDraft: false, updatedAt: ago(1500), reviewDecision: .approved, checks: .success,
                    unresolvedThreads: 0, accountID: openSourceAccount
                ),
            ]
        )

        let inbox = InboxSnapshot(items: [
            InboxItem(id: "n1", reason: .reviewRequested, title: "Paywall redirect loop on shared links",
                      repository: "acme/portal", updatedAt: ago(35), isUnread: true,
                      url: url("https://github.com/acme/portal/pull/490"), accountID: workAccount),
            InboxItem(id: "n2", reason: .mention, title: "Cache invalidation on publish misses the AMP variant",
                      repository: "acme/portal", updatedAt: ago(140), isUnread: true,
                      url: url("https://github.com/acme/portal/issues/486"), accountID: workAccount),
            InboxItem(id: "n3", reason: .assigned, title: "Rotate the CDN token before the 1st",
                      repository: "acme/ops", updatedAt: ago(400), isUnread: true,
                      url: url("https://github.com/acme/ops/issues/58"), accountID: workAccount),
            InboxItem(id: "n4", reason: .ciActivity, title: "Deploy: failed on main",
                      repository: "acme/site", updatedAt: ago(180), isUnread: true,
                      url: url("https://github.com/acme/site/actions"), accountID: workAccount),
            InboxItem(id: "n5", reason: .subscribed, title: "Release 4.3.0",
                      repository: "drupal/search_api_solr", updatedAt: ago(2000), isUnread: false,
                      url: url("https://github.com/drupal/search_api_solr/releases"), accountID: openSourceAccount),
        ])

        func run(_ id: Int, _ name: String, _ repository: String, _ branch: String, _ conclusion: RunConclusion,
                 startedMinutesAgo: Double, minutes: Double, status: RunStatus = .completed) -> WorkflowRun {
            WorkflowRun(
                id: id, name: name, repository: repository, branch: branch, status: status, conclusion: conclusion,
                startedAt: ago(startedMinutesAgo), updatedAt: ago(startedMinutesAgo - minutes),
                url: url("https://github.com/\(repository)/actions/runs/\(id)"), accountID: workAccount,
                isOnDefaultBranch: branch == "main"
            )
        }
        let actions = ActionsSnapshot(
            runs: [
                run(9001, "CI", "acme/portal", "feat/PROJ-311-address", .none, startedMinutesAgo: 6, minutes: 0, status: .inProgress),
                run(9000, "Deploy", "acme/site", "main", .failure, startedMinutesAgo: 180, minutes: 4),
                run(8999, "Deploy", "acme/site", "main", .failure, startedMinutesAgo: 1200, minutes: 3),
                run(8998, "CI", "acme/portal", "main", .success, startedMinutesAgo: 300, minutes: 2.5),
                run(8997, "CI", "acme/portal", "fix/amp-cache-headers", .failure, startedMinutesAgo: 320, minutes: 2),
                run(8996, "Validate", "acme/site", "main", .success, startedMinutesAgo: 1300, minutes: 1),
                run(8995, "CI", "acme/portal", "main", .success, startedMinutesAgo: 1500, minutes: 2.6),
                run(8994, "CI", "acme/portal", "main", .success, startedMinutesAgo: 2900, minutes: 2.4),
                run(8993, "Deploy", "acme/site", "main", .success, startedMinutesAgo: 3000, minutes: 3.5),
                run(8992, "CI", "acme/portal", "main", .success, startedMinutesAgo: 4300, minutes: 2.7),
                run(8991, "Validate", "acme/site", "main", .success, startedMinutesAgo: 5800, minutes: 1.1),
                run(8990, "CI", "acme/portal", "main", .success, startedMinutesAgo: 7200, minutes: 2.5),
                run(8989, "CI", "acme/portal", "main", .success, startedMinutesAgo: 8600, minutes: 2.5),
            ],
            windowDays: 7,
            repositories: ["acme/portal", "acme/site"]
        )

        let mergeRequests = MergeRequestsSnapshot(
            totalCount: 3,
            mergeRequests: [
                MergeRequestSummary(
                    id: "MR-215", iid: 215, title: "Search facets for the archive", project: "cms/editor",
                    url: url("https://gitlab.com/cms/editor/-/merge_requests/215"), isDraft: false, hasConflicts: false,
                    updatedAt: ago(90), pipeline: .success, approvalsLeft: 1, unresolvedThreads: 0,
                    isReviewRequest: true, author: "marta"
                ),
                MergeRequestSummary(
                    id: "MR-212", iid: 212, title: "Editor toolbar spacing", project: "cms/editor",
                    url: url("https://gitlab.com/cms/editor/-/merge_requests/212"), isDraft: false, hasConflicts: true,
                    updatedAt: ago(4000), pipeline: .success, approvalsLeft: 0, unresolvedThreads: 1
                ),
                MergeRequestSummary(
                    id: "MR-87", iid: 87, title: "Rate limits for the export endpoint", project: "cms/api",
                    url: url("https://gitlab.com/cms/api/-/merge_requests/87"), isDraft: false, hasConflicts: false,
                    updatedAt: ago(25), pipeline: .running, approvalsLeft: 1, unresolvedThreads: 0
                ),
            ]
        )

        let checkouts = [
            CheckoutState(id: "acme-news", title: "ACME News", branch: "feat/PROJ-311-homepage", dirtyFiles: 4, ahead: 2, behind: 0, hasUpstream: true),
            CheckoutState(id: "contrib-d11", title: "Drupal Contrib · 11.x", branch: "4.x-facet-counts", dirtyFiles: 0, ahead: 1, behind: 0,
                          hasUpstream: true, localCommits: 1, oldestLocalCommitAt: ago(4 * 1440)),
            CheckoutState(id: "storefront-api", title: "Storefront API", branch: "feat/rate-limits", dirtyFiles: 1, ahead: 0, behind: 3, hasUpstream: true),
        ]

        let stackStatuses: [String: LocalStackStatus] = [
            "acme-news": LocalStackStatus(
                state: .running, engineVersion: "fusion 3.2", containers: 10, checkedAt: now,
                siteURL: url("http://localhost"), branch: "feat/PROJ-311-homepage",
                repositoryURL: url("https://github.com/acme/arc-news"), healthStatusCode: 200
            ),
            "acme-sports": LocalStackStatus(state: .stopped, checkedAt: now, branch: "main",
                                            repositoryURL: url("https://github.com/acme/arc-sports")),
        ]

        let ddevStatuses: [String: DDEVStatus] = [
            "contrib-d11": DDEVStatus(
                state: .running,
                entry: DDEVListEntry(name: "contrib-d11", approot: "~/Projects/contrib-d11", type: "drupal11", state: .running,
                                     primaryURL: url("https://contrib-d11.ddev.site"), mailpitURL: url("https://contrib-d11.ddev.site:8026")),
                config: DDEVConfig(name: "contrib-d11", type: "drupal11", phpVersion: "8.3", databaseType: "mariadb", databaseVersion: "10.11"),
                branch: "4.x-facet-counts", repositoryURL: url("https://git.drupalcode.org/project/search_api_solr"),
                framework: "Drupal 11", checkedAt: now
            ),
            "acme-shop": DDEVStatus(
                state: .stopped,
                config: DDEVConfig(name: "acme-shop", type: "drupal10", phpVersion: "8.2", databaseType: "mysql", databaseVersion: "8.0"),
                branch: "main", repositoryURL: url("https://github.com/acme/shop"), framework: "Drupal 10", checkedAt: now
            ),
        ]

        let localStatuses: [String: LocalProjectStatus] = [
            "storefront-api": LocalProjectStatus(state: .running, checkedAt: now, pid: 48213, branch: "feat/rate-limits",
                                                 repositoryURL: url("https://github.com/acme/storefront-api"), hasLog: true),
        ]

        let logLines = [
            "fusion-cli-engine  | 14:02:09 starting fusion engine 3.2.0",
            "fusion-cli-engine  | 14:02:10 loaded 42 components from bundle acme-news",
            "fusion-cli-engine  | 14:02:11 engine ready on :80",
            "fusion-cli-engine  | 14:02:11 watching src/ for changes",
            "fusion-cli-resolver| 14:02:11 resolver ready, 18 resolvers",
            "fusion-cli-engine  | 14:05:48 GET /  200  312 ms",
            "fusion-cli-engine  | 14:05:49 GET /pf/api/v3/content/fetch/content-api  200  188 ms",
            "fusion-cli-engine  | 14:05:49 GET /pf/resources/dist/css/global.css  200  4 ms",
            "fusion-cli-engine  | 14:06:02 compiled features/global/header (1.4 s)",
            "fusion-cli-engine  | 14:06:03 GET /sports/  200  241 ms",
            "fusion-cli-engine  | 14:06:03 GET /pf/api/v3/content/fetch/collections-api  200  92 ms",
            "fusion-cli-engine  | 14:06:40 compiled features/homepage/lead (0.9 s)",
            "fusion-cli-engine  | 14:06:41 GET /  200  275 ms",
            "fusion-cli-engine  | 14:07:15 GET /pf/api/v3/content/fetch/site-service-hierarchy  200  61 ms",
            "fusion-cli-engine  | 14:07:15 GET /pf/api/v3/content/fetch/content-api  200  203 ms",
            "fusion-cli-engine  | 14:07:16 GET /politics/2026/09/27/budget-vote/  200  318 ms",
            "fusion-cli-engine  | 14:07:40 compiled features/article/body (1.1 s)",
            "fusion-cli-engine  | 14:07:41 GET /politics/2026/09/27/budget-vote/  200  290 ms",
            "fusion-cli-engine  | 14:08:02 GET /pf/api/v3/content/fetch/content-api  404  35 ms",
            "fusion-cli-engine  | 14:08:02 GET /culture/  200  222 ms",
            "fusion-cli-engine  | 14:08:30 compiled features/global/footer (0.6 s)",
            "fusion-cli-engine  | 14:08:31 GET /  200  268 ms",
        ]
        let logs: [CardID: LogLines] = [
            arcProjects[0].cardID: LogLines(lines: logLines, source: "docker compose logs fusion-cli-engine", fetchedAt: now),
            localProjects[0].cardID: LogLines(
                lines: [
                    "{\"level\":30,\"time\":\"14:01:02\",\"msg\":\"Server listening at http://127.0.0.1:4000\"}",
                    "{\"level\":30,\"time\":\"14:05:47\",\"msg\":\"incoming request\",\"req\":{\"method\":\"GET\",\"url\":\"/health\"}}",
                    "{\"level\":30,\"time\":\"14:05:47\",\"msg\":\"request completed\",\"responseTime\":3.1}",
                ],
                source: "~/Projects/storefront-api/.devdeck/run.log",
                fetchedAt: now
            ),
        ]

        return DeckSample(
            pullRequests: pullRequests,
            inbox: inbox,
            actions: actions,
            mergeRequests: mergeRequests,
            checkouts: checkouts,
            stackStatuses: stackStatuses,
            ddevStatuses: ddevStatuses,
            localStatuses: localStatuses,
            docker: DockerStatus(state: .running, serverVersion: "27.3.1", checkedAt: now),
            logs: logs
        )
    }
}
