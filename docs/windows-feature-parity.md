# macOS / Windows behavior audit — 2026-10-02

The authoritative acceptance inventory is now the [Mac functional specification](macos-functional-spec.md):
140 source-referenced behaviors covering defaults, persistence, side effects, failures and complete
flows. This page retains historical completed evidence. The current SET-08 adaptation is qualified
and active in Preview78356: Core226/provenance16/native1587/installer8/read-only9/render372. Its
checkpoint, historical ACC-03/provider evidence and remaining gaps are recorded at the end. Earlier broad rows must not be read as
proof of all newly enumerated scenarios. Arc org/site/hosted/template links, local editor and DDEV
templates/kinds and generic Detect/caption/separate opening URL now have implementation and
qualification below. Settings keyboard/check behavior and browser discovery/profile/fallback are
qualified and active in the development Preview; real browser/account acceptance remains open.
Remaining gaps include tray navigation, ordering/cadence, geometry/parking and summon semantics.
Natural tray/catalog and explicit-Tidy order is qualified and active in the development Preview.
At that catalog checkpoint SET-04 was still open: saved sidebar order lacked flat natural groups,
runtime dots and disabled-row dimming. The later qualified sidebar subset is recorded below.
The branded Windows tray glyph and attention shapes are restored; this does not close the separate
application-icon artwork, notification delivery or full release gates.
TRAY-05 tier overflow, visible subtitle/account/age and a calm check time are qualified and active
in the Preview. Native menu geometry and synthetic main/overflow/calm/browser views pass;
TRAY-06 deck actions are qualified. The TRAY-07 supported subset is now qualified and active570836:
scoped Alt read→dismiss, exact personal Inbox targets including URL-less items, explicit full-list
actions and current primary routes. The row remains partial for native updater install/notes;
physical Alt/IME/screen-reader acceptance is separate. Existing broad Inbox read controls stay intact.
UI-08 card menus and the draft-safe visibility path are qualified and retained in Preview484424, including
current compact/log/lock state, Tidy, active-card refresh and explicit Inbox read-rest/read-all rows.
Core122/0, portable worker328/0, native1165/0, installer8/0 and fresh read-only/runtime checks pass;
sixty synthetic views pass. The owned update preserves all existing settings and nine native widgets.
The TRAY-06 dashboard/active-refresh/arrangements and precise Deck modes subset is qualified and
retained in Preview484424: Core132/native1261/installer8/fresh read-only/runtime/synthetic84 passed.
DD-05/all-DDEV poweroff and the remaining TRAY-06 action are qualified and active in446868.
Final Core149/worker345/native1328/installer8/synthetic102 and fresh read-only/runtime checks pass.
Lifecycle qualification uses fake CLI only. SET-04 was open at that poweroff checkpoint; its later
subset follows. Updater/external gates remain open.
WIF and shared provider/log/checkout cadence are qualified and active in Preview484424. Final
Core183/worker367/native1396exit0/installer8/synthetic192/read-only7+2/runtime16/Arc4/metadata5 and
owned ordinary Git30/promisor60 checks pass. The exact owned update preserves all nine widgets/settings;
default-off actual integration performs no Git reads. Original Mac119/product graph/spec140/204 stay
unchanged. Installed disposable Git fixtures do not establish arbitrary repository/program parity.

Reference: implemented Mac modules, README, SettingsPages/SettingsWindowController, project cards,
LogWindow and LocalFolder. A shared API kit or matching button label does not establish UI parity.
Mac execution is unavailable; findings below are source-level comparisons plus Windows qualification.

