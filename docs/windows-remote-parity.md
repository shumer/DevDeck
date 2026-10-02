# GitHub / GitLab Windows parity audit

For the complete acceptance contract, use [macos-functional-spec.md](macos-functional-spec.md).
These historical remote corrections do not certify browser discovery/default fallback, Mac global
refresh/backoff cadence, full freshness presentation, >100-row health distribution, focused Actions
configuration, native notification delivery or the full product. Current Mac draft dictionaries
have module lifetime; Windows explicitly clears window-local drafts on close. Earlier wording
describing identical window-only lifetime was too broad.

2026-10-01. Target: behavior implemented in the current Mac sources. Windows runs natively;
the shared Swift API workspaces run in WSL. This is a source/fixture audit, not live account certification.

| Behavior | Mac reference | Windows audit / correction |
| --- | --- | --- |
| Own PRs plus requested reviews, organization filters, pagination, overlapping results | GitHubWorkspace / PullRequestsService / PullRequestsSnapshot | Same shared implementation; adapter fixtures cover totals, identities, capped results and review requests |
| GitLab hosted instances, own MRs plus requested reviews, deduplication and partial failures | GitLabWorkspace / MergeRequestsService / MergeRequestsSnapshot | Same shared implementation; hosted endpoint fixture and complete status matrix |
| Blocked → requested review → attention → ready, then recent activity | `prioritized()` in shared PR/MR snapshots | Fixed: worker previously exported storage order; exports the same prioritized arrays |
| Short codes and full hover explanation; conflict/check/review precedence | PullRequestSummary / MergeRequestSummary | Fixed: exact shared `statusCode` alongside existing `statusLine`; ticket key/subject exported separately |
| Review/blocked/clear verdict, health distribution, repository/org or project/group counts | PullRequestsCard / MergeRequestsCard | Restored typed counts, verdict, distribution and footer |
| Compact/expanded rows | CardMetrics: 3 / 12 | Restored 3 / 12, beyond-ceiling notice; full list retains all fetched rows and updates in place |
| Collapsed remote summary and web dashboard | Four Mac remote cards / module dashboard actions | Restored summary, visible browser action and refresh/full-list context menu |
| Per-account URL browser/profile | LinkOpener / ModuleContext | Retained; public GitHub, enterprise GitHub and configured GitLab host dashboard routing checked |
| Multiple-account badges and explicit scope | Mac shared workspace and account forms | Retained row badges; added account selection to existing Windows cards, avoiding card recreation |
| Account setup and discoverable card visibility | CardCatalog / DeckMenu | Fixed account-only setup: startup and verified account saves create shared PR/Inbox (on), Actions (off), GitLab MR (on). Four types always listed in tray and Settings/Cards; local visibility grouped in tray. Hidden legacy cards and custom scopes retain IDs/placements; new built-ins follow all provider accounts |
| Individual Inbox read and personal notification preservation | NotificationsService / InboxCard | Existing per-thread validated PATCH and paged non-personal rest-read retained; read rows have no read action |
| Read all, bounded by newest notification displayed per account | NotificationsService.markAllRead / inbox controller | Restored explicit per-account PUT with displayed timestamp; missing/negative/future/ambiguous cutoff rejected |
| Mutation progress, failure feedback, cancellation and duplicate action guard | Inbox progress state | Added gathering/marking/all feedback, cancel, disabled controls, refresh and inline sanitized failure |
| Inbox reason labels, unread/personal counts, age, priority and capped total | InboxSnapshot / InboxItem / InboxCard | Restored unread count (previously all rows), priority order, reason badges, age and actionable verdict |
| No decisive Actions run differs from zero percent | ActionsSnapshot.successRate | Retained nil semantics; restored no-runs and separate empty-watch-list / quiet-window states |
| Failures first; active jobs only when there are no failures | ActionsCard.rows | Restored two-row Mac policy; priority before transport ceiling preserves older failures amid newer success |
| Success window, failed/running totals, watched repositories, average duration | ActionsSnapshot / ActionsCard | Restored typed metadata; full-snapshot statistics remain independent of visible-row ceiling |
| Configured repositories, or repositories from open PRs per account | ActionsWatchList / GitHubWorkspace | Shared fallback retained, including surviving explicit accounts when another account's fallback fails |
| Partial account failure retains good rows; all accounts failing is a failed refresh | Shared workspaces / CardState | Retained; native failure coverage checks previous rows, partial-account message and guarded bulk reads |
| Cache/credentials isolation and read invalidation | APITransport / OS token stores | Per account/host/token cache scope retained; all three mutations invalidate selected account cache |
| Poll interval and hidden cards | CardsSettingsPage / Inbox server interval | User interval plus server minimum retained; disabled cards are not constructed; closing cancels polling |
| Review/blocked/failed-main alerts, quiet first observation, PR/Inbox deduplication | GitHubAttention / GitLabAttention / AccountAttention | Existing shared policies retained and covered by portable and Windows attention suites |
| Safe failures and localization | Shared error kinds / six original localization tables | Typed/sanitized transport retained; restored UI uses original six-language resources |
| Settings browser check | Mac account forms | Added browser/profile test action to Windows account form |
| Unsaved token draft while switching accounts/pages | Mac account section draft dictionaries | Restored window-local/account-specific memory; closing clears drafts, verification/storage remain explicit |

## Qualification and remaining gates

Final package/native/layout results are recorded in `.local_docs/EVIDENCE.md` and `windows-remote-*`
reports: Swift 291/0, Core 54/0, Windows/WSL 84/0, native UI 340/0, installer 8/0 and 96 synthetic
views across six languages. Owned Preview PID 225408 preserves settings/positions/startup/Alt+Tab.
All API fixtures use artificial accounts and tokens; no real notification is marked read.
Final synchronization found two enabled GitHub accounts and no configured remote cards; the earlier
assumption that the current Preview had no accounts was stale. A separate read-only credential/API
qualification is recorded in `windows-remote-accounts.json`; no notification mutation is authorized
by this probe. GitLab has no configured account. Browser login/notification delivery, native Mac
execution and x64/desktop/network/signing gates remain open.

The live read-only probe returned four PRs (one blocked, MC/DR), nineteen Actions runs (four failed)
without account failures. Inbox retained thirteen unread/four personal notifications alongside one
account's forbidden access failure. This demonstrates partial-failure preservation on real data;
that account's notification access still needs investigation. No notification was marked read, no
credential written, no banner sent and no primary configuration/widget changed.

The wider migration is not fully equivalent yet: Work in flight, template/dynamic link editing,
custom summon/dimming/packing and update installation remain separate tracked work. Account removal
now detaches card references while preserving identities/placement. Empty automatic scopes retain
visibility preferences and stop polling until an account returns; empty manual scopes disable.

Card-discovery qualification: Core 60/0, native UI 355/0, installer 8/0, read-only native seven local
plus two remote cards (PR 4, Inbox 13 with one forbidden account), six final synthetic settings views.
Owned Preview PID 235652 now has nine switcher-excluded widgets. Original local identities/positions,
preferences/WSL mapping/default settings/startup retained; new fixed-ID PR/Inbox enabled and Actions
hidden, each scoped to both GitHub accounts. Singleton exit 0 and old worker proxies 0. Mac contract
119 files plus active graph unchanged. No real account/credential/notification mutation or project
lifecycle operation, actual deck screenshot, commit/push/release. See ADR 0024; external gates stay open.
