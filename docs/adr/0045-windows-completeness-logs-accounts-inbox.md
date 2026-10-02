# 0045 — Windows log, account and Inbox completeness fixes

Status: Accepted; scoped development subset qualified and activated.
Date: 2026-10-03.

The full Mac-source audit exposed complete-flow gaps beyond earlier broad parity rows. Actual
old-body fixtures demonstrated lost log Follow/header state, stale log failure feedback, rejected
quiet edits of legacy slash-bound account endpoints, oversized prefixed verification IDs and
serial/early-aborted Inbox read-rest processing. Preserve existing Mac integrations and current
credential/lifecycle behavior while fixing these specific paths.

## Decision

[LogWindow](../../Windows/DevDeck.Windows.App/LogWindow.cs) guards programmatic text/scroll changes,
so they do not toggle Follow; genuine manual scroll and search retain their existing intent.
Responses and errors require the same current project reference and live window. The
[controller](../../Windows/DevDeck.Windows.App/DeckController.cs) reconciles only matching retained
card log presentation after show/hide/close. Explicit open logs survive hiding the widget;
hidden/minimized log windows stop automatic reads.

[AccountSettingsForm](../../Windows/DevDeck.Windows.App/AccountSettingsForm.cs) preserves an exact
ordinal unchanged committed endpoint for metadata saves, including legacy GitHub root/GitLab
prefix slashes. New or explicitly edited values retain previous normalization/admission; edits
that change a credential identity still require verified replacement. Existing raw scope arrays,
IDs and password drafts retain their independent behavior. Generic SaveSettingsAsync's existing
reconciliation/reset policy is unchanged.

Explicit nonempty replacement normalizes its endpoint and preserves verify→new credential
write→settings commit→old-target cleanup. Only a successful current-owner/current-revision commit
may echo that endpoint into the field. Scoped Watch suppression avoids dirty/revision/debounce
changes and another metadata save; newer text, ABA edits and closed owners are not overwritten.
The following saved-token check uses the new committed target. The replacement producer uses
literal cardID `verify`, rather than adding a seven-byte prefix to an account ID. Independent
byte-bound fixtures cover ASCII/multibyte121-byte controls and128-byte IDs without weakening
the worker's128-byte admission.

[WorkerRemoteService](../../Sources/DevDeckWorkerProtocol/WorkerRemoteService.swift) reuses the
shared NotificationsService replenishing bulk helper with concurrency6 for thread/read-rest
actions. Separate failures do not omit later admitted targets; progress uses the selected total
and failure is reported after aggregate completion. Cancellation admission precedes underlying
HTTP delegation. Existing transport retry behavior, protocol1 and Void/error response schema
remain; typed per-thread physical outcomes/optimistic-mask changes are separate work.

## Qualification and deployment

Current Preview118080/package781a6f passed logs3/accounts3 components, fullnative1593, installer8,
read-only7local+2remote and372 fresh six-language synthetic scenes. Eight EN/RU frames were
visually inspected. Core focused4/full226 and worker focused3/full382/release/archive are explicitly
reused by70/208 identical input files; this is not another execution. ADE5/F683 runtime25 and owned
Git30+fake-local promisor60 are separate actual checks in Ubuntu24.04/Debian. Nine retained actual
behavioral failures have green counterparts; the first replacement regression and normalized
follow-up failure remain recorded, with the original two-write assertion unchanged.

The scoped updater replaced only78356, exit0/120.10s; corrected-datetime verification exited0 in
113.49s, both within180s. All nine0x80080 HWNDs and prior IDs/XY/compact/raw accounts/scopes/Seen/
preferences/distributions/configuration/shortcut/full backup/defaults/startup remain, and absent
geometry stays absent. Exactly two admitted RuntimeDirectory transitions deploy the new managed
hash-addressed worker; old D9 remains intact, singleton0/old worker proxies0. Initial proof-schema
and datetime-helper failures were retained and corrected without product changes.

Component credentials/readers are owned fakes. Full Core separately cleans up a UUID-owned
synthetic native vault entry. Integration uses real configured projects/providers read-only:
Inbox retains a forbidden-account failure, GitLab is unconfigured, and stopped sites do not
prove phone reachability. Checkout/Inbox/lifecycle mutation flags are false. Fresh Mac119/graph
and spec140/204 guards protect source; they do not replace native Mac build/UI acceptance.
Exact hashes, timings, bounds and historical results are in
[qualification](../windows-qualification.md).

## Remaining work

The140-ID source inventory is triage, not140 passed behaviors. Notification/settings, typed Inbox
outcomes, display/summon/app branding/updater implementation and native Mac/x64/live permission/
browser/phone/physical input/accessibility/Shell/signing/clean-machine acceptance remain open.
No new settings schema, channel, permission or Mac UI behavior is introduced by this batch.
FullParityConfirmed=false; releaseQualified=false. Private reviewer handoff/helpers remain
uncommitted; this checkpoint does not create a release.