| Behavior | macOS reference | Windows before this step | Action / evidence |
| --- | --- | --- | --- |
| Native desktop cards and switcher exclusion | AppDelegate / CardHostView | Implemented; native styles qualified | Retain existing regression |
| Local start/stop/restart, progress/cancel | three project modules / DeckController | Implemented and owned fixture qualified | Retain guards and lifecycle tests |
| Folder and terminal in the correct checkout | LocalFolder | Implemented with Windows Terminal/WSL fallback | Check literal paths/distribution and log terminal action |
| QR / phone link | PhonePopover / LocalAddress | Missing | Implemented: Windows physical LAN discovery, loopback-only rewrite and QR; independent decoder passed short/Unicode/long URLs. Phone network reachability remains external |
| Log window | LogWindow / controller open-log polling | Partial: one snapshot, 80 lines, duplicate windows | Implemented: singleton, visible-only polling, follow/search/source/file, terminal logs and geometry. Native tests and seven actual read-only tails passed |
| Collapsed project controls | three project card collapsedActions | Partial: header only | One compact row with lifecycle/terminal/running site; folder/log/QR/refresh/settings in context menu. Six-language native layouts and reparenting checked |
| Project repository/branch link | project cards / kit status | Branch text only; repository URL not exported | Shared repository URL exported and opened through project browser; branch text retained |
| Project tool/environment links and browser | project model/configuration forms | Partial: local site only, project browser absent | Typed dynamic template/enabled/kind rows, browser/profile and persistent environments implemented; hosted/local gating and Arc options/local editor covered by ADR0029. Installed browser/friendly Chromium picker/default fallback qualified and active; live identities remain external |
| DDEV Mailpit/xhgui links | DDEVProject.toolLinks | Missing in Windows UI | Shared resolved links shown only while running, with independent autosaved visibility switches |
| All-DDEV poweroff | DeckController.powerOffDDEV / DDEVEnvironment.powerOff | No native tray/group operation | Qualified/active446868: connected-Docker scope and frozen distribution list, Cancel default, typed all-actor prepare barrier/renewals, serial shared command, captured identities/no run retry, physical bulk outcomes and retained hidden/compact owners. Final Core149/worker345/native1328/installer8/synthetic102/read-only/runtime checks pass; fake CLI qualification only. ADR0037 |
| Remote PR/inbox/Actions/GitLab cards | GitHubModules / GitLabModule | Snapshots existed but lost ordering/status/summary/collapsed actions | Restored shared priority/status codes, 3/12 rows, counts/health bar, account dashboards, full lists, Inbox cutoff/progress/cancel and Actions failure/active/quiet metadata. Detailed matrix: [remote audit](windows-remote-parity.md). Real API acceptance remains open |
| Account setup/card visibility | CardCatalog / DeckMenu | Accounts saved without cards; tray visibility list absent | Shared catalog bootstraps PR/Inbox, offers Actions/MR, retains hidden legacy cards and exposes tray/settings toggles plus local groups |
| Work in flight | WorkInFlightModule / CheckoutInspector | Missing | Qualified/active484424: default-off optional fixed-ID preference, all configured folders including hidden sources, typed offline reads, retained three/twelve-row/compact card, exact terminal target, scoped informational attention and shared provider→logs→checkout cadence. Core183/worker367/native1396/installer8/synthetic192/read-only/runtime and owned Git30+60 pass; Mac119 unchanged. ADR0038 |
| Hidden card makes no fetches | controller active-card set | Implemented by rebuilding enabled cards | Retain; check logs/window lifecycle |
| Settings sidebar and search | SettingsWindowController / SettingsListView | Missing: one long local-project page and extra windows | Present — flat natural account/project groups preserve saved ties independent of deck order; current hidden local owners supply Running/Busy dots. Disabled entries remain selectable with dimmed icon/title and undimmed dot. Exact-target cached credential availability and list-only reconciliation preserve drafts/password/focus/search/scroll/attention/check time. SET-04 qualified at601784 and retained in78356; historical Core214/native1492/synthetic252, ADR0040. SET-08 adaptation is qualified separately; SET-02 OS metrics and live/accessibility/native gates remain separate |
| Settings window size | SettingsWindowController frame autosave / measured scroll layout | Resizable1020×720/min880×440, size lost on reopen | Partial — normal-user-completed width/height persistence qualified/active627264, preserving forms/drafts/focus/CTS/runtime and latest metadata merge; effective supported-area clamp never rewrites chosen size. Windows resizable-width adaptation, no XY/display homes. Actual Core4/full218/native1515/installer8/synthetic282/read-only7+2 pass; OS sidebar metrics/physical display acceptance remain open. ADR0041 |
| Running-copy provenance | GeneralSettingsPage bundle/build/location | Informational version only | Adapted/Gate — cached startup informational version, labelled assembly fallback, loaded App MVID and distinct process/module paths; once-only provider, independent bounded fallback, readonly accessible fields and exact informational updater input. Qualified/active78356: Core226/provenance16/native1587/synthetic372; no package trust, Mac marketing/build counter/translocation or native-release equivalence. ADR0044 |
| Settings contextual navigation | module settingsTarget / showSetting | Generic settings opens | Local card opens its project; single-account remote card/error opens its account; multi-account card opens Cards |
| Provider-specific account fields and request scopes | AccountSettingsForms / GitLabAccount | GitLab exposed GitHub filters/failed-run controls; unused legacy scopes were sent and reparsed | Qualified provider subset retained in78356; historical39204 Core4/full222/native1541 proof: Address before token, new-draft switch/provider lock, inactive GL arrays/preferences and raw unedited GH arrays preserved, empty GL request projection, guarded explicit scope edits/revisions and actual current-Draft Test fake proof. Local ACC-03 actions are qualified separately; live identity remains open. ADR0042/0043 |
| Autosave configuration, explicit verified token save | SettingsForm / AccountSettingsForms | Partial: project/account metadata needs Save | Quiet serialized saves and nonempty verified replacement retained. Provider creation and separate/empty-input stored Verify qualified in68312 (Core226/token30/native1571) and remain in78356: current browser/endpoint/manual Enterprise page, exact committed credential/full-route tickets, owner epochs, scoped autosave pause, separate result row and precise presence-cache update. Half-entered replacement and metadata errors survive. Live permissions/browser identity and older replacement ID/slash limitations remain open; ADR0043 |
| Scoped health row and removal confirmation | local/Arc modules / SettingsListView | Generic Saved overwrote feedback; checks had no fresh owning row; removal lacked confirmation | Dedicated row uses original worker summary and rejects changed identity/generation/lifetime; relevant edits auto-check. Ephemeral project.check and separate transport isolate drafts from live observations. One cancel-default removal path. Worker317/Core96/native1034 pass; active Preview preserves old settings |
| Deck floating/lock/arrange/arrangements | DeckSettingsPage / menu | Available mainly in tray; partial settings | Floating/lock/saved arrangements in Deck page; tray tidy measures native visible heights, uses 12-DIP gaps/column wrapping and preserves anchor/snapshots. Header/context/settings compact controls added |
| Catalog/tray/Tidy order | CardCatalog.projectOrder / sortedByTitle | Tray kind groups retain added title order; Tidy consumes stored arrays | CardOrdering provides built-in roles/extras then Arc/DDEV/plain natural titles and permanent-ID ties without rewriting settings. Core104/native1041/installer8/read-only qualification pass; active Preview retains all settings/windows. SET-04 remains separate; see ADR0033 |
| Summon shortcut / close gaps / dim | DeckSettingsPage / SummonKey | Fixed Ctrl+Alt+Space; no dim/packing preference | Audit and implement native equivalents separately |
| Refresh interval | CardsSettingsPage | Fixed local/remote intervals except inbox server hint | Same60/120/300/600-second choices; fresh/missing settings default120, legacy omitted RefreshSeconds retains60 and explicit saved choices stay. Server minimum preserved. Actions repositories are per-account; Mac deck-wide/Actions-off-disabled watchlist remains partial |
| Notifications/attention/history | shared builders / NotificationsSettingsPage | Implemented; six-language forms qualified | Retain; controlled cross-distro Docker episode gate still open |
| Tray attention presentation | AttentionDigest / DeckMenu.addAttention | Five rows per tier, tooltip-only subtitle and no calm check time | Three urgent/two informational rows, single-leftover direct and tier overflow; native visible subtitle/account/age, full accessible/tooltip text and disabled none actions. Calm host-observation clock is a Windows adaptation. Core112/native1103/installer8/read-only/synthetic geometry checks pass and remain active in Preview437068, ADR0034. TRAY-06/07 remain separate |
| Tray/full-list attention actions | DeckMenu primary/Option alternate | Main/overflow rows dispatch primary only; AttentionWindow supplies permitted project Dismiss | Partial — supported primary targets, same-owner hidden project/log reveal, scoped Alt read→dismiss and explicit full-list buttons qualified/active570836. Exact personal Inbox card/account/origin/thread targets support URL-less reads, current admission, tuple optimistic masking and no lost-write replay; primary.none stays inert. Core202/worker379/native1468exit0/228synthetics/read-only/runtime/preservation pass, ADR0039. Native updater install/available-update notes and physical Alt/IME/screen-reader/external gates remain open |
| OS credential storage and account browser profiles | Keychain / LinkOpener | Credential Manager and raw remote profiles implemented | Vault/verification retained. Supported installed browsers/friendly Chromium profile names, retained/ignored old Firefox profiles and missing/start-failed default fallback are qualified and active. Core96/native1034 pass; live identities and real vault actions remain external |
| Updates | GeneralSettingsPage / Updater | Check opens release notes; no installation | Keep explicit missing parity; signing/publisher gate |
| Display parking and restore | PanelPlacement / DeckParking | Initial/reachable-window recovery only | Expanded native hardware/shell acceptance needed |
| Arc organizations/catalog and legacy local stack catalog | CardCatalog isImplemented=false | Not implemented | Excluded from parity target: Mac does not ship these cards |

