# 0035 — Windows card visibility and retained owners

Date: 2026-10-02
Status: Accepted; qualified and active in Windows Preview413076

Every Windows settings save waited for the lifecycle action gate, reset all attention/notification
baselines and recreated every card. Hiding a saved legacy remote card could wait for an unrelated
project command; other windows lost identity and snapshots. Existing project forms also stored
Enabled in every metadata draft, so an old queued draft could show a card hidden afterward.

Use one SetCardVisibleAsync action by exact permanent project/remote ID. A built-in kind first
resolves its saved role or performs provider/setup discovery, then uses that ID; later canonical
and custom cards remain independent. Visibility persists only the selected Enabled value without
waiting for the lifecycle gate. Store failure retains old settings/presentation. Settings/tray/card
entrypoints share this operation, without global worker/session/attention resets.

Retain configured card owners while hidden: HWND, snapshot, running operation, in-flight transport,
expanded/full list and log state survive. Stop new polling and close the hidden card's transient
context/QR presentation. Summon, Tidy and display recovery skip hidden cards. Actual removal and
shutdown dispose owners. Ordinary settings reconciliation retains unchanged cached owners; a
changed card configuration may recreate that selected owner once the action gate permits it.
The no-fetch contract concerns new card polling: an already started operation/read and an explicitly
open ordinary log window keep their lifetime; hiding a card never silently cancels that work.

Both card menus repopulate on opening from current state. They expose exact-ID Hide/context Settings,
compact, live lock, Tidy and refresh of all active cards through existing local/remote busy and
coalescing guards. Project show/hide-log follows the actual ordinary log window and is disabled in
compact mode; folder/terminal/QR retain their existing local/busy eligibility. Inbox has explicit
read-rest and read-all rows, with failure-free displayed per-account cutoffs and mutation guards.
Read-all captures those cutoffs before an awaited operation, never the click time. This pair is a
Windows adaptation of the Mac Option alternate; attention-menu modifier actions remain separate.

Existing project shown-checkbox Click commits visibility immediately, independently of metadata
validation/autosave. Every existing metadata replacement reads committed current Enabled at commit,
including a draft captured before waiting for an action. New-project Add keeps its explicit draft
Enabled. SettingsWindow.ReconcileCardVisibility reads current settings and updates only matching
project/built-in/custom controls and the saved visibility baseline. It does not reload navigation,
rebuild the page, flush metadata or alter text/token drafts, focus, cursor, errors or dirty state.

Protocol1 gains an optional bounded activeProjectIDs request context and an advertised capability.
Omitted context keeps legacy behavior; empty context excludes local/Docker events. Validate context
before filesystem/runner work. Original project/Docker attention builders consume only the active
set, while watch/status/settler/job history remains intact. Native requests capture the distribution
visibility revision; a late old revision may still settle status/progress/errors but must not restore
obsolete attention. Exact scope/item pruning preserves sibling local events and remote baselines,
queued notification identities and Seen/check time. The first current observation after reveal seeds
that card's old alerts quietly while new sibling alerts can still deliver.

The native production red windows-visibility-red-ui.json proves the old legacy hide blocks on an
unrelated action gate. Source settings fixtures cover invalid drafts/cursor/error preservation,
captured queued metadata, immediate existing checkbox actions, first-role legacy/later canonical/
custom IDs, hidden new-project Add and unrelated ID isolation in all six languages. They use owned
temporary settings and live:false controllers with live:true metadata forms; WSL discovery and
health readers are disabled/injected, and no worker, browser or vault operation is performed.
Final warning-free ARM64 qualification passes Core122/0, portable worker328/0, native1165/0 and
installer8/0. Fresh read-only seven-local/two-remote/tray10s checks confirm three independent
transports and two original Arc summaries. The new qualified worker also passes freshly rerun generic
runtime16/0, Arc4/0 and DDEV metadata5/0. Sixty synthetic views cover tray/browser and six-language
idle/compact/busy card contexts. Mac119/product graph, spec140/204 and whitespace pass. Only owned
Preview408076 was replaced by413076/package9b16d53b1d9d46fca8bca9fcacca4ad4.
windows-visibility-preview-checks.json proves original configuration/shortcut/full backup, all
nine0x80080 windows and existing IDs/settings/positions/compact/scopes/preferences/distributions/
defaults/startup preserved, singleton0 and old proxies0.

Frozen original Mac sources/resources/product graph remain unchanged; additive worker context is
outside that graph. No real account/token/project lifecycle/browser/notification/network policy
operation is used for synthetic qualification. WIF, SET-04,
TRAY-06 main-tray dashboard/global refresh/arrangements/all-DDEV poweroff, TRAY-07 attention modifier
twins, native Mac/x64/live identities/phone/display/shell/signing and complete migration
gates remain open.
