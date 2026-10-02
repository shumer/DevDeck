# 0041 — Windows settings window size persistence

Status: Accepted; scoped size behavior qualified and active. Date: 2026-10-02.

Windows settings previously reopened at1020×720 DIP after every restart. Mac uses AppKit frame
autosave with fixed1076-point width; copying its frame/content dimensions would remove the
already supported Windows resizable width. Preserve resizable width and height,1020×720-DIP
defaults and880×440 minimum, and persist only completed normal user resize intent.

## Size contract and persistence

Add the last optional `DeckSettings.SettingsWindow` record, `SettingsWindowGeometry(Width,Height)`.
Null remains omitted and preserves the old defaults. Valid new width is finite880…10000 and height
440…10000 DIP. A bounded type-local converter treats malformed syntactically valid optional stored
size as null without discarding otherwise valid settings; whole invalid JSON remains outside that
fallback. Invalid new size writes are rejected.

`SettingsGeometry.Restore` clamps only the effective opening size when both finite logical work-area
dimensions meet880×440. It retains the chosen saved size. Smaller/unavailable/unsupported area
measurements do not partially clamp or authorize a reduced invalid saved size. Existing MaxHeight
uses the same whole-area support predicate; there is no new MaxWidth. Coordinates, monitor identity,
display homes/parking and mixed-DPI restore are outside this size-only record.

The HWND hook captures the current normal size at WM_ENTERSIZEMOVE and admits changed size after
WM_EXITSIZEMOVE through deferred layout completion. It revalidates generation, current owner/HWND,
UI Dispatcher, visibility, normal mode, lifetime and unchanged requested exit dimensions. Initial
layout, programmatic resizing, page/search/sidebar changes, moves alone and minimize/maximize do
not persist. Hide/state change/close/replacement invalidate pending receipts. Both Closing and
CloseSettingsAsync invalidate intent before metadata Flush/Yield; a refused invalid-draft close
still permits a later user resize. live:false sample windows never persist their layout changes.

The precise controller path copies the latest accepted Settings with the size, persists that model,
then assigns Settings after success. It does not enter project actions, discover/rebuild owners,
read credentials, change worker transports/polling or reset attention/Seen/queues/check time.
`SettingsGeometry.PreserveCurrent` merges the latest geometry into older queued metadata commits.
Resizing retains the actual form, invalid draft, password/token draft, search/focus/caret, current
row error and pending health-check owner/token.

The path writes the accepted domain model rather than raw legacy JSON spelling/unknown fields.
Existing SettingsStore.Load materializes default/migrated Arc links from legacy null; the next
current-model save may persist that existing normalization. The size feature does not change that
migration. Its strict fixture seeds canonical Arc links before initial Save rather than hiding
normalization after a failed comparison or removing Arc coverage.

A failed size save preserves committed size/model and the usable actual form. A separate localized
nonmodal banner reports the error without replacing the form's current error. A later completed
resize retries and clears only that banner, without a generic Saved dialog. The fixed245-DIP
sidebar/current styles and stretched vertical-scroll forms remain. Actual six-language footer
bounds passed; suspected French/Italian bitmap row differences did not establish clipping, so the
original footer is unchanged.

## Qualification and activation

The original production baseline15d79f6418d2467bbc44bd80649b3320 exited1/2.42s: a completed owned
940×560 native resize reopened1020×720 through a fresh controller/window against the same owned
NTFS store. Positive native/WPF/configuration/clock/no-poll premises passed. After implementation
the reopen component3e07 passed1/0 exit0/3.71s and footer component4388 passed6/0 exit0/6.35s.

The actual held-Flush close racead0a24f14bfc402daa97cd91638bb66d exited1/3.82s after a warning-free
39.95s build. Both explicit CloseSettingsAsync and native Closing committed940×560 once while
actual Flush remained pending/current window visible. Start-of-close invalidation was applied
after this red. Original package/report/log remain retained.

The first full geometry componentf0e11d70e6044f56b4a35e3c5ff0eff0 exited1/9.88s after warning-free
45.38s build at post-retry preservation; initial failed-write/exact target+backup/form/focus/error
and successful retry assertions passed. Diagnostic-only cb42e3b77b264dc5a303687899e9aecc exited1/
3.22s after warning-free48.05s build with only persisted `$.cards[2].links` changed. Current model,
clock, signals, pending/delivery queues and polling were identical. Canonical Arc links were then
supplied before initial fixture Save. Strict comparisons, diagnostics, Arc and23-case count stayed;
no corrective post-failure save/product migration change/assertion relaxation was introduced.