Current implementation order: requested phone/log/terminal functions, settings navigation/forms,
remaining card/action/configuration gaps, then qualification and owned Preview replacement. Update
each row with concrete checks after its implementation; never declare full parity from this inventory.

Final local qualification for this iteration: Windows/WSL 77/0, native UI 136/0, Swift portable 286/0,
installer 8/0 and native seven-status/tray integration exit 0. Owned Preview PID 184120 preserves seven
tool-window cards, all original project/preference/position fields, singleton and startup behavior.
Sixty-six final renders use synthetic data only. Mac preservation contract passes 119 files + graph;
native Mac behavior, live accounts and actual phone networking remain unqualified.

Screenshot-reference follow-up: Core 50/0, native UI 154/0, installer 8/0, seven actual-card/tray integration exit 0 and 54 synthetic views. Owned Preview settings/positions/Alt+Tab preserved; original Mac graph and 119 frozen files unchanged. Native Mac/x64/real-account/phone/network/signing qualification remains open.

Remote-card follow-up: shared priority/status/counts/dashboard behavior, 3/12 rows, Inbox cutoff/
progress/cancel and Actions failure/active/watch/quiet behavior restored. Window-only token drafts,
account scope editing and browser checks added. Swift 291/0, Windows/WSL 84/0 (Core 54/0), native
UI 340/0, installer 8/0, seven actual statuses/tray, 96 synthetic views; owned Preview PID 225408,
original configuration/defaults/startup and seven switcher-excluded widgets preserved. Detailed
scope and remaining live-account/settings workflow gates: [remote audit](windows-remote-parity.md).

Card-discovery follow-up: account setup/startup now creates shared PR/Inbox defaults, exposes every
remote type in tray/Settings and groups local-project visibility. Stable legacy identities/scopes/hidden
states/positions retained; automatic scopes follow new accounts. Account removal detaches references;
inactive scopes close windows and stop polling. Core 60/0, native UI 355/0, installer 8/0; read-only
seven-local/two-remote native integration and six final synthetic settings views. Owned Preview
PID 235652 has nine HWNDs 0x80080, original local config/preferences/defaults/startup preserved,
singleton exit 0/old proxies 0. PR 4 and Inbox 13 (one forbidden account); GitLab remains unconfigured.
Mac contract 119 files + active graph unchanged; native/external release and wider parity gates remain.

Columns/compact follow-up: tidy now uses native occupied bounds/DPI and pixel-snapped persisted
positions, 12-DIP gaps, visible-card heights, work-area wrapping and current anchor/order. Existing
windows/snapshots are retained; hidden positions stay intact. Accessible header/context/settings compact
controls preserve saved state. Core 65/0, native UI 388/0, installer 8/0, read-only seven-local/two-remote
integration and 30 synthetic views. Owned Preview PID 256728 retains nine excluded HWNDs, original
config/positions/compact flags/preferences/defaults/startup; singleton exit 0 and old proxies 0.
Mac contract 119 files + graph unchanged. No automatic packing/rearranging on update; native/external
full release and wider parity gates remain open. See ADR 0025.

DDEV metadata follow-up: the production worker now exports shared PHP/database versions through
an optional versionsLine field, separately from Arc engineVersion. Framework/checkout and versions
remain visible for stopped/paused/unknown projects and alongside warnings; compact cards hide them.
All reported Mailpit/xhgui URLs reach the host's saved visibility switches; new xhgui defaults off.
The prior sample-only EngineVersion text masked the omission; production regression failed before
the fix. Portable293/0, Core67/0, nativeUI484/0, installer8/0, seven-local/two-remote read-only
integration and five independently matched checkout configs passed. Templates/kinds and live xhgui
service/browser acceptance remain open. See [ADR0027](adr/0027-ddev-worker-metadata.md).

Local-poll follow-up: native ten-second shared loop, explicit-cycle DDEV inventory and separate
local/remote connections replace per-card15s polling/repeated CLI calls/transport blocking.
Production cycle regression failed293/1 beforefix; greenSwift297/Core70/nativeUI486/installer8
qualification includes busy/closed/overlap/new/manual/import/action/error/reconnect semantics.
Existing saved remote refresh choices remain unchanged. See [ADR0028](adr/0028-local-poll-cycles.md).

Compact-operation follow-up: native busy cancellation no longer overrides compact icon width with
its expanded text-button minimum. Start/stop/restart keep a 30-by-32-DIP cancellation control;
repeated expand/collapse preserves progress and keeps idle actions hidden until final state.
The new native regression failed before the fix, then native UI540/0, installer8/0, seven-local/
two-remote read-only integration and five independent DDEV checkout metadata matches passed.
Synthetic before/after views cover DDEV/Arc/local; Mac119 files/product graph stay unchanged.
Shared Swift/Core behavior is unchanged; full migration and external release gates remain open.
Owned compact-fix Preview293388 preserves all nine switcher-excluded widget windows, original
positions/compact flags/preferences/scopes/distributions/defaults/startup, singleton exit0 and
old worker proxies0. The existing shared Swift297/Core70 qualification remains unchanged.

Arc/DDEV configuration follow-up: organization/site/local origin/health/custom start-stop options
reach the original ArcProject through optional protocol1 fields; its local PageBuilder URL is
exported. Hosted-only Arc needs no status worker; later folder attachment retains card identity.
Typed link rows replace raw URL text, retain kind/template/disabled values and custom add/rename/
remove, with exact-only old Arc template correction. Hosted destinations remain usable during
stopped/working states; local destinations follow runtime. Actual Mac health default is /release,
corrected in the specification. See [ADR0029](adr/0029-arc-options-and-project-link-templates.md).
Portable302/0, Core75/0, native564/0, installer8/0 and read-only seven-local/two-remote integration
qualify this subset. Both installed worker hashes match the qualified ARM64 binary; both existing
Arc editor URLs match local origin/shared path, and five DDEV metadata lines still match configs.
Native Mac/x64, browser/phone/network, real Fusion lifecycle and complete migration gates stay open.

Arc/DDEV batch activated in owned Preview316304: all nine0x80080 widgets, old settings/IDs/positions/compact/scopes/preferences/distributions/defaults/startup preserved, singleton0/old proxies0. Primary distro hashes and actual Arc editor origins independently pass4/0. Complete migration and external gates remain open.

