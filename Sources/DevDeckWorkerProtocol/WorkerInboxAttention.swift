import DevDeckCore
import Foundation
import GitHubKit

/// Bind the original policy's item to its source before any thread-ID deduplication.
/// Two configured accounts can expose the same raw thread ID, including URL-less subjects.
enum WorkerInboxAttention {
    static func identity(accountID: String, threadID: String) -> String {
        "inbox:\(accountID.utf8.count):\(accountID):\(threadID.utf8.count):\(threadID)"
    }

    static func project(_ snapshot: InboxSnapshot, request: WorkerRemoteRequest)
        -> (signals: WorkerAttentionSnapshot, attention: [WorkerRemoteAttention]) {
        let accounts = Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0) })
        let labels = Dictionary(uniqueKeysWithValues: request.accounts.map { ($0.id, $0.label) })
        var originals: [AttentionItem] = []
        var sources: [String: InboxItem] = [:]
        for source in snapshot.items {
            let own = InboxSnapshot(items: [source])
            for original in GitHubAttention.items(pullRequests: nil, inbox: own, actions: nil, labels: labels) {
                let id = identity(accountID: source.accountID, threadID: source.id)
                if sources[id] == nil { sources[id] = source }
                originals.append(AttentionItem(id: id, tier: original.tier, mark: original.mark, title: original.title,
                    subtitle: original.subtitle, since: original.since, action: original.action,
                    isEnabled: original.isEnabled, isDismissible: original.isDismissible,
                    inboxThreadID: original.inboxThreadID))
            }
        }
        let items = AttentionDigest(items: originals).items.map { original in
            let source = sources[original.id]!
            var projected = WorkerAttentionBridge.item(original)
            // Review overlap remains provider/URL based; another account's colliding thread
            // cannot turn an ordinary mention into a review or lend it a mutation target.
            projected.key = source.reason == .reviewRequested
                ? source.url.map { "github:review:" + $0.absoluteString } ?? original.id : original.id
            if validThread(source.id), let account = accounts[source.accountID],
               snapshot.items.filter({ $0.accountID == source.accountID && $0.id == source.id }).count == 1 {
                projected.inboxRead = WorkerInboxReadTarget(cardID: request.cardID, accountID: source.accountID,
                    threadID: source.id, endpoint: account.endpoint)
            }
            return projected
        }
        let attention = items.map { projected in
            let source = sources[projected.id]!
            return WorkerRemoteAttention(id: projected.id, key: projected.key, accountID: source.accountID,
                kind: source.reason == .reviewRequested ? "review" : "inbox", title: source.title,
                url: source.url?.absoluteString)
        }
        return (WorkerAttentionSnapshot(scope: request.cardID, projectedItems: items, alerts: []), attention)
    }

    private static func validThread(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 32 && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}
