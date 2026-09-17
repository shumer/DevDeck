import DevDeckCore
import Foundation

/// What GitHub wants from a person, as rows for the menu and banners for the notification centre.
///
/// Pure, so the suite can hold the wording and the counting still: every number the menu-bar
/// icon used to show came from here, including the review counted twice.
public enum GitHubAttention {
    /// Account labels by id, passed only when there is more than one account to tell apart.
    public typealias Labels = [String: String]

    // MARK: Rows

    public static func items(
        pullRequests: PullRequestsSnapshot?,
        inbox: InboxSnapshot?,
        actions: ActionsSnapshot?,
        labels: Labels
    ) -> [AttentionItem] {
        var items: [AttentionItem] = []
        let requests = pullRequests?.pullRequests ?? []

        for request in requests {
            if request.isReviewRequest {
                items.append(reviewItem(request, labels: labels))
            } else if request.health == .blocked {
                items.append(stuckItem(request, labels: labels))
            }
        }

        // The same review arrives twice, once as a pull request and once as a notification, and
        // it is one thing waiting on you.
        let reviewURLs = Set(requests.filter(\.isReviewRequest).map(\.url))
        for item in inbox?.items ?? [] {
            guard item.isUnread, let words = inboxWords(item.reason) else { continue }
            if item.reason == .reviewRequested, let url = item.url, reviewURLs.contains(url) { continue }
            items.append(AttentionItem(
                id: "inbox:\(item.id)",
                tier: .waiting,
                mark: .github,
                title: "\(words.prefix): \(AttentionWords.trimmed(item.title))",
                subtitle: AttentionWords.withAccount([item.repository, words.detail], label: labels[item.accountID]),
                since: item.updatedAt,
                action: item.url.map { .open($0, service: .github, account: item.accountID) } ?? .none,
                inboxThreadID: item.id
            ))
        }

        for failing in actions?.failingOnMainBranch ?? [] {
            let run = failing.latest
            items.append(AttentionItem(
                id: "run:\(run.accountID):\(run.repository):\(run.name):\(run.branch)",
                tier: .stuck,
                mark: .github,
                title: AttentionWords.trimmed("\(run.name) failing on \(run.branch)"),
                subtitle: AttentionWords.withAccount(
                    [run.repository, failing.streak > 1 ? "failed \(failing.streak) times in a row" : "the last run failed"],
                    label: labels[run.accountID]
                ),
                since: failing.firstFailure.startedAt,
                action: run.url.map { .open($0, service: .github, account: run.accountID) } ?? .none
            ))
        }
        return items
    }

    static func reviewItem(_ request: PullRequestSummary, labels: Labels) -> AttentionItem {
        let who = request.requestedBy.map { "\($0) asked" }
            ?? request.author.map { "from \($0)" }
            ?? "review requested"
        return AttentionItem(
            id: "review:\(request.id)",
            tier: .waiting,
            mark: .github,
            title: "Review: \(AttentionWords.trimmed(request.ticket.subject))",
            subtitle: AttentionWords.withAccount(["\(request.repository) #\(request.number)", who], label: labels[request.accountID]),
            since: request.requestedAt ?? request.updatedAt,
            action: .open(request.url, service: .github, account: request.accountID)
        )
    }

    static func stuckItem(_ request: PullRequestSummary, labels: Labels) -> AttentionItem {
        AttentionItem(
            id: "stuck:\(request.id):\(request.statusCode)",
            tier: .stuck,
            mark: .github,
            title: "\(stuckVerb(request)): \(AttentionWords.trimmed(request.ticket.subject))",
            subtitle: AttentionWords.withAccount(["\(request.repository) #\(request.number)", "your pull request"], label: labels[request.accountID]),
            since: request.updatedAt,
            action: .open(request.url, service: .github, account: request.accountID)
        )
    }

    static func stuckVerb(_ request: PullRequestSummary) -> String {
        if request.hasConflicts { return "Merge conflict" }
        if request.checks == .failure { return "Checks failed" }
        return "Changes requested"
    }

    /// What an inbox row is called, and nil for the reasons that are news rather than a request:
    /// a comment, a state change, CI chatter, a subscription.
    static func inboxWords(_ reason: NotificationReason) -> (prefix: String, detail: String)? {
        switch reason {
        case .securityAlert: return ("Security alert", "security alert")
        case .reviewRequested: return ("Review", "review requested")
        case .mention: return ("Mentioned", "you were mentioned")
        case .teamMention: return ("Your team was mentioned", "team mention")
        case .assigned: return ("Assigned to you", "assigned to you")
        case .ciActivity, .stateChange, .comment, .author, .subscribed, .other: return nil
        }
    }

    // MARK: Banners

    /// The banners one pull requests snapshot could raise, before anyone's switches are applied.
    public static func alerts(pullRequests: PullRequestsSnapshot, labels: Labels) -> [DeckAlert] {
        pullRequests.pullRequests.compactMap { request in
            let place = AttentionWords.withAccount(["\(request.repository) #\(request.number)"], label: labels[request.accountID])
            let ticket = [request.ticket.key, request.ticket.subject].compactMap { $0 }.joined(separator: " ")
            if request.isReviewRequest {
                return DeckAlert(
                    id: "review:\(request.id)",
                    kind: .reviewRequest,
                    source: .github,
                    title: request.requestedBy.map { "\($0) asked for your review" } ?? "Your review is requested",
                    subtitle: place,
                    body: "\(ticket). Click to open it.",
                    subject: request.ticket.subject,
                    target: .url(request.url, account: request.accountID),
                    isQuiet: false
                )
            }
            guard request.health == .blocked else { return nil }
            let (title, next): (String, String) = {
                if request.hasConflicts { return ("Your pull request has a merge conflict", "Click to open it.") }
                if request.checks == .failure { return ("Checks failed on your pull request", "Click to see which.") }
                return ("Changes requested on your pull request", "Click to read the review.")
            }()
            return DeckAlert(
                // The state is part of the identity: something announced as blocked, fixed, and
                // broken again is worth saying twice.
                id: "blocked:\(request.id):\(request.statusCode)",
                kind: .blocked,
                source: .github,
                title: title,
                subtitle: place,
                body: "\(ticket). \(next)",
                subject: request.ticket.subject,
                target: .url(request.url, account: request.accountID),
                isQuiet: true
            )
        }
    }

    public static func alerts(actions: ActionsSnapshot, labels: Labels) -> [DeckAlert] {
        actions.failingOnMainBranch.compactMap { failing in
            let run = failing.latest
            guard let url = run.url else { return nil }
            return DeckAlert(
                // The first failure of the streak is in the id, so a workflow fixed and broken
                // again is news again, and the same streak getting longer is not.
                id: "run:\(run.repository):\(run.name):\(run.branch):\(failing.firstFailure.id)",
                kind: .failedRun,
                source: .github,
                title: AttentionWords.trimmed("\(run.name) is failing on \(run.branch)", to: 60),
                subtitle: AttentionWords.withAccount([run.repository], label: labels[run.accountID]),
                body: "The last run failed. Click to see it.",
                subject: run.name,
                target: .url(url, account: run.accountID),
                isQuiet: true
            )
        }
    }
}
