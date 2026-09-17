import Foundation
import DevDeckCore

/// Rows of every tier with made-up names, for `open -a DevDeck --args --menu sample`.
///
/// A deck with nothing wrong shows "Nothing needs you", which is the right answer and useless for
/// looking at how a busy menu reads. This is the busy menu, for a screenshot and for judging the
/// layout at real size; nothing in it is fetched and clicking it goes nowhere that matters.
enum AttentionSamples {
    static func items(now: Date) -> [AttentionItem] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let example = URL(string: "https://github.com")!
        return [
            AttentionItem(id: "s1", tier: .waiting, mark: .github, title: "Review: Fix cache invalidation on publish",
                          subtitle: "acme/arc-web #482 · anna asked", since: ago(120), action: .open(example, service: .github, account: "")),
            AttentionItem(id: "s2", tier: .waiting, mark: .gitlab, title: "Review: Search facets for the archive",
                          subtitle: "cms/editor !215 · from marta", since: ago(1500), action: .open(example, service: .gitlab, account: "")),
            AttentionItem(id: "s3", tier: .needsFixing, mark: .ddev, title: "ACME Shop stopped on its own",
                          subtitle: "DDEV · was running at 11:40 · nobody pressed Stop", since: ago(25), action: .none, isDismissible: true),
            AttentionItem(id: "s4", tier: .needsFixing, mark: .token, title: "Replace GitHub token (Work)",
                          subtitle: "Token rejected · nothing from this account is updating", since: ago(80), action: .none),
            AttentionItem(id: "s5", tier: .stuck, mark: .github, title: "Checks failed: Paywall redirect loop",
                          subtitle: "acme/arc-web #490 · your pull request", since: ago(300), action: .open(example, service: .github, account: "")),
            AttentionItem(id: "s6", tier: .stuck, mark: .gitlab, title: "Merge conflict: Editor toolbar spacing",
                          subtitle: "cms/editor !212 · your merge request", since: ago(4000), action: .open(example, service: .gitlab, account: "")),
            AttentionItem(id: "s7", tier: .stuck, mark: .github, title: "Deploy failing on main",
                          subtitle: "acme/site · failed 3 times in a row", since: ago(180), action: .open(example, service: .github, account: "")),
            AttentionItem(id: "s8", tier: .stuck, mark: .github, title: "Changes requested: Cache headers for AMP",
                          subtitle: "acme/arc-web #471 · your pull request", since: ago(1440), action: .open(example, service: .github, account: "")),
            AttentionItem(id: "s9", tier: .stuck, mark: .github, title: "Checks failed: Ad slots on mobile",
                          subtitle: "acme/arc-web #466 · your pull request", since: ago(2880), action: .open(example, service: .github, account: "")),
            AttentionItem(id: "s10", tier: .goodToKnow, mark: .unpushed, title: "4 commits only on this Mac: widgets",
                          subtitle: "feat/PROJ-77-tables · oldest 5 days ago", since: ago(7200), action: .none),
            UpdateAttention.item(version: "0.15", phase: .waiting(card: "ACME News")),
        ]
    }
}
