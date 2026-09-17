import DevDeckCore
import Foundation

/// What GitLab wants from a person, in the same words as `GitHubAttention`, because the two
/// cards ask the same question of the same reader.
public enum GitLabAttention {
    /// Account labels by id, passed only when there is more than one instance to tell apart.
    public typealias Labels = [String: String]

    public static func items(mergeRequests: MergeRequestsSnapshot?, labels: Labels) -> [AttentionItem] {
        (mergeRequests?.mergeRequests ?? []).compactMap { request in
            let place = "\(request.project) !\(request.iid)"
            if request.isReviewRequest {
                return AttentionItem(
                    id: "review:\(request.id)",
                    tier: .waiting,
                    mark: .gitlab,
                    title: "Review: \(AttentionWords.trimmed(request.ticket.subject))",
                    subtitle: AttentionWords.withAccount(
                        [place, request.author.map { "from \($0)" } ?? "review requested"],
                        label: labels[request.accountID]
                    ),
                    since: request.updatedAt,
                    action: .open(request.url, service: .gitlab, account: request.accountID)
                )
            }
            guard request.health == .blocked else { return nil }
            return AttentionItem(
                id: "stuck:\(request.id):\(request.statusCode)",
                tier: .stuck,
                mark: .gitlab,
                title: "\(stuckVerb(request)): \(AttentionWords.trimmed(request.ticket.subject))",
                subtitle: AttentionWords.withAccount([place, "your merge request"], label: labels[request.accountID]),
                since: request.updatedAt,
                action: .open(request.url, service: .gitlab, account: request.accountID)
            )
        }
    }

    static func stuckVerb(_ request: MergeRequestSummary) -> String {
        request.hasConflicts ? "Merge conflict" : "Pipeline failed"
    }

    /// The banners one snapshot could raise, before anyone's switches are applied.
    public static func alerts(mergeRequests: MergeRequestsSnapshot, labels: Labels) -> [DeckAlert] {
        mergeRequests.mergeRequests.compactMap { request in
            let place = AttentionWords.withAccount(["\(request.project) !\(request.iid)"], label: labels[request.accountID])
            let ticket = [request.ticket.key, request.ticket.subject].compactMap { $0 }.joined(separator: " ")
            if request.isReviewRequest {
                return DeckAlert(
                    id: "review:\(request.id)",
                    kind: .reviewRequest,
                    source: .gitlab,
                    title: request.author.map { "\($0) asked for your review" } ?? "Your review is requested",
                    subtitle: place,
                    body: "\(ticket). Click to open it.",
                    subject: request.ticket.subject,
                    target: .url(request.url, account: request.accountID),
                    isQuiet: false
                )
            }
            guard request.health == .blocked else { return nil }
            return DeckAlert(
                // The state is part of the identity: something announced as blocked, fixed, and
                // broken again is worth saying twice.
                id: "blocked:\(request.id):\(request.statusCode)",
                kind: .blocked,
                source: .gitlab,
                title: request.hasConflicts ? "Your merge request has a conflict" : "Pipeline failed on your merge request",
                subtitle: place,
                body: request.hasConflicts
                    ? "\(ticket). Rebase or merge the target branch."
                    : "\(ticket). Click to see the failed jobs.",
                subject: request.ticket.subject,
                target: .url(request.url, account: request.accountID),
                isQuiet: true
            )
        }
    }
}