Generic-project follow-up: original ProjectProbe is available through file-only project.probe and
native add-folder/manual Detect. It retains chosen caption/health/name/opening URL and ignores a
changed checkout. Optional caption/openURL preserve legacy health fallback; typed links use the
opening address, card metadata separates caption/checkout from command, original glyph vocabulary
and Nest/Bun/Docker paths are retained. Browser Test follows Mac plain/Arc/DDEV target order,
including fresh DDEV URLs and saved hidden-tool switches. See ADR0030. Worker309/Core80/native593/
installer8, read-only7+2/generic16/Arc4/metadata5 and24 synthetic six-language views qualify this
subset. Owned Preview326432 keeps nine excluded HWNDs and all original settings/defaults/startup,
singleton0/old proxies0; both primary runtimes checked after activation. Complete migration,
settings/browser catalog/profile/fallback and native Mac/x64/external gates remain open.

QR availability follow-up (ADR0031): the running card and compact/stopped context menu open a code
or actionable guidance. Automatic rewriting accepts loopback and this PC's exact physical LAN IP;
routed DDEV hostnames remain protected. An optional independent phoneURL stores an explicitly
configured address already accessible from the phone. Copy dismisses; new status updates replace an
open code; failed reads invalidate it until a fresh snapshot. Core84/native738/installer8 and145
new synthetic six-language QR scenarios pass. Read-only seven-local/two-remote checks classify six
stopped services and one host-routed DDEV; five DDEV metadata lines still match existing checkouts.
Thirty-six synthetic QR/form views inspected. Original Mac119/product graph and shared worker
archive unchanged; existing portable309/runtime16 baseline retained rather than rerun. Owned
Preview330460 preserves nine0x80080 windows, all old settings/positions/compact/scopes/preferences/
distributions/defaults/startup, singleton0 and old proxies0. Both installed worker hashes and two
Arc editor origins reverified4/0. Actual phone/LAN/DDEV HTTP/DNS/firewall access remains an external
gate; no service/network configuration was changed and full migration is not complete.

Windows branch glyph correction: the project row now has a clear three-node fork and centered label,
replacing the U-shaped drawing. Existing native738/0, installer8/0, read-only seven-local/two-remote
integration and five DDEV metadata checks pass. Eighteen synthetic six-language/three-kind scenes
qualify the drawing. Core assembly and worker archive match the prior qualified package exactly;
Core84/portable309 are retained baselines. Mac119 files/product graph remain frozen. Owned
Preview332428 preserves all nine0x80080 widgets, settings/positions/compact/scopes/preferences/
distributions/defaults/startup, singleton0 and old proxies0. Full migration/external gates remain.

Settings/browser qualification — 2026-10-02: SET-03/07, ACC-05/08 and token Return are now
active in the Preview. Ctrl+F/sidebar arrows/guarded removal share one confirmation path; Return/Escape cancel
removal. Quiet autosave serializes concurrent flushes, keeps fields editable and preserves stable
new-project identity. Invalid metadata remains editable and guards navigation/close until corrected.
Arc/plain checks run on arrival/relevant edits in their own row and reject
stale identity/generation/lifetime; DDEV has no extra row. The worker supplies original localized
checkSummary/checkedAt instead of reconstructing state/refusal/ownership details in the host.
The ephemeral project.check operation uses a separate settings transport, neither registering
draft edits nor advancing live settling/attention; cancellation does not abort other worker channels.
Fresh DDEV browser-Test URLs use the same isolated path.
Supported installed browsers are discovered read-only, Chromium Local State supplies friendly
profiles, saved absent choices remain intact, Firefox profiles are ignored and every opening path
uses the default-browser fallback. See [ADR0032](adr/0032-windows-settings-checks-and-browser-choice.md).
Portable317/0, Core96/0, native UI1034/0 (296 new checks) and installer8/0 pass; production reds
cover browser routing, optional summaries, quiet-save focus and the missing project.check operation.
Read-only seven-local/two-remote integration checks the separate settings transport and fresh
summaries on two actual Arc projects. Runtime fixtures16/0, Arc runtime/origin4/0 and DDEV metadata5/0
pass. Forty-eight synthetic scenes were generated; full local/Arc forms were inspected. The
standalone browser fixture then needed a height correction and was not accepted visual evidence;
native profile-control checks pass independently. Only owned Preview332428 was replaced by354968,
keeping the original configuration/shortcut, nine0x80080 windows, IDs/positions/compact/scopes/
preferences/distributions/defaults/startup, singleton0 and old worker proxies0. No actual browser,
account/token removal, project lifecycle or network/default/profile mutation is certified by these
fixtures. Natural ordering CAT-04 is qualified in the follow-up below. Native Mac/x64/live
browser/real-account/phone/display/signing and full migration gates stay open.

Natural-order qualification — 2026-10-02: CAT-04 and the ordering part of DES-05 now use one
pure culture-aware projection for tray and explicit Tidy. Arc/DDEV/plain groups use numeric,
case-insensitive title order and permanent-ID ties. Remote roles keep the first saved card of each
kind, including legacy IDs; later canonical/custom cards remain independent and follow natural titles.
Persisted arrays, IDs/scopes/visibility/compact flags and hidden placements are not rewritten. Tidy
uses existing measured windows; native fixtures check HWND/snapshot/busy-state/gap/wrap preservation.
At that checkpoint SET-04 remained open: the sidebar used saved arrays and had no flat natural sorting,
runtime dots or disabled-row dimming. See
[ADR0033](adr/0033-windows-catalog-and-tidy-order.md). Core104/0, native1041/0 and installer8/0 pass
after a production native red against the previous tray order. Warning-free ARM64 package and
read-only seven-local/two-remote/tray10s integration confirm three independent transports; generic
runtime16/0, Arc runtime/origin4/0 and DDEV metadata5/0 pass. Unchanged worker317 qualification is
retained with a byte-identical archive, not rerun. Mac119/product graph and spec140/204 pass.
Forty-eight synthetic six-language scenes were generated; local/Arc/account forms were inspected.
Standalone browser320-DIP height restored its profile row, but at this snapshot the margin root
still cropped the right edge; browser-bitmap acceptance was withheld until the tray follow-up below.
Only owned Preview354968 was replaced by380656, keeping the original configuration/shortcut/
full backup and all nine0x80080 windows, IDs/settings/positions/compact/scopes/preferences/
distributions/defaults/startup, singleton0 and old proxies0. User projects/lifecycle/browser/account/
network rules were untouched. Native Mac/x64/live browser/real-account/phone/display/signing and
full migration gates remain open.

