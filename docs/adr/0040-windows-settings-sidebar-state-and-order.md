# 0040 — Windows settings sidebar state and order

Status: Accepted; scoped behavior qualified and active. Date: 2026-10-02.

Windows settings followed saved account/project arrays and lacked semantic activity dots and
disabled-row treatment. Reusing deck ordering would group project kinds and use permanent-ID ties;
rebuilding a form for a poll could lose a draft, password, focus or scroll. The sidebar therefore
uses a separate stable natural title projection and retained rows.

`SettingsSidebarOrdering` flattens configured projects across kinds and accounts across providers,
using the current/supplied culture's numeric case-insensitive comparison. Equal titles retain saved
input order. Original objects, stored arrays, hidden metadata and independent deck order remain.
Exact Apple/Windows collation equivalence is an external acceptance limit.

Current local owners, including hidden cards, provide `SidebarProjectActivity`. Active operation
CTS, group ownership or command presentation takes Busy precedence over an older running receipt;
physical working/plain starting are Busy, running is Running, and other states are None. Failed
polls retain accepted state. Publication follows existing generation/lifetime/ProjectID guards and
revalidates the actual owner/full reference after UI dispatch. Replacement is reconciled after
registration, clearing a former dot without carrying receipts across folder/distro/kind changes.
This adds no worker RPC/capability, timer, attention observation or settings save.

Rows remain selectable when configured off the deck. Their unselected title dims, selected title
stays white, icon opacity is0.45 and the reserved seven-DIP dot stays undimmed. Full localized
tooltips and automation descriptions accompany clipped titles. Reconciliation updates retained
rows and the selected title from the full list, preserving form/draft/password/focus/caret/query/
selection/page and sidebar scroll/error/debounce/CTS. It neither flushes drafts nor resets sibling
attention/Seen/queues/successful-check time. A surviving viewport anchor uses current offset after
layout coercion, with the captured offset only as fallback.

Becoming visible reconciles the retained list from current owner/availability caches. Automatic
publication skips an invisible settings window, so Show catches up receipts accepted while hidden.
This path does not reseed credential metadata, replace/flush the form or request focus. The first
c5 implementation component exposed this genuine opening gap; its exit1 receipt remains retained.

`WindowsTokenStore.HasToken` checks bounded Generic credential metadata for the exact provider/ID/
endpoint target without decoding/copying token bytes or marshaling string/blob pointees. Its pointer
header matches CREDENTIALW and is freed once; missing/unreadable/nongeneric/oversized or nonempty-
null-blob metadata is unavailable. A bounded legacy zero-byte value is present, matching original Mac non-nil
presence semantics. This means stored value, not authenticated provider permission.

The window caches only the availability boolean by exact `CredentialTarget`. Constructing a new
window, successful current credential commitment or the first explicit committed uncached account
target may update it; re-show/project/search/ordinary metadata/row callbacks reuse the cache.
Current write and settings persistence precede the separate credential callback, which precedes
ordinary list reconciliation/former-target cleanup. Cleanup failure cannot falsely describe a
committed current target. Closed/replaced window/account callbacks are rejected. Existing token
verification/read/write policy and explicit-save behavior stay unchanged.

## Qualification and activation

Actual production Core/native reds remain: old mixed-kind/saved10,2,1 ordering failed, running/busy
dots and disabled title/icon dimming were absent, and disabled entries already remained selectable.
The c5 opening failure is a product presentation fix. The e61 initial field-focus premise failed
before preservation comparisons; test-only owned layout/BringIntoView/rendered-viewport checks
established actual keyboard focus before the unchanged strict draft/password/caret/scroll assertions.
The original failures and packages remain retained; no production focus policy changed for that fixture.

The first complete eced package exited1/219.54s because an older navigation fixture expected provider
input order. Actual isolated diagnosticac1 retained account:lab selection and sidebar keyboard focus,
confirming natural order. Only strict first/last expectations changed; focus/heading/clamping/filter/
removal/token assertions and full1492 count remain. Its separate installer proof is historical.

Final immutable package9563ba2b2a4242fa9a58c76f8b166764 passes Core214/0 (12new), native1492/0
observed exit0/296.17s within its300-second budget, installer8/0 exit0/118.88s with identical
manifest,252 six-language synthetic views (24sidebar), and read-only7local+2remote exit0/32.34s.
The24 new cases are extracted from the final full run (`standaloneRun=false`); the separate24-case
component4988 run is historical. Final standalone legacy navigation68/0 exits0/11.83s.
App SHA256 `0F5AE107EF4274FE872D192139D2A1E90F2CDD7BD384DBF5E536A26FF786CECD` and manifest
`7676689E3B1E354E29B97E46A4552B445A80124EF9367D2446BB039F29DBF285` match final execution/
installer/completed-render receipts. Partial reports and previous artifacts remain preserved;
activation checks exact current package/hashes/observed exits before stopping its recorded owner.

The exact unchanged TRAY archive
`d9fc85a3407dc4cac2e43ec95a468f5c3cbc37ea27641238f762a0caf54d4bc3` and binary
`abd86a21d68f3895259608521fe16053e17eeefb87e8a8d7ff824acce7b050b6` reuse worker379/runtime16/
Arc4/editor origins/metadata5/owned Git30+promisor60 qualifications. These were not rerun as SET-04
worker checks. Final package correlation and Mac119/product graph/spec140/204 pass.

Only recorded Preview570836 was replaced by601784 with original configuration/shortcut/full backup.
The actual preservation verifier confirms all nine0x80080 HWNDs and prior IDs/XY/compact/scopes/
preferences/accounts/distributions/defaults/startup, singleton0 and no old worker proxies.
TRAY2cc/570836 and prior failed packages/reports remain preserved. Token-body ordering uses fake
verification/writes; no real token/provider/notification/lifecycle/Git mutation or desktop capture
was used for this qualification.

## Limits

Owned WPF/synthetic geometry and fake credential availability do not qualify live credentials/provider
permissions, physical keyboard/screen-reader behavior, exact Mac/Windows collation, native Mac/x64,
display/shell/phone/signing/clean-machine or arbitrary hardware recovery. TRAY-07 remains partial
for native updater install/available-update notes. SET-02/08, full summon and full migration remain
open. The next SET-02 geometry plan is accepted, without implementation/qualification at this
checkpoint. This is an unsigned development artifact, `releaseQualified=false`.

Implementation: [ordering](../../Windows/DevDeck.Windows.Core/SettingsSidebarOrdering.cs),
[credential metadata](../../Windows/DevDeck.Windows.Core/WindowsTokenStore.cs),
[retained row](../../Windows/DevDeck.Windows.App/SettingsSidebarRow.cs),
[settings window](../../Windows/DevDeck.Windows.App/SettingsWindow.cs),
[guarded publication](../../Windows/DevDeck.Windows.App/DeckController.SettingsSidebar.cs),
[physical owner](../../Windows/DevDeck.Windows.App/ProjectCard.cs) and
[explicit token commit](../../Windows/DevDeck.Windows.App/AccountSettingsForm.cs).
Original source: [list reconciliation](../../Sources/DevDeckApp/SettingsWindowController.swift#L270),
[sidebar rows](../../Sources/DevDeckApp/SettingsListView.swift#L149) and
[token presence](../../Sources/DevDeckApp/Modules/SettingsSection.swift#L93).
