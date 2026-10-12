import DevDeckCore
import Foundation

/// What Azure DevOps wants from a person, in the same words as the GitHub card, because the
/// two ask the same question of the same reader.
public enum AzureAttention {
    /// Account labels by id, passed only when there is more than one organization to tell apart.
    public typealias Labels = [String: String]

    public static func items(pullRequests: AzurePullRequestsSnapshot?, labels: Labels) -> [AttentionItem] {
        (pullRequests?.pullRequests ?? []).compactMap { request in
            if request.isReviewRequest {
                return AttentionItem(
                    id: "review:\(request.id)",
                    tier: .waiting,
                    mark: .azure,
                    title: L("attention.row.colon", L("attention.inbox.review.prefix"), AttentionWords.trimmed(request.ticket.subject)),
                    subtitle: AttentionWords.withAccount(
                        [request.place, request.author.map { L("attention.gh.who.from", $0) } ?? L("attention.inbox.review.note")],
                        label: labels[request.accountID]
                    ),
                    since: request.createdAt,
                    action: .open(request.url, service: .azure, account: request.accountID)
                )
            }
            guard request.health == .blocked else { return nil }
            return AttentionItem(
                id: "stuck:\(request.id):\(request.statusCode)",
                tier: .stuck,
                mark: .azure,
                title: L("attention.row.colon", stuckVerb(request), AttentionWords.trimmed(request.ticket.subject)),
                subtitle: AttentionWords.withAccount([request.place, L("attention.gh.yours")], label: labels[request.accountID]),
                since: request.createdAt,
                action: .open(request.url, service: .azure, account: request.accountID)
            )
        }
    }

    static func stuckVerb(_ request: AzurePullRequestSummary) -> String {
        if request.hasConflicts { return L("attention.stuck.conflict") }
        if request.merge == .failed { return L("attention.stuck.mergeFailed") }
        return L("attention.stuck.changesRequested")
    }

    /// The banners one snapshot could raise, before anyone's switches are applied.
    public static func alerts(pullRequests: AzurePullRequestsSnapshot, labels: Labels) -> [DeckAlert] {
        pullRequests.pullRequests.compactMap { request in
            let place = AttentionWords.withAccount([request.place], label: labels[request.accountID])
            let ticket = [request.ticket.key, request.ticket.subject].compactMap { $0 }.joined(separator: " ")
            if request.isReviewRequest {
                return DeckAlert(
                    id: "review:\(request.id)",
                    kind: .reviewRequest,
                    source: .azure,
                    title: request.author.map { L("attention.banner.review.title.who", $0) } ?? L("attention.banner.review.title"),
                    subtitle: place,
                    body: L("attention.banner.open", ticket),
                    subject: request.ticket.subject,
                    target: .url(request.url, account: request.accountID),
                    isQuiet: false
                )
            }
            guard request.health == .blocked else { return nil }
            let (title, next): (String, String) = {
                if request.hasConflicts { return (L("attention.banner.pr.conflict.title"), L("attention.banner.next.open")) }
                if request.merge == .failed { return (L("attention.banner.pr.merge.title"), L("attention.banner.next.open")) }
                return (L("attention.banner.pr.changes.title"), L("attention.banner.next.review"))
            }()
            return DeckAlert(
                // The state is part of the identity: something announced as blocked, fixed, and
                // broken again is worth saying twice.
                id: "blocked:\(request.id):\(request.statusCode)",
                kind: .blocked,
                source: .azure,
                title: title,
                subtitle: place,
                body: L("attention.banner.body", ticket, next),
                subject: request.ticket.subject,
                target: .url(request.url, account: request.accountID),
                isQuiet: true
            )
        }
    }
}