Tray-attention qualification — 2026-10-02: TRAY-05 now projects already validated worker
signals into three rows for waiting/needs-fixing/stuck and two for good-to-know. One leftover stays
directly visible; larger sections use same-tier submenus preserving each item's identity, target and
enabled/none guard. Native keyboard-operable rows show the title, trimmed subtitle/account and
age, with complete tooltip/accessibility text and reused brand marks. Rebuilding the menu disposes
its owned bitmap resources. The empty state includes local HH:mm from the host's last receipt of a
validated worker attention observation, or current time before any observation. Event Since/UpdatedAt
and ephemeral settings checks do not masquerade as check time. This is an explicit Windows clock
adaptation: the existing protocol does not carry the Mac controller's aggregate lastCheckedAt.
The production native red in windows-tray-red-ui.json fails exactly five waiting items where the
old Take5 menu loses the three-direct/two-overflow split. A package-level geometry red in
windows-tray-layout-red.ps1/json also captures the age/right-subtitle clipping. Production sizing now
uses bounded row preferences for main/overflow widths, uniform full-width rows and owner-client
painting bounds; native title-column text uses the visible Unicode prefix while accessible names,
tooltips, keyboard prefix and action identity remain intact. Core112/0, native1103/0, installer8/0
and warning-free ARM64 qualification pass. Fresh read-only seven-local/two-remote/tray10s integration
confirms three independent transports and original Arc summaries. Worker317/runtime16/Arc4/
metadata5 remain the explicitly reused, byte-identical b526 baseline, not rerun.
Twenty-four synthetic views qualify main/overflow/calm/browser: inline ages/subtitles and browser
profile/right controls fit. The browser Grid margin root fixes the prior standalone fixture crop.
Mac119/product graph and spec140/204/whitespace pass. Only owned Preview380656 was replaced by
408076/package206e7033c2854ea584be774b0e62900f, preserving original configuration/shortcut/full
backup, all nine0x80080 windows, existing IDs/settings/positions/compact/scopes/preferences/
distributions/defaults/startup, singleton0 and old proxies0 (windows-tray-preview-checks.json).
Mac/worker sources remained unchanged for that batch. TRAY-06/07, real accounts/browser/phone/display,
native Mac/x64/signing and full migration gates remain open. See
[ADR0034](adr/0034-windows-tray-attention-presentation.md).

Visibility/context qualified and active — 2026-10-02: card/tray/settings visibility now shares an
exact-permanent-ID action that commits only the selected Enabled value without waiting for an
unrelated lifecycle action. Hidden owners retain HWND/snapshot/operation/transports/list/log state;
new polling and their own transient QR/context stop. Summon, display recovery and Tidy respect
visibility; actual removal/shutdown still dispose owners. Context Hide and Settings retain current
card identity and update labels/availability on opening. Menus also expose live lock/Tidy and
RefreshAllAsync for all active local/remote cards using existing busy/coalesced poll guards, not only
the clicked card. Project log show/hide follows the ordinary log window and is disabled in compact
mode. Inbox offers explicit read-rest/read-all rows using failure-free displayed per-account cutoffs,
with current mutation guards; this adapts the Mac's Option alternate without changing attention-menu
modifier behavior. Existing shown-checkbox Click is separate
from metadata autosave; metadata commit reads current Enabled, so a captured old draft cannot undo
a hide. Open settings reconcile only matching controls/baseline, preserving invalid drafts/errors,
cursor, token drafts and page identity. New-project Add retains its explicit draft visibility.
Optional protocol1 activeProjectIDs bounds original local/Docker event generation without deleting
status/watch/settler/job history: nil keeps legacy behavior, [] produces no local attention. Visibility
revisions reject obsolete attention while retaining status/progress/errors, selected-source pruning
keeps sibling baselines/check time, and quiet reveal seeds old own alerts without suppressing new
sibling events. The production native red windows-visibility-red-ui.json records a legacy hide
blocked by the old global action gate. Final warning-free ARM64 qualification passes Core122/0,
portable worker328/0, native1165/0 and installer8/0. Fresh read-only seven-local/two-remote/tray10s
checks confirm three independent transports and two original Arc summaries. The new qualified worker
also passes freshly rerun generic runtime16/0, Arc4/0 and DDEV metadata5/0 checks. Sixty synthetic
views cover tray/browser and six-language idle/compact/busy card contexts. Mac119/product graph,
spec140/204 and whitespace pass. Only owned Preview408076 was replaced by413076/package
9b16d53b1d9d46fca8bca9fcacca4ad4. windows-visibility-preview-checks.json proves original
configuration/shortcut/full backup, all nine0x80080 windows and existing IDs/settings/positions/
compact/scopes/preferences/distributions/defaults/startup preserved, singleton0 and old proxies0.
Frozen Mac sources/product graph stay intact; additive worker behavior changes are outside that
graph. At that visibility checkpoint, SET-04, all-DDEV poweroff and TRAY-07 attention modifier twins
remained open. Full native Mac/x64/live identities/phone/display/shell/signing gates remain open. See
[ADR0035](adr/0035-windows-card-visibility-and-retained-owners.md).

Tray deck-command subset qualified and active — 2026-10-02: Open pull requests uses the fixed original public
dashboard URL and the first enabled GitHub account in saved order for browser/profile, falling back
to system choice without reading a credential or requiring a visible card. Actual menu click tests
use an injected recorder. Main-tray refresh invokes all eligible active local/remote paths with
shared local cycle IDs, busy/hidden/hosted skips and existing pending-read coalescing; jobs/transports
continue without cancellation, and different distribution results remain independent.
Saved arrangements capture the complete configured ID set, Enabled/preferred compact and saved XY.
Current-state matches produce dynamic menu ticks, independent of persistence order; drag/flag/ID
changes invalidate them. Trimmed case-insensitive overwrites preserve spelling/index, explicit new
saves keep the newest eight, and existing longer legacy lists survive loading/overwriting. Precise
Save/Forget preserve attention/check time/Seen/queues/owners; scoped Apply restores visibility,
compact and positions only for existing IDs. Unknown/deleted saved IDs are skipped, new cards are
untouched, and a stale removed name is a no-op. A busy remote collapse may remain partial with its
existing choice and ongoing work intact while XY applies; an idle retry completes it, without a
false full-match tick. In-place settings choice/mode reconciliation preserves other form/token/error/
cursor state. Deck floating/lock now use the existing direct setters with persistence before assign.
The name prompt and Deck page validate blank/control/128-character bounds. Save/Return trims;
Cancel/Escape writes nothing. Shared exact rounded field/button styles avoid a second settings window.
Tray named Forget is in an explicit Remove submenu; settings has a selected-name Forget control.
These rows adapt Mac's Option forget; TRAY-07 attention modifier semantics are still separate.
The production red windows-commands-red-ui.json records the missing original dashboard action.
Core132/0, native1261/0 and installer8/0 pass with a warning-free ARM64 package. Unchanged
worker328/b5c1 archive/suite qualification is reused, not rerun. Fresh read-only7+2, runtime16/0,
Arc4/0, DDEV metadata5/0 and84 synthetic views pass; Mac119/product graph/spec140/204 and whitespace
remain clean. Only owned Preview413076 was replaced by437068/package db0486ac622a43e083fbda7abbd848fb.
windows-commands-preview-checks.json proves all nine0x80080 windows and existing IDs/settings/
positions/compact/scopes/preferences/distributions/defaults/startup/original configuration/shortcut/
full backup preserved, singleton0 and old proxies0. Frozen Mac119/product graph remain intact;
at that command checkpoint all-DDEV poweroff, SET-04 and TRAY-07 remained open. Native Mac/x64/live
identities/phone/display/shell/signing/full migration gates stay open.
See [ADR0036](adr/0036-windows-tray-deck-commands-and-arrangements.md).

