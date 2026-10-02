# 0039 — Windows attention alternates and exact Inbox reads

Status: Accepted; supported subset qualified and active. Date: 2026-10-02.

Windows attention supplied primary navigation and a separate project Dismiss control, without
Mac's Option alternatives or a source-bound Inbox read target. A raw notification ID can occur in
two configured accounts, and a subject URL can be absent. Neither is enough to authorize a write.

Append optional `WorkerInboxReadTarget {cardID,accountID,threadID,endpoint}` to attention items and
advertise `attention.inboxReadTarget`, preserving protocol1 and the existing `remote.markRead` RPC.
The worker binds the target to the original personal unread source before generic dedupe. Identity
uses UTF-8 length-prefixed account/thread components. ReviewRequested keeps the original review-URL
key, without grafting a suppressed Inbox read target onto a surviving PR representative. Ambiguous
duplicate sources omit the target. Original GitHubAttention/shared builders/resources stay unchanged.

Core validates captured card/account/API endpoint and exact unread personal row, original primary
URL or none, ID/key/tier/mark and consistent top-level/nested provenance before attention observation.
Targets in unrelated providers, alerts, local/checkout/poweroff routes or malformed envelopes are
rejected. Old JSON without the optional target remains primary-only; the host does not reconstruct
a write target from a URL, title, key or another row.

One choice policy provides primary, read and permitted project-dismiss actions. Read takes precedence;
primary.none is disabled while a URL-less read target stays usable. Alt changes main/overflow rows
in place through the owned-chain WPF/WinForms adapter; full-list named buttons expose the same
alternate. Modifier press alone executes nothing. ItemClicked captures the shown choice before
native auto-close and retains it only through synchronous Click; Stop removes current-chain handlers
and filters. A visible controller rebuild closes the root before disposing its old rows. Both
captions and native columns reserve stable bounds, preserving logical counts/selection/accessibility.

Read uses the current RemoteCard mutation/lifetime and application action gate. Before credential
access and after awaited admission it rechecks the enabled current owner/card/account/provider/API
endpoint/scope and exact raw unread personal row. Only the selected account/thread is removed
optimistically from its own card/attention; pending stale polls are masked without advancing
successful-check time or resetting siblings. Hidden owners retain started CTS/HWND work without
completion-driven reveal or new hidden fetch. Closing/removing cancels owned lifetime. Failure stays
visible, a fresh response can restore unread status, and lost writes are never automatically replayed.
Broad Inbox row/read-rest/read-all behavior stays unchanged. Dismiss revalidates the current full
project reference except display title after acquisition and returns false for stale/hidden/closed
admission. A configured hidden showCard primary reveals the same retained owner and opens one log;
removed IDs create nothing.

## Qualification and activation

Final immutable package2cc50416402c48b9bab4ac6624d88107 passes Core202/0, portable worker379/0,
native1468/0 with observed exit0 in181.91s, installer8/0 exit0 in36.08s and228 synthetic views
(192prior+36 new, six languages). The72 new native cases are included in that full run:
view24+modifier22+controller-visible-rebuild1+read11+primary8+dismiss5+showCard1. Its exported focused
summary has `standaloneRun=false`; the separate72 run on earlier98d7 is historical, not a final rerun.
Read-only7local+2remote exits0 in33.25s, verifying independent local/remote/settings/checkout channels,
shared cadence, typed Inbox capability and no Inbox-write/lifecycle/default-off Git invocation.
Runtime16 in Ubuntu/Debian, Arc4/editor origins, DDEV metadata5 and frozen Mac119/product graph/
spec140/204 pass. Source preservation supplements the required native Mac qualification.

The worker archive SHA-256 is
`d9fc85a3407dc4cac2e43ec95a468f5c3cbc37ea27641238f762a0caf54d4bc3`; binary SHA-256 is
`abd86a21d68f3895259608521fe16053e17eeefb87e8a8d7ff824acce7b050b6`.
Owned ordinary Git30/0 and promisor60/0 checks pass against those exact inputs in both installed
distributions, preserving the existing WIF transport boundary without establishing every Git
package/object layout or arbitrary repository-program behavior. Fake HTTP PATCH records the exact
owning account/endpoint/thread, cache invalidation and sanitized failure. No actual user checkout,
credential/provider write, notification read, lifecycle/network action or desktop capture is used.

Only recorded Preview484424 was replaced by570836 with the original configuration/shortcut/full
backup. `windows-tray-modifiers-preview-checks.json` proves all nine0x80080 HWNDs and prior IDs/XY/
compact/scopes/preferences/accounts/distributions/default settings/startup, singleton0 and no old
worker proxies. Previous WIF02ea/484424 and behavioral/native failures remain preserved.

Earlier98d7 qualified product1468/72/installer8/read-only9 (239.31s/22.31s) was not activated: its
render matrix completed192 prior+4 new views, then found no overflow in a four-waiting-item sample.
Only synthetic Range4→5/per-render error reporting changed; final2cc was fully requalified.
Genuine held-hide write and visible-controller-rebuild reds remain retained. The generic-runtime
fixture's IBM437/default-reader failure was fixed with strict UTF-8 helper readers only; production
JSON transport, global codepages and historical WIF helpers are unchanged.

## Limits

Queued key/mouse and exact HWND delivery are owned synthetic evidence. The unrelated-window proof
uses an independent STA message-only queue because WinForms can intentionally retarget same-thread
keys during a modal menu. It does not prove same-thread modal isolation, physical Alt/AltGr/IME,
OS-global input or screen-reader behavior. Fake write/dispatch tests do not qualify live account
permissions, browser identity, actual notification mutations or Docker/terminal targets.

TRAY-07 stays partial for native verified update installation/available-update notes. SET-04,
full summon latch/dimming, native Mac/x64/live identities/phone/display/shell/signing/clean-machine
and full migration remain open. This is an unsigned development artifact, `releaseQualified=false`.

Implementation: [worker Inbox projection](../../Sources/DevDeckWorkerProtocol/WorkerInboxAttention.swift),
[protocol](../../Sources/DevDeckWorkerProtocol/WorkerProtocol.swift),
[target validation](../../Windows/DevDeck.Windows.Core/InboxReadValidation.cs),
[choices](../../Windows/DevDeck.Windows.Core/AttentionChoices.cs),
[native admission](../../Windows/DevDeck.Windows.App/DeckController.AttentionActions.cs),
[card mutation](../../Windows/DevDeck.Windows.App/RemoteCard.cs),
[tray rows](../../Windows/DevDeck.Windows.App/TrayAttentionRow.cs),
[modifier adapter](../../Windows/DevDeck.Windows.App/TrayAttentionModifiers.cs) and
[full list](../../Windows/DevDeck.Windows.App/AttentionWindow.cs).
Original source: [DeckMenu](../../Sources/DevDeckApp/DeckMenu.swift#L331) and
[AppDelegate](../../Sources/DevDeckApp/AppDelegate.swift#L276).