Fresh component12a5696cc4344dee8a66f88e4d9d4c39 passed23/0, observed exit0/31.75s after warning-free
45.82s build. It remains historical and separate from the final full run. Geometry cases include
real held action gate/nonempty eligible attention/Seen/pending/queue, retained owner/HWND/snapshot/
uncancelled injected read, stale metadata merge/current owner admission/pending receipt cancellation,
failed-write banner/retry/invalid-draft refused close/password focus and six-language216 actual
page/font/size layouts. Each layout requires named real controls; bounds and trailing BringIntoView
premises are meaningful. Fixtures dispose hidden owned windows and isolate health/discovery/vault.

Final immutable3779f95e4665421bb0c218a54cea339e passes actual apphost Core4 focused/full218,
fullnative1515/0 observed exit0/232.51s, installer8/0 exit0/38.33s with identical manifest,
read-only7local+2remote exit0/45.58s and282 completed six-language synthetic views (30geometry).
The23 new native cases are extracted from final full1515 (`standaloneRun=false`), not described as
another final standalone run. Native1515 retains1492 old cases;282 views retain252 prior scenes
plus five minimum880×440/font18 scenes across six languages. Owned ru/en/fr/it PNG subsets of
General/Deck/project/account/error/sidebar/attention were reviewed; no desktop capture was used.

App SHA256 `EC4C62F7DF903BA0FE6EC886CDB876D84C6901B6D9F7A746FBBB056BCF255A8D` and manifest
`95207F63806C5F9D8FD1E40E77C79EC85DBA030DDAFDB84A615225D3F1E261F7` correlate final execution,
installer and completed renders; no wrapper restoration was used. Actual Core apphost test-artifact
correlation is distinct from RID-package hashes, without a byte-equality claim. The exact unchanged
TRAY archive `d9fc85a3407dc4cac2e43ec95a468f5c3cbc37ea27641238f762a0caf54d4bc3` and binary
`abd86a21d68f3895259608521fe16053e17eeefb87e8a8d7ff824acce7b050b6` reuse worker379/runtime16/
Arc4/metadata5/owned Git30+promisor60 qualifications; they were not rerun for this UI batch.
Mac119/product graph/spec140/204 and source/diff guards pass.

Only recorded Preview601784 was replaced by627264 with final3779. The actual verifier confirms all
nine0x80080 HWNDs, prior IDs/XY/compact/scopes/preferences/accounts/distributions/original config/
shortcut/full backup/default settings/startup, singleton0 and old proxies0. Absent size remained
absent; activation itself does not materialize user geometry. Original failures/artifacts remain
retained, and the full prior SET-04/TRAY/WIF/visibility/arrangement checks stay in the native suite.

The native write-failure seam throws before Store.Save and compares exact owned target/backup
bytes/existence plus model/form/focus/banner state. It does not prove an actual native filesystem
atomic replacement failure; Core's actual atomic failure/recovery proof is separate. Owned synthetic
controllers/checkers/token drafts/queues/native HWNDs are used throughout; no real credential/
provider/project lifecycle/browser/terminal mutation is performed for qualification.

## Limits and separate source-claim corrections

SET-02 remains Partial for OS sidebar-size metrics and physical display acceptance. This Windows
resizable-width adaptation is explicit rather than a fixed-width Mac copy. Coordinates/display homes/
DPI/parking, SET-08 provenance, updater install/notes, full summon and native Mac/x64/live identities/
phone/physical input/accessibility/display/shell/signing/clean-machine/full migration remain open.
This unsigned development package remains `releaseQualified=false`.

The same documentation pass corrects earlier claims without implementing account behavior:
ACC-03 remains Partial for absent token-creation links and empty-field stored-token Verify, retaining
qualified nonempty verify/save/Return proofs. ACC-09 already reads current browser/profile/endpoint
Draft() inside Test click; picker/fallback proofs do not qualify a live signed-in click. SET-11
fresh/missing settings use120 seconds while omitted legacy RefreshSeconds retains60; repositories
are per-account and differ from Mac's deck-wide/Actions-off-disabled watchlist. Provider-applicability
implementation is a separate later batch and is not shipped/qualified by this package.

Implementation: [geometry contract](../../Windows/DevDeck.Windows.Core/SettingsGeometry.cs),
[settings persistence](../../Windows/DevDeck.Windows.Core/Settings.cs),
[current-owner commit](../../Windows/DevDeck.Windows.App/DeckController.SettingsGeometry.cs),
[settings window](../../Windows/DevDeck.Windows.App/SettingsWindow.cs),
[owned native proof](../../Windows/DevDeck.Windows.App/SettingsGeometryTests.cs) and
[synthetic scenes](../../Windows/DevDeck.Windows.App/SettingsGeometrySamples.cs).
Original source: [Mac geometry](../../Sources/DevDeckApp/SettingsWindowController.swift#L107),
[measured form layout](../../Sources/DevDeckApp/SettingsForm.swift#L234) and
[OS sidebar metrics](../../Sources/DevDeckApp/SettingsListView.swift#L365).