All-DDEV poweroff qualified and active — 2026-10-02: DD-05 and the remaining TRAY-06 action pass
the final package/runtime/owned-update checks. The command
scope is all DDEV on connected Docker servers, including off-deck/other-WSL projects, router and
SSH agent. The original Mac title/actions are retained; Windows replaces machine-only detail with
that accurate scope and frozen distribution names. Cancel receives default/focus, Enter/Escape/X
decline, and only explicit Power off accepts; the shared rounded tool-window styles preserve owner
topmost/no-taskbar behavior.

The bounded protocol1 capability adds prepare/run/finalize/abort with exact typed plans, token and
stable worker-instance identity. Capture every local polling actor before staging, require all
capabilities/prepare acknowledgements and renew all actors before each serial route command. Each
confirmed unique DDEV-bearing distribution calls unchanged DDEVEnvironment.powerOff once; its
catalog is reconciliation input, not a shutdown filter. Lost runs are never retried/reconnected.
Worker reservation/epoch and prepared intent overlays preserve existing mutation/read ownership,
block stale observations and restore base watch/settler exactly when never run. Monotonic 600-second
leases and bounded receipts prevent abandoned reservations; fresh physical inventory is reconciled
without cancelling existing consumers or clearing unrelated watches. Every prepared ID returns in
order, with command/inventory diagnostics separate from physical state; unknown/missing inventory
is never inferred stopped. Cleanup proceeds independently of a cancelled run token.

Native group presentation retains the same visible/hidden HWNDs, chosen compact/positions, log
windows and actual per-card CTS. Busy lifecycle/QR/refresh gating has no dead group Cancel or enlarged
compact Stop. Generation/token guards reject stale reads/progress; never-run abort restores prior
success/error presentation and check time. Physical failure preserves known metadata; no-status
failure is unavailable. Settings, Seen and queues are not globally reset.
Final Core149/0, worker345/0, native1328/0, installer8/0 and102 synthetic views pass against the
warning-free package. Fresh read-only7+2/capability hello (one actual configured DDEV distribution,
lifecycleInvoked=false), runtime16 in Ubuntu/Debian, Arc4/metadata5/Mac119/product graph/spec140/204
and whitespace pass. CLI lifecycle qualification is fake-only. Only owned Preview437068 was replaced
by446868/package bf3c10f14d724c7b90bcbfe51df429aa with qualifieda9 archive/1203 binary.
windows-poweroff-preview-checks.json proves nine0x80080 HWNDs and prior IDs/settings/positions/
compact/scopes/preferences/distributions/defaults/startup/original configuration/shortcut/full backup,
singleton0 and old proxies0. SET-04/TRAY-07 remained open at that poweroff checkpoint. Native Mac/x64/
live identities/phone/display/shell/signing/full migration gates remain open. See
[ADR0037](adr/0037-windows-ddev-poweroff-transaction.md).

Work in flight/shared cadence qualified and active — 2026-10-02: WIF-01–03/REM-04 now use one
accountless default-off aggregate, all configured Arc/DDEV/plain folders including hidden sources,
typed isolated one-checkout reads and exact current distribution/ID/path terminal targets. Existing
null preferences/legacy layouts and unrelated optional arrays stay intact. Started hidden reads keep
their lifetime/physical cache/HWND; obsolete attention/new admission stop at the current call. Routes
merge before global urgency/dirty/natural stable projection. Three/twelve rows and≤76-DIP compact
states retain first-two localized facts/full accessible text and the existing branch glyph. Checking
keeps prior full-pass time; partial/all-failed/incomplete/no-qualified-receipt results never falsely
claim current configured work is clean. Informational WIF scope has no banners/notification queue.

The controller shared cycle runs PR→Inbox→MR→Actions, custom extras, open logs and WIF, with
original coalesced delay/backoff/reset/hints, pre-admission hidden/busy guards and bounded source-error
isolation. Per-remote timers are removed; old omitted60/new empty120 preferences stay distinct.
Fixed child commands use GIT_OPTIONAL_LOCKS=0/GIT_NO_LAZY_FETCH=1/GIT_ALLOW_PROTOCOL=; the empty
allowlist explicitly denies Git transport independently of lazy-fetch support. Linux startup uses
original numeric-other fallback rather than the crashing Foundation stringsdict; native six-language
title/subtitle plurals regenerate from validated facts without altering shared policy/Mac resources.
Narrow atomic settings recovery retries only1175 with unchanged temporary/target/previous-backup
bytes or absence, at most five Replace calls/200ms admission, no non-atomic fallback. The original
external locker cause is unconfirmed; controlled owned backup-lock and13 focused tests prove this path.

Final Core183/0, worker367/0, native1396/0 observed exit0, installer8/0 and192 synthetic views
(102prior+90 WIF, six languages) pass. The first180-second helper timeout is retained; same immutable
artifact completes exit0 in180.05 seconds on its bounded rerun without changed source/assertions.
Fresh read-only7local+2remote verifies four checkout/settings/local/remote channels/shared cadence,
poweroff/checkout capability hello, lifecycleInvoked=false and default-off-no-Git; runtime16 in
Ubuntu/Debian, Arc4/editor origins, DDEV metadata5 and Mac119/product graph/spec140/204/diff pass.
Final archive0ea97b/binary7f57a8 has owned ordinary Git30/promisor60 checks: state/age/targets,
preserved HEAD/refs/config/index bytes+mtime, positive controls and honest missing-tree/missing-parent
outcomes with no worker transport-helper invocation. This does not qualify arbitrary repository
programs, every object/transport layout or untested Git packages. No actual user checkout/terminal,
provider mutation or lifecycle operation was used for qualification.

Only recorded446868 was replaced by484424/package02ea3db442754597aaeccb7315e1876d.
windows-wif-preview-checks.json proves all nine0x80080 HWNDs and prior IDs/settings/positions/compact/
scopes/preferences/distributions/defaults/startup/original configuration/shortcut/full backup,
singleton0/old worker proxies0. WIF stays default-off in existing settings. SET-04 flat sorting/
runtime dots/disabled dimming were still absent at this checkpoint, as were TRAY-07 attention
alternatives/Inbox read. The later attention subset is recorded below. Native Mac/x64/live identities/phone/display/shell/signing/
clean-machine/full migration gates remain open. See [ADR0038](adr/0038-windows-work-in-flight.md).

Attention alternates qualified and active — 2026-10-02: Preview570836/package
2cc50416402c48b9bab4ac6624d88107 adds scoped Alt read→dismiss and explicit full-list actions,
with source-bound personal Inbox targets before dedupe. Length-prefixed UTF-8 account/thread
identities avoid raw-ID collisions; original review-URL overlap and personal policy stay intact,
with no read-target graft onto a PR representative. URL-less reads work while primary.none stays
disabled. Current owner/account/provider/origin/scope/unread-row checks precede credentials/write;
pending optimistic masking changes only the selected tuple without resetting siblings/check time.
Hidden started work retains CTS/HWND, stale admission is false, failures remain visible and lost
writes are not replayed. Broad Inbox row/read-rest/read-all behavior remains unchanged.

Final Core202/0, worker379/0, native1468/0 observedexit0/181.91s, installer8/0 exit0/36.08s,
228 six-language synthetic views, read-only7local+2remote exit0/33.25s, runtime16/Arc4/metadata5,
exact d9fc85/abd86a owned Git30/promisor60 and Mac119graph/spec140/204 pass. The72 new native
cases are included in that full run, not a separate final run. Only recorded484424 was replaced,
preserving all nine0x80080 HWNDs/IDs/XY/compact/scopes/preferences/accounts/distributions/original
configuration/shortcut/full backup/defaults/startup, singleton0 and old proxies0.

Earlier reds and98d7 product-qualified1468/72/installer8/read-only9 are retained; its incomplete
render matrix was never activated. The sample-only4→5 waiting-item fix created a real overflow,
then the final2cc package was requalified. Physical Alt/IME/screen-reader, same-thread modal-menu
isolation, live credentials/provider writes/native Mac and the broader release gates are not
established by queued/fake fixtures. SET-04 was open at that TRAY checkpoint; the later subset follows.
Full summon behavior and native updater install/notes remain open.
See [ADR0039](adr/0039-windows-attention-alternates-and-inbox-read.md).

Settings sidebar qualification checkpoint — 2026-10-02: Preview601784/package
9563ba2b2a4242fa9a58c76f8b166764 uses stable culture-aware natural account/project groups,
independent of provider/kind/deck order. Current physical local owners, including hidden cards,
supply Running/Busy presentation; command/group ownership overrides an older running receipt,
while a failed poll retains accepted state. Disabled rows stay selectable, with selected white/
unselected dim title, icon0.45 and an undimmed seven-DIP dot/full localized tooltip. Metadata-only
availability is cached by exact credential target. Visible-window reconciliation catches up accepted
hidden-time receipts without rereading credentials. Current-owner/lifetime/reference guards reject
delayed replacement/removal publication. Retained rows preserve the active form/draft/password/
query/caret/focus/selection/scroll/debounce/CTS and sibling attention/Seen/successful-check time.

Meaningful old saved-order/absent-dot/dim reds, the genuine c5 opening gap, e61 fixture-readiness
failure and eced stale navigation expectation remain retained. Final Core214/0, native1492/0
observed exit0/296.17s, installer8/0 exit0/118.88s with identical manifest,252 six-language
synthetic views (24sidebar) and read-only7local+2remote exit0/32.34s pass. The24 new native cases
are extracted from the final full run (`standaloneRun=false`); the4988 component run is historical.
Final standalone legacy navigation68/0 exits0/11.83s. Exact unchanged d9fc85/abd86a worker379 and
runtime16/Arc4/metadata5/owned Git30+promisor60 qualifications are reused from TRAY, with final
package/hash correlation; no SET-04 worker rebuild/run is claimed. Mac119graph/spec140/204 pass.
Only recorded570836 was replaced, preserving nine0x80080 HWNDs and previous IDs/XY/compact/scopes/
preferences/accounts/distributions/original configuration/shortcut/full backup/defaults/startup,
singleton0 and old proxies0. Token-body tests use fake verification/writes; no real provider/vault
mutation, lifecycle action or desktop capture was used. At that checkpoint SET-02/08, updater install/notes, full summon,
native Mac/x64/live identity/phone/physical input/accessibility/display/shell/signing/clean-machine/
full migration gates remain open. See [ADR0040](adr/0040-windows-settings-sidebar-state-and-order.md).

Settings size qualified and active — 2026-10-02: Preview627264/package
3779f95e4665421bb0c218a54cea339e remembers width/height after a completed normal user resize,
retaining Windows resizable width/height,1020×720 defaults and880×440 minimum. Optional null size
stays omitted; supported logical work-area clamp changes the effective size without rewriting the
chosen size. Moves, initial/programmatic/page/search/sidebar layout and minimize/maximize do not
save. Current-owner/HWND/lifetime/generation/UI-thread checks reject stale receipts, including after
close starts while metadata Flush is held. Current-model persistence bypasses global actions and
keeps actual form/drafts/password/focus/error/CTS, retained owners, attention/Seen/queues/check time
and polling. Queued old metadata preserves the newest size. A separate localized banner reports
save failure and a later completed resize retries without clearing the form's row error.

Actual apphost Core4/full218, fullnative1515/0 observed exit0/232.51s, installer8/0 exit0/38.33s
with identical manifest,282 completed six-language synthetic views (30geometry) and read-only7local+
2remote exit0/45.58s pass. New23 are extracted from the final full run (`standaloneRun=false`),
distinct from historical standalone12a56923/0 exit0/31.75s. AppEC4C62/manifest95207F match final
execution/installer/renders. Unchanged d9fc85/abd86a worker379/runtime16/Arc4/metadata5/owned
Git30+promisor60 evidence is reused, not rerun. Mac119graph/spec140/204 pass. Only recorded601784
was replaced; all nine0x80080 HWNDs and old IDs/XY/compact/scopes/preferences/accounts/distros/
original configuration/shortcut/full backup/defaults/startup remain, absent geometry stays absent,
singleton0/old proxies0. Original reopen/closing reds and first-full/diagnostic failures remain
retained. The only diagnostic change was existing Arc raw null-links→accepted default links;
canonical links were supplied before initial fixture Save, preserving Arc/strict assertions.
Native pre-Store failure/exact owned file+backup proof is distinct from Core actual atomic failure.
Actual six-language footer bounds passed; its original layout is unchanged.

At this SET-02 checkpoint, ACC-03 was Partial for missing provider-token creation and empty-field
stored Verify, retaining qualified nonempty save/Return proofs; the later ACC-03 subset below
qualifies those local actions. ACC-09 Test
already reads the current browser/profile/endpoint draft at click; live launch/identity is still a
gate, with no newly qualified click claimed. SET-11 fresh/missing120 versus omitted legacy60 is
deliberate; repositories are per-account, and Mac's deck-wide/Actions-off-disabled watchlist stays
partial. Provider applicability work is not shipped/qualified by this geometry package. SET-02 OS
sidebar metrics, XY/display homes/DPI, SET-08, updater install/notes, full summon and native Mac/x64/
live identity/phone/physical input/accessibility/display/shell/signing/clean-machine/full migration
remain open. See [ADR0041](adr/0041-windows-settings-window-size-persistence.md).

Historical provider applicability checkpoint — 2026-10-02: Preview39204/package
99b3f7da4605432e9bba23fcf965ce5d separates GitLab instance/token help from GitHub scopes/failed-run fields.
Notifications renders GL failed-run as noninteractive not-applicable without erasing stored bits.
New-draft provider switching retains controls/drafts, and commit locks the provider/permanent ID.
GitLab request arrays are empty while saved inactive data stays exact, including duplicates/order/
null elements/raw over-limit entries. Unedited GH arrays still fail strict validation when invalid;
explicit edits use existing comma parsing, with captured revisions retaining later pending edits.
New GL commits empty scopes/false runs; actual Test reads current endpoint/browser/profile draft.

Actual Core4/full222, finalnative1541/0 exit0/170.35s, installer8/0 exit0/23.64s with unchanged
manifest/no restoration and read-only7local+2remote exit0/9.62s pass. Completed312 six-language synthetic views include30 provider scenes; App/manifest match the final package. Provider26
fake-body groups are included, distinct from historical standalone26/41.37s. Wire6 is null-token
admission without HTTP; d9fc85/abd86a worker379/runtime16/Arc4/metadata5/Git30+60 remain reused.
Only restored owner6168 was replaced by39204. All nine0x80080 HWNDs and prior card IDs/XY/compact/raw scopes/accounts/preferences/distributions/original configuration/shortcut/full backup/defaults/startup are preserved; absent size stays omitted, singleton0 and old worker proxies0. Mac119graph/spec140/204 remain intact. Historical failures are retained;
bounded fixture focus preparation did not relax assertions or change production behavior.
ACC-03 local token actions remained missing at this provider checkpoint and are qualified below.
Live provider/browser identity, SET-08, SET-11 deck-wide watchlist, display/summon/updater/native Mac/
x64/network/phone/accessibility/shell/signing/release/full migration remain open.
[ADR0042](adr/0042-windows-account-provider-applicability.md).

Historical ACC-03 qualified checkpoint — 2026-10-02: Preview68312/package04928307578842e6b1c3337fdf206cf0 added
current-provider token pages, a blank cancel-default Enterprise address dialog with exact API
context and separate/empty-input stored-token checks. Creation ignores unrelated incomplete
metadata without reading credentials. Stored checks preserve the password draft and metadata
errors, capture exact committed target/full route/owner epoch/replacement revision and submit
remote.verify once. Exact-route settingsChecks reuse and scoped autosave suspension isolate them
from card polling, attention and ordinary saves. Known presence updates only the current cache.

Actual Core focused4/full226, standalone token30/0 exit0/32.83s, fullnative1571/0 exit0/189.8s,
installer8/0 exit0/24.29s with identical manifest/no restoration, read-only7local+2remote exit0/
12.09s and342 six-language synthetic views including30 token scenes pass. Six new English/Russian
scenes were visually reviewed;342 generated scenes are not342 inspected bitmaps. Only39204 was
replaced by68312; all nine0x80080 HWNDs and prior IDs/XY/compact/raw accounts/scopes/preferences/
distributions/configuration/shortcut/full backup/defaults/startup are preserved, absent geometry
stays omitted, singleton0/old proxies0. Mac119/graph/spec140/204 pass. The unchanged d9fc85/abd86a
worker379/runtime16/Arc4/metadata5/Git30+60 baseline is reused, not a new worker qualification.

There are now at most five lazy ownership slots per distribution: local/shared remote/checkout/
settingsChecks local/settingsChecks remote. The prior four-channel receipts remain historical.
The30 token groups use fake credentials/browser/API bodies and an owned fake worker child, not
live provider permissions. Old nonempty-replacement maximum-ID namespace and slash-normalizing
metadata limitations remain. SET-08 was separate at that checkpoint; native Mac/x64/browser/phone/display/physical input/
accessibility/shell/signing/clean-machine/full migration gates stay open; releaseQualified=false.
See [ADR0043](adr/0043-windows-account-token-actions.md) and [qualification](windows-qualification.md).

SET-08 qualified and active — 2026-10-02: Preview78356/package9e1090ab67b94081853edfd12e72554e
shows immutable startup App/version/process/module facts. Missing values remain independent;
assembly fallback is labelled and never used by CheckNow. MVID identifies the loaded App module
only. No settings schema, worker operation, frozen Mac UI or package-trust classifier was added.

Actual Core focused4/full226, provenance16/0 exit0/11.30s, fullnative1587/0 exit0/208.14s,
installer8/0 exit0/24.08s and read-only7local+2remote exit0/11.88s pass. Completed372 six-language
synthetic views include30 provenance scenes; eight English/Russian frames were visually reviewed.
The final App/manifest correlate every packaged gate. A sample-only startup-fact correction was
caught before artwork generation; actual generic/geometry/empty-sidebar factories now use fake
facts and preserve state within the unchanged16 groups. Prior candidates remain historical.

Verified owner78356 preserves all nine0x80080 HWNDs and prior IDs/XY/compact/raw scopes/accounts/
preferences/distributions/configuration/shortcut/full backup/defaults/startup, with absent geometry
omitted and singleton0/old worker proxies0. Worker379/runtime16/Arc4/metadata5/Git30+60/null-wire6
are exact-hash reuse, not fresh SET-08 execution. Mac119/graph/spec140/204 source guards are distinct
from native Mac acceptance. Mac marketing/build-counter/translocation/update-install semantics,
native Mac/x64/live identities/browser/phone/display/summon/input/accessibility/shell/signing/
clean-machine/full migration gates remain open; releaseQualified=false.
See [ADR0044](adr/0044-windows-running-build-provenance.md) and [qualification](windows-qualification.md).
