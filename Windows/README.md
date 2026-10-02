# Windows host — implementation in progress

The [Mac functional specification](../docs/macos-functional-spec.md) is the migration acceptance
inventory: 140 source-referenced behaviors with defaults, Windows mappings and complete user-flow
checks. Earlier parity summaries cover completed subsets; they do not certify complete parity.
The notification-area icon now carries the original DD panel-stack shape in every state, using
an ink ring for stuck work, an ink dot for needs fixing and a red dot only for waiting on you.
It follows the system taskbar theme/DPI and retains its current state when Explorer recreates the
notification area. High-contrast and actual Explorer/display recovery still require live acceptance.

The application is a native Windows executable. It starts its Swift workers in WSL2 itself.
Users do not launch a Linux desktop UI. macOS keeps the existing AppKit/SwiftUI application.

Current implementation: local DDEV/Arc cards, per-project distro/path, read-only discovery/status,
start/stop/restart with verified outcomes, cancellation/progress, generic project commands,
logs, tray, Ctrl+Alt+Space summon with tray fallback, desktop/floating modes, lock/arrange/drag
positions, Explorer/Windows Terminal links, distro discovery, DDEV import and Arc folder addition.
Project settings can be edited while keeping stable IDs, placement, visibility and saved arrangements.
Settings now use a searchable sidebar with General, Deck, Cards and Notifications pages, followed by
accounts and projects. Card settings open their matching form. Existing project/account metadata
autosaves after a short pause; adding a project or verifying/replacing a token remains explicit.
Accounts form one naturally sorted group across GitHub/GitLab, and projects one across Arc/DDEV/plain
projects. Equivalent titles retain saved ties; opening settings never rewrites deck order. A green
dot means the current retained local owner reports running; amber means working, a pending command/
group operation or plain-project starting. Hidden cards keep accepted state without sidebar polling.
Disabled rows remain selectable/removable: icon and unselected title dim, selected title stays white,
and the seven-DIP activity dot stays undimmed. Full localized tooltips and accessible names describe
the entry and whether it is on the deck.

Account token availability means a stored bounded value, including a legacy zero-byte credential,
rather than authenticated provider permission. The window caches only a boolean by the exact
provider/account/endpoint target. A newly created settings window, explicit committed token save or
first committed uncached account target may read metadata. Showing a retained window, project
callbacks, search, ordinary metadata edits and row updates use the cache. The helper never decodes
token bytes or marshals string/blob pointees and frees its native allocation once. Missing/unreadable/
invalid metadata is unavailable. A current-target commit updates availability before former-target
cleanup, so a cleanup error cannot falsely describe the committed new target.

The settings/browser batch is qualified and active in the running Preview. Ctrl+F focuses search; Up/Down navigate sidebar
items, and Delete/Backspace there uses the same removal confirmation as the form button.
Cancel receives initial focus and Return/Escape cancel. Removing a project changes its card
configuration without stopping services or deleting its checkout; account removal detaches its
scopes and deletes only that account's credential. Return in the token field invokes explicit
verification/save, never metadata autosave. Quiet metadata saves keep fields editable and do not
replace a health answer with a generic Saved message. Invalid metadata stays editable and prevents
leaving or closing its form until corrected; concurrent flushes wait for the latest edit.
Arc/plain forms show a dedicated health row on arrival and after relevant folder, distribution,
command or health-address edits. Results retain the original shared summary, including refusal
and ownership detail. Identity/generation/lifetime checks discard delayed replies for a changed
form; DDEV has no extra health row. Optional protocol1 checkSummary/checkedAt preserve old payloads.
Settings use the read-only `project.check` operation instead of registering the draft as a live card.
Its separate worker transport prevents canceled checks from interrupting card polling or project
commands. Fresh DDEV URLs for browser Test use this same isolated path. Card polling/actions keep
their existing `project.status` observations.
The shared browser picker discovers installed Edge, Chrome, Firefox, Brave, Vivaldi and Chromium
through read-only registrations and known paths. Chromium profiles come from bounded Local State
name metadata, with Default followed by natural directory order; the picker hides when no profiles
can be offered. Saved absent browser/profile choices remain visible and unchanged. Old Firefox
profiles remain stored but are ignored when opening links. Every opening path tries the chosen
browser and falls back to the system default if it is missing or cannot start. Browser/profile
qualification uses offline fixtures, never launches actual browsers or changes real defaults.
Core96/0, portable worker317/0, native UI1034/0 and installer8/0 pass. Read-only integration covers
seven local and two remote cards plus fresh summaries on two Arc projects; both distribution
runtimes, five DDEV metadata values and the updated Preview's nine windows/settings are preserved.
Live browser identities, real account/token flows and full native
Mac/x64/external release gates remain open. See [ADR0032](../docs/adr/0032-windows-settings-checks-and-browser-choice.md).
The Mac screenshot reference guides neutral translucent cards, original brand marks, separate branch
and status lines, quiet timestamps and a single row of primary actions. Collapsed cards keep their
name and primary icons; right-click offers folder, logs, phone QR, refresh and contextual settings.
Project settings use a header visibility switch and grouped horizontal rows. Mailpit/xhgui or
PageBuilder/Composer switches control the shared resolved links; TEST/UAT/PROD rows retain disabled
addresses. The folder picker accepts only the selected WSL distribution's UNC checkout.
Tools/environment links and project browser profiles are configurable; repository, Mailpit and xhgui
links come from the shared integrations. Remote cards can expand to twelve rows; their full-list window
is reused and refreshed. Remote refresh choices are 1/2/5/10 minutes, respecting the inbox server minimum.

Windows DDEV cards now show the configured PHP and database versions beside the framework and
checkout name, including stopped/paused projects. Versions come from the existing shared parser
through the production worker. Mailpit/xhgui use the reported URLs and saved tool switches; new
projects default xhgui off. Local cards share a ten-second poll and one DDEV inventory per cycle;
GitHub/GitLab requests use an independent worker connection. [Metadata contract](../docs/adr/0027-ddev-worker-metadata.md).
Logs have one window per project with up to 400 newest lines, a two-second refresh while visible,
Follow, case-insensitive search, source, full-file opening in Notepad when a file exists, and terminal
following for DDEV/Fusion/local files. Closing, hiding or minimizing a log stops automatic reads;
an explicitly open log remains independent when its card is hidden. User window moves/resizes preserve its geometry. The ordinary terminal
button opens the correct WSL checkout in Windows Terminal with a WSL fallback. Both paths use a stable
Windows working directory; Terminal receives an explicit tab starting directory before WSL enters the
project. This avoids inherited Preview package directories and error 0x8007010b after package changes.

Running loopback HTTP(S) sites, or a site already using this PC's physical LAN IPv4 address, can
show a phone QR popup. The running card's QR button and context menu explain missing addresses,
Wi-Fi or routed hostnames instead of leaving an inactive item. Stopped/working cards hide the icon;
the stopped card's menu explains that it must run, and working cards disable QR during the command.
Compact cards retain QR in the context menu. Copy closes the popup; a new snapshot updates an open
code, and a failed status read closes it and prevents reopening a stale code.
Project settings include an optional **Phone address**: enter a direct HTTP address or a domain
already reachable from the phone. An empty field retains automatic localhost rewriting; the chosen
phone address does not replace the project's readiness or browser URL. Tool/site groups wrap when they fit.
The phone and PC must share a network and the server must accept LAN connections. Encoding is tested
with an independent decoder; actual phone access depends on WSL networking and Windows firewall.
DDEV host-routing domains are not rewritten to an IP address. A normal `*.ddev.site` address on the
phone refers to the phone itself; a direct port bound only to `127.0.0.1` also cannot accept LAN traffic.
For an explicitly configured direct HTTP port or LAN domain, follow the
[DDEV sharing documentation](https://docs.ddev.com/en/stable/users/topics/sharing/) and put the
reachable address in **Phone address**. DevDeck changes no firewall, DNS, DDEV or WSL network rules
automatically. [Feature parity](../docs/windows-feature-parity.md) records remaining gaps.
Settings can open Docker Desktop explicitly and enable a per-configuration Windows startup shortcut.
Cards can collapse; a second launch summons the existing deck. Initial off-screen recovery handles
removed monitors, with expanded DPI/virtual-desktop checks still pending.
Local and remote widgets stay out of Alt+Tab and the taskbar in both desktop and floating modes.
Git branch labels use a small, clear fork glyph aligned with the name.
Settings, accounts, logs and expanded lists remain ordinary windows. Cards share a compact dark
surface, muted state colours and state-dependent primary actions. Refresh/settings live in the header;
terminal/log icons keep translated tooltips and accessible names. Double-click the title to collapse.
The visible header chevron or card context menu collapses/expands a card. Project settings and remote
card advanced options also expose Compact card; the preference survives restarts and arrangements.
Arrange in columns uses actual visible-card heights with 12-DIP vertical/horizontal gaps. Compact
cards take only their measured height; hidden cards keep their saved positions. Columns wrap at the
anchor monitor's work-area edge and grow toward available space. Tidy retains the deck anchor/order
and moves existing windows without resetting snapshots, lists, operations or polling. Automatic packing
is not enabled; changing a card's height can be followed by another explicit arrange action.
Natural catalog ordering is qualified and active in the Preview. Tray projects and explicit Tidy share Arc/DDEV/plain kind order and
culture-aware titles, placing site2 before site10. Built-in remote roles retain their first saved
card, including legacy IDs; extra remote cards follow by title. Presentation sorting does not
rewrite saved arrays, scopes, IDs, compact/visibility flags or hidden placements, and no cards are
automatically rearranged during an upgrade. Tidy keeps the existing live windows and measured gaps.
Core104/0, native UI1041/0, installer8/0 and read-only seven-local/two-remote/runtime/metadata checks
pass. The unchanged worker317 archive retains its prior qualification. The updated Preview keeps
all nine windows and the original configuration/IDs/positions/compact/scopes/defaults/startup;
the separate settings-sidebar/live-dot requirement remains partial. See
[ADR0033](../docs/adr/0033-windows-catalog-and-tidy-order.md).
While a project action runs, Cancel replaces the idle lifecycle controls; local-site links are disabled
until the project is running again. Folder, terminal and logs remain available.
Compact cancellation retains the normal 30-by-32-DIP icon dimensions during start, stop and restart.
Expanding or collapsing during a command keeps cancellation available and preserves its progress;
idle lifecycle controls return when the final project snapshot arrives.
Arc forms expose organization/site, local URL and health path (default `/release`), plus start/stop
commands. Empty local URL uses the checkout's `.env`; path/query remain specific to the site, while
health and local PageBuilder use the server origin. Without a folder, Arc keeps hosted links usable
and disables local actions without worker polling; adding a folder preserves its ID and placement.
The link editor has enabled/template/type rows, fixed builtin labels and custom add/rename/remove.
Arc substitutes `{org}` and site ID `{site}`; DDEV substitutes its primary URL for `{site}`.
Tool/site groups stay distinct, and external destinations remain enabled while local services stop.
Old literal links and disabled addresses survive; only exact superseded Arc templates are corrected.
See [ADR 0029](../docs/adr/0029-arc-options-and-project-link-templates.md).

Plain projects offer Detect beside the start command and when choosing a new checkout. The shared
Mac ProjectProbe reads Compose, package scripts/workspaces, Make and environment ports without
running commands or network checks. Detection replaces command/mode/Docker choices, fills empty
caption/health fields and preserves the name, opening URL and card identity. Results for a folder
changed during detection are ignored. Caption is under Advanced; Check URL and Open URL remain
separate, with blank Open URL falling back to Check URL. Template links use the opening address.
Cards show caption/checkout beside the command and select the original framework/runtime marks.
See [ADR 0030](../docs/adr/0030-shared-project-detection-and-separate-open-url.md).
Actions are serialized across distro workers; Fusion checks Docker port ownership before start.
Cancellation stops the CLI session, then refreshes state; it does not roll back containers already
created by Docker. The qualified all-DDEV poweroff batch is described below and active in
Preview484424. No Fusion teardown operation is exposed.

Remote cards reuse Swift GitHub/GitLab services for PRs, notifications, Actions and merge requests.
After verified account setup, GitHub Pull requests and Inbox appear automatically and aggregate all
GitHub accounts; Actions starts hidden. GitLab setup shows Merge requests. The tray's Cards section
and Settings/Cards always list the four types. Click a checked row to hide it or an unchecked row to
show it. Without an enabled matching account, enabling opens the matching account setup page.
The tray groups local-project visibility by Arc/DDEV/Projects. Settings account expanders let you
keep automatic inclusion of new accounts or choose a custom scope and WSL distribution. Existing
account-only configurations gain defaults on startup; explicit hidden states, legacy IDs, custom
scopes and positions remain intact. Hidden cards stop polling. Work in
flight remains visibly disabled while its Windows implementation is pending.
Removing an account detaches its card references without losing identities/positions. Automatic scopes
create no window or fetch while no enabled account exists and resume after setup; empty manual scopes disable.
Account metadata stays in Windows settings; tokens stay in Windows Credential Manager. New tokens
are verified before saving and supplied only through the inherited worker stdin pipe. Links support
per-account browser profiles. Attention uses shared rules, deduplicates PR/inbox reviews and stays
quiet on first observation. Notifications are opt-in. Inbox supports individual mark-read and bounded
mark-rest; reviews, mentions, assignments and security notifications remain unread in mark-rest.
Qualified and active in the Preview: tray attention now has native two-line rows with
visible account/subtitle text, age badges and the original brand marks. Urgent tiers show three rows,
informational items two; a single leftover remains direct, and larger sections offer a same-tier
submenu whose rows retain the original targets and availability guards. Long subtitles are trimmed
by text elements, with complete tooltip/accessibility text. Status-only rows stay disabled, including
an enabled producer item whose action is `none`. The empty digest shows a local HH:mm check time
from the last validated worker attention observation received by the Windows host; event ages and
settings draft checks do not supply that time. Before an observation it uses the current-time fallback.
The old five-row and actual menu-width reds are retained; explicit menu/row sizing and bounded
Unicode title prefixes keep native columns and painted content within the client, including larger
fonts. Core112/0, native1103/0, installer8/0 and fresh read-only seven-local/two-remote checks pass.
Twenty-four synthetic views qualify main/overflow/calm/browser presentation, with inline ages,
subtitles and browser profile/right controls visible. The worker317/runtime16/Arc4/metadata5
baseline was retained with a byte-identical archive, not rerun, for this batch. Preview408076
preserved all nine0x80080 windows and prior settings/defaults/startup; it is superseded by the
visibility/context update below. Tray global actions and attention modifier alternates remain
separate TRAY-06/07 gaps;
see [ADR0034](../docs/adr/0034-windows-tray-attention-presentation.md).
Qualified and retained in Preview484424: Hide from card,
tray or settings targets one permanent ID, retaining that hidden card's owner, snapshot, running
operation and native identity. Other cards, expanded lists, logs and notification baselines remain
intact; summon/Tidy/display recovery respect visibility. Existing project visibility is an immediate
separate action: an invalid metadata draft stays editable, and an already captured autosave preserves
the current committed visibility. Open settings update only the relevant checkbox and baseline.
Local requests include an optional bounded activeProjectIDs context; omitted retains legacy behavior,
empty excludes local/Docker attention, and a changed visibility revision suppresses obsolete attention
without discarding operation/status/progress. Hidden-source notifications are pruned precisely, and
revealed old events seed quietly while new sibling events remain deliverable. A hidden card starts no
new card polling; an already started operation/read and an independently open log window retain their
lifetime. Current card context menus include live lock checkmarks, Tidy, refresh of all active cards,
and project show/hide-log state (disabled in compact mode). Inbox context offers explicit read-rest
and read-all rows, disabled while mutating or without a failure-free displayed cutoff; read-all uses
that cutoff for each owning account. These explicit rows adapt the Mac's Option alternate.
Core122/0, portable worker328/0, native1165/0 and installer8/0 pass with a warning-free ARM64
package. Fresh read-only seven-local/two-remote checks, independent transports, generic runtime16,
Arc4, DDEV metadata5 and sixty synthetic views pass; Mac119/product graph and spec140/204 remain
unchanged. Only owned Preview408076 was replaced by413076/package9b16d53b1d9d46fca8bca9fcacca4ad4,
preserving original configuration/shortcut/full backup, all nine0x80080 windows, IDs, placements,
compact flags, scopes, preferences, distributions, defaults and startup; singleton0 and old proxies0.
All-DDEV poweroff qualification follows below; attention modifier twins remain open;
see [ADR0035](../docs/adr/0035-windows-card-visibility-and-retained-owners.md).
Qualified and retained in Preview484424: the main tray now offers Open pull requests at
the original fixed `https://github.com/pulls`, using the first enabled GitHub account in saved order
for browser/profile, or system default when none exists. It does not depend on a visible PR card,
token or account API endpoint. Refresh uses the existing shared local cycle and independent remote
paths for active eligible cards; hidden/hosted/busy cards are skipped and pending reads are coalesced.
It never cancels an operation to refresh.
The Arrangements submenu saves all configured permanent IDs with chosen Enabled/compact flags and
saved XY. Matching the full current set drives fresh checkmarks, independent of saved array order;
dragging or changing a flag removes a match. Names are trimmed; a case-insensitive overwrite retains
the original spelling and menu position. Explicit new saves keep the newest eight, while loading or
overwriting a longer legacy list leaves it intact. Apply uses scoped visibility, compact, then XY
for still-configured IDs; missing/stale names are a no-op and new/unrelated cards remain unchanged.
A busy remote collapse can remain partial without cancelling its work: geometry still applies,
its current compact choice stays honest, and retrying after the mutation finishes completes the match.
Save/Forget alter only arrangements; Deck floating/lock use the existing precise setters. Neither
path waits for the lifecycle gate or resets attention, check time, Seen, queues or card owners.
Open settings reconcile only the relevant choices/switches, retaining drafts, focus and errors.
The localized tray name prompt accepts valid Save/Return and Cancel/Escape, rejects blank/control/
overlong names, and shares the exact rounded settings styles without constructing another settings
window. Explicit named Forget is reachable in a Remove submenu and on the Deck page; this is the
Windows adaptation of Mac's Option action. Attention modifier twins remain a separate requirement.
Core132/0, native1261/0 and installer8/0 pass with a warning-free ARM64 package; unchanged
worker328/b5c1 qualification is explicitly reused, not rerun. Fresh read-only7+2, runtime16/Arc4/
metadata5 and84 synthetic views pass; Mac119/product graph/spec140/204 and whitespace remain clean.
Only owned Preview413076 was replaced by437068/package db0486ac622a43e083fbda7abbd848fb.
windows-commands-preview-checks.json proves all nine0x80080 windows and previous IDs/settings/
positions/compact/scopes/preferences/distributions/defaults/startup/original configuration/shortcut/
full backup preserved, singleton0 and old proxies0. Later poweroff/WIF qualifications are recorded
below; TRAY-07 and full native/live/external release gates remain open. See
[ADR0036](../docs/adr/0036-windows-tray-deck-commands-and-arrangements.md).

All-DDEV poweroff is qualified and active in Preview484424. The tray action covers
every configured DDEV-bearing distribution, including hidden cards. The product prompt freezes and
lists those distribution names; it explains the Docker-wide scope, including off-deck projects,
other WSL distributions, the router and SSH agent. A WSL route is not a Docker isolation boundary.
The default/focused Cancel, Enter, Escape and window close decline; only an explicit Power off click
accepts. The tool window inherits its owner's topmost state and shared rounded settings styles.
It does not stop Docker Desktop or WSL itself.

Protocol1 adds a bounded typed powerOff context/result and the ddev.poweroff.transaction capability.
All captured polling actors must support it and acknowledge prepare before any shared
DDEVEnvironment.powerOff command runs. Commands run serially once per unique confirmed DDEV-bearing
distribution; every actor renews its monotonic 600-second lease before each run. Native retains the
captured worker identity/plan/token, never reconnects or retries a lost run, and finalizes all staged
actors after any attempted command. A never-run abort restores the original watch/settler and card
presentation without manufacturing a check or stopped state. Observation epochs fence pending polls,
and inventory invalidation leaves existing consumers uncancelled. Reconciliation uses one fresh
inventory per actor, returns exact prepared IDs in order and separates command/inventory diagnostics
from physical statuses; an unknown result cannot be presented as stopped.

Native group busy is separate from per-card cancellation. The same visible/hidden owners, native
handles, compact preference, positions, logs and actual per-card CTS survive; lifecycle/QR/refresh
controls stay gated and compact Stop never expands. Token/generation guards discard stale reads and
progress. Physical status plus a failure keeps its metadata and diagnostic; a missing physical result
shows unavailable. Settings, attention baselines and queued alerts are not globally reset.
Core149/0, final worker345/0, native1328/0, installer8/0 and102 synthetic views pass against the final
warning-free ARM64 package. Fresh read-only7+2 negotiates capability hello on the one configured
DDEV-bearing distribution and records lifecycleInvoked=false. Runtime16 in Ubuntu/Debian, Arc4,
DDEV metadata5, Mac119/product graph/spec140/204 and whitespace pass. Poweroff lifecycle checks use
fake CLI runners only. Only owned Preview437068 was replaced by446868/package
bf3c10f14d724c7b90bcbfe51df429aa with the qualifieda9 archive/1203 binary.
windows-poweroff-preview-checks.json proves all nine0x80080 HWNDs, prior IDs/settings/positions/
compact/scopes/preferences/distributions/defaults/startup/original configuration/shortcut/full
backup preserved, singleton0 and old proxies0.
SET-04/TRAY-07 remained open at that poweroff checkpoint; later subsets follow. Native Mac/x64/live
identities/phone/display/shell/signing/full migration gates remain open.
See [ADR0037](../docs/adr/0037-windows-ddev-poweroff-transaction.md).

### Work in flight — qualified and active

Preview484424 includes the default-off, token-free `local.workInFlight` card. Tray and Cards
settings use the same exact-ID visibility transition. A missing preference remains omitted from
old settings; explicit hide retains the owner/cache/placement/compact setting and contributes no
attention. The card watches all configured local Arc/DDEV/plain folders, including hidden source
cards, deduplicated by distribution plus lexically standardized path. Hosted Arc entries with no
folder are omitted. A 1024-checkout limit produces a diagnostic and keeps the previous cache.

An isolated checkout transport reads one typed snapshot at a time per distribution, using the
existing shared Git parser and attention builder. Fixed status and urgent-only log commands have
20-second limits; the native RPC deadline is75 seconds. The fixed child prefix is
`env GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 GIT_ALLOW_PROTOCOL= `: optional-lock/lazy-fetch
suppression plus an explicit empty Git transport allowlist. It changes neither parent environment
nor repository/global config. No runtime/Docker/provider/watch mutation belongs to this route.
The portable aged-commit builder exposed a Linux Foundation plural-resource crash. A worker-only
startup bundle uses numeric fallback forms without changing Mac resources or swapping language per
request. Fallback uses each original numeric `other` form, without loading stringsdict. Windows reconstructs the displayed title/subtitle with its six-language plural adapter
from validated commit/age/branch facts; this is not a claim of identical Linux plural grammar.
Native rows show the branch and first two localized facts, urgency, in-flight/unpushed counts and
successful watched count. Three rows expand to at most twelve; compact height remains bounded to
76 DIP. Checking keeps the previous full-pass timestamp; partial/all-failed/stale states are explicit.
The whole row opens the exact current checkout in its configured distribution, including hidden
project sources. Removed/moved/foreign targets do nothing. There are no project/log/QR/account tools.

A retained controller loop sequences PR→Inbox→GitLab MR→Actions, custom extras, open logs and
checkouts with the original shared delay/backoff/server-hint policy. Per-remote-card periodic timers
are removed. Hidden/closed/busy cards are skipped before admission; pending
reads coalesce, and hiding a started checkout read does not cancel its token or replace the HWND.
The old omitted refresh preference stays60 seconds; newly created empty settings explicitly use120.

Final qualification passes Core183/0 (170 existing/WIF plus13 atomic-recovery checks), portable
worker367/0, native1396/0 with observed exit0, installer8/0 and192 synthetic views (102 prior+90 WIF,
six languages). The first180-second native helper timeout is retained; the same immutable candidate
completed exit0 in180.05 seconds on the bounded rerun without assertion/source changes. Fresh
read-only7local+2remote verifies separate checkout/settings/local/remote channels, shared cadence,
poweroff and checkout capability hello, lifecycleInvoked=false and no Git when WIF is default-off.
Runtime16 in Ubuntu/Debian, Arc4/editor origins, DDEV metadata5 and Mac119/product graph/spec140/204
pass. The final worker archive is0ea97b0c42d30ac56253711c7722d7150cbadb4efb08dc2f019d18cfedcc882b;
binary7f57a8775fcbde20c2ae66f4c986aca54709bf4056082fede1a1d27296a7b200.

Owned ordinary Git30 and promisor60 checks pass against that final worker in both distributions.
They verify branch/dirty/local-commit/age/typed targets, unchanged HEAD/refs/config/index bytes+mtime,
ordinary status positive controls and missing-tree/missing-parent typed outcomes with no worker
transport-helper invocation. Explicit allowlist denial has independent positive controls. These
owned disposable fixtures establish the installed paths, not arbitrary repository-configured
programs, all object/transport layouts or untested Git packages. No user checkout, real terminal,
provider mutation or project lifecycle command was used for qualification.

Only recorded446868 was replaced by484424/package02ea3db442754597aaeccb7315e1876d.
windows-wif-preview-checks.json proves all nine0x80080 HWNDs, preexisting IDs/positions/compact/scopes/
preferences/distributions/defaults/startup/original configuration/shortcut/full backup, singleton0
and old worker proxies0. The WIF preference remains default-off; no extra widget is forced on.
At this WIF checkpoint, SET-04 still used saved sidebar order without runtime dots/disabled dimming
and attention alternatives/Inbox read were absent. The later TRAY-07 subset is recorded below;
SET-04 remained open at that WIF checkpoint; its later subset is recorded below. Native Mac/x64/live
identities/phone/display/shell/signing/full migration gates remain open.
See [ADR0038](../docs/adr/0038-windows-work-in-flight.md).

### Attention alternates — qualified supported subset

Preview570836/package2cc50416402c48b9bab4ac6624d88107 includes scoped Alt alternates in the main
and overflow tray menus and explicit named buttons in the full attention list. An enabled primary
opens its promised browser/profile, account settings, configured project/log, Docker or checkout
terminal. Alt selects exact personal Inbox Mark read before permitted project Dismiss; pressing the
modifier alone executes nothing. Primary `none` remains inert, but a URL-less notification can offer
Mark read. A hidden configured project/log target reveals the same retained owner and opens one log;
removed IDs create no configuration.

The optional protocol1 read target binds card/account/API endpoint/thread. Before credentials and
after awaited admission, the current enabled owner/provider/origin/scope and exact unread personal
row must still match. Optimistic projection removes only its account/thread, retains raw authorization
state and masks older pending polls, without falsifying successful-check time or resetting siblings.
Hidden started work retains its actual CTS/HWND and completes without new hidden refresh or reveal.
Closing/removing cancels owned lifetime. Errors stay visible, fresh state can restore unread rows,
and lost writes are not replayed. Broad Inbox row/read-rest/read-all operations are unchanged.
Project Dismiss rechecks the current full project reference except display title after acquisition;
stale admission returns false and does not retire the full-list row.

The menu adapter observes only its current owned chain, captures the shown choice before native
auto-close for synchronous Click, and removes filters/hooks on close/dispose. A visible controller
rebuild closes the root before disposing children. Actual queued keyboard/mouse fixtures include
rebuilt overflow and exact delivery to an independent owned STA message-only queue. They do not
qualify physical Alt/AltGr/IME/screen readers, OS-global input or isolation from WinForms' intentional
same-thread modal key retargeting. The explicit full-list action does not require a modifier.

Final Core202/0, worker379/0, native1468/0 observed exit0/181.91s, installer8/0 exit0/36.08s,
228 synthetic views (192prior+36 new, six languages), read-only7local+2remote exit0/33.25s,
runtime16/Arc4/metadata5 and Mac119/product graph/spec140/204 pass. The72 new cases are included
in the final full run (`standaloneRun=false`); the separate72 run on earlier98d7 is historical.
Installed remote hello advertises `attention.inboxReadTarget`, with no Inbox write, lifecycle or
default-off Git invocation. Strict UTF-8 helper readers resolve a retained IBM437 fixture-decoding
failure; production JSON/global codepages are unchanged. Exact d9fc85 archive/abd86a binary owned
Git30/promisor60 checks pass in Ubuntu/Debian without extending arbitrary repository guarantees.

Only recorded484424 was replaced. All nine0x80080 windows, prior IDs/XY/compact/scopes/preferences/
accounts/distributions, original configuration/shortcut/full backup/defaults/startup, singleton0
and old worker proxies0 are preserved. Earlier failed artifacts, the visible-rebuild/held-hide reds
and98d7's qualified product but failed incomplete render matrix remain retained; it was not activated.
TRAY-07 remains partial for native updater installation/available-update notes. SET-04 was open at
that TRAY checkpoint. Full summon behavior and native Mac/x64/live identity/physical input/
accessibility/phone/display/shell/signing/
clean-machine/full migration gates remain open. See [ADR0039](../docs/adr/0039-windows-attention-alternates-and-inbox-read.md).

### Retained settings sidebar — qualified and active

At the SET-04 checkpoint, Preview601784/package9563ba2b2a4242fa9a58c76f8b166764 qualified.
Current-owner publication rejects closed/replaced/removed IDs and stale physical generations,
then updates retained rows. Replacement clears a former running dot even when a new hidden/hosted
owner has no receipt. Window titles use the full selected entry even when search hides its row.
Becoming visible reconciles cached presentation without reseeding credentials or replacing/flushing
the active form. Sidebar updates preserve invalid drafts/passwords/errors/debounce/CTS, focus/caret,
query/selection/scroll and attention/Seen/successful-check time.

Final Core214/0 (12new), native1492/0 observed exit0/296.17s, installer8/0 exit0/118.88s with
identical manifest,252 six-language synthetic views (24sidebar) and read-only7local+2remote exit0/
32.34s pass. The24 new cases are extracted from the final full1492 run (`standaloneRun=false`);
the separate24-case component4988 is historical. Final standalone legacy navigation68/0 exits0/
11.83s. Worker379 and runtime16/Arc4/metadata5/owned Git30+promisor60 are reused from the exact
unchanged d9fc85 archive/abd86a binary qualified in TRAY, with final package/hash correlation;
SET-04 adds no worker RPC/capability/timer. Mac119/product graph/spec140/204 stay intact.
Only recorded570836 was replaced; all nine0x80080 widgets and previous IDs/XY/compact/scopes/
preferences/accounts/distributions/original configuration/shortcut/full backup/defaults/startup
remain preserved, singleton0 and old proxies0.

The genuine c5 cached-opening failure, e61 initial focus-premise failure and eced stale navigation
expectation remain preserved with their packages/reports. Actual token-body tests use owned fake
verification/writes. No real credential/provider mutation, lifecycle action or desktop capture was
used. Owned WPF/synthetic geometry does not establish physical input/screen-reader/native Mac,
exact Apple/Windows collation, x64/display/shell/phone/signing/clean-machine acceptance. TRAY-07
updater install/notes, SET-02/08, full summon and full migration remained open at that checkpoint.
See [ADR0040](../docs/adr/0040-windows-settings-sidebar-state-and-order.md).

Settings width and height are now remembered after a completed normal user resize. Windows retains
resizable width/height,1020×720-DIP defaults and880×440 minimum, adapting Mac's fixed-width window.
The optional `settingsWindow` record stores width/height only; null remains omitted until an admitted
resize. Finite new sizes are bounded to880…10000 by440…10000 DIP. Malformed syntactically valid
optional stored geometry falls back to null without discarding otherwise valid settings. Opening
can clamp the effective size only when both finite logical work dimensions meet880×440; the chosen
size is retained. The existing supported-area MaxHeight policy stays, with no new MaxWidth.

The current visible normal HWND admits a changed size after its owned WM_ENTERSIZEMOVE/
WM_EXITSIZEMOVE completion, revalidating lifetime/generation/Dispatcher/current owner and layout.
Initial/programmatic/page/search/sidebar layout, moving alone and minimize/maximize do not save.
The precise write saves the latest accepted model before assignment, bypasses project actions and
preserves owners, polling, attention/Seen/queues/check time and actual forms/drafts/passwords/focus/
errors/pending health-check ownership. Older queued metadata cannot overwrite a newer size.
Save failure shows a separate localized nonmodal banner; a later completed resize retries and clears
only that banner. Both Closing and CloseSettingsAsync invalidate pending receipts before metadata
Flush; a refused invalid-draft close still permits future user resizing. No coordinates or monitor
homes are added. Existing load-time Arc null-link/default migration may persist with the current
model; this path does not promise byte-identical raw legacy JSON spelling/unknown fields.

This subset is qualified and active in Preview627264/package3779f95e4665421bb0c218a54cea339e.
Actual apphost Core4/full218, fullnative1515/0 observed exit0/232.51s, installer8/0 exit0/38.33s
with identical manifest,282 completed six-language synthetic views (30geometry) and read-only7local+
2remote exit0/45.58s pass. The23 new cases are extracted from the final full run
(`standaloneRun=false`); historical component12a569 passed standalone23/0 in31.75s. The unchanged
d9fc85/abd86a TRAY worker379/runtime16/Arc4/metadata5/owned Git30+promisor60 baseline is reused,
not rerun. AppEC4C62/manifest95207F match execution, installer and completed renders. Mac119/product
graph/spec140/204 pass. Only recorded601784 was replaced, preserving all nine0x80080 HWNDs, prior
IDs/XY/compact/scopes/preferences/accounts/distributions/original config/shortcut/full backup/
defaults/startup; absent size was not materialized, singleton0/old proxies0. Reopen/held-Flush closing
reds and the Arc-link fixture diagnostic remain retained. The UI failure proof injects a pre-Store
failure and checks exact owned target/backup bytes; Core's actual atomic failure proof is separate.
Actual footer bounds passed and the original footer remains unchanged.

At this SET-02 checkpoint, account token creation and empty-field verification of an existing
credential were missing local functions; the later ACC-03 checkpoint below qualifies them.
Explicit nonempty verify/save/replace and Return routing retain qualified fake-body proofs.
Account browser Test already reads current draft browser/profile/endpoint at click; picker/
fallback proof does not establish a live signed-in launch. Fresh/missing settings default120 seconds;
legacy omitted RefreshSeconds retains60. Actions repositories remain per-account rather than Mac's
deck-wide watchlist disabled while Actions is off. These ACC-03/09/SET-11 wording corrections add no
new account behavior or live qualification. SET-02 OS sidebar metrics, SET-08, updater install/notes,
full summon and native Mac/x64/live identity/physical input/accessibility/display/phone/shell/signing/
clean-machine/full migration remain open. See [ADR0041](../docs/adr/0041-windows-settings-window-size-persistence.md).

HTTP validators and bodies survive refreshes inside each worker, with separate provider/account/host/
credential namespaces. Cached transports hold no token store or authorization headers. Mark-read
invalidates the account cache. Inbox polling respects the server interval within 60 seconds–one day.

## Develop

Use .NET 10 SDK on Windows and Swift 6.3.3 in the official Jammy container for the worker.
`DevDeck.Windows.Core` has no WPF dependency. Its console test executable uses owned fake processes.

```powershell
dotnet run --project Windows/DevDeck.Windows.Tests/DevDeck.Windows.Tests.csproj
dotnet build Windows/DevDeck.Windows.App/DevDeck.Windows.App.csproj
```

Build the Linux worker with a separate SwiftPM scratch volume, then run
`Tools/WorkerSmoke/package_runtime.sh <scratch> <output> release` after a Release build inside that container. Package that output
as `.localtools/worker-linux-arm64.tar`; the WPF project includes it as a development artifact.
Do not call a container binary a supported runtime until it is checked inside each distro.
The ARM64 Release bundle was negotiated from Windows in Ubuntu-24.04 and Debian (glibc 2.36).
An owned actual DDEV project passed start/status/HTTP in Windows/logs/restart/stop from the native
Windows client. This does not qualify every existing project, HTTPS trust or Linux x64.
The runtime's debug-only isolated-shell hook is for owned live fixtures and is omitted in release
worker builds. Production packaging must build and qualify release workers separately.

Publish the self-contained Windows package onto a local Windows filesystem:

```powershell
pwsh -File Windows/build.ps1 -Runtime win-arm64 -Launch
```

The script defaults to `%LOCALAPPDATA%\DevDeck\Development\app`. A WSL UNC source checkout is
fine for compilation, but native WPF DLL loading from that case-sensitive share failed locally;
the identical package ran successfully from NTFS. Script execution restrictions may require using
the equivalent direct `dotnet publish` command; do not change global execution policy.

Initial settings live separately at `%LOCALAPPDATA%\DevDeck\windows-settings.json`, with schema
version 1, stable card IDs and an atomic backup on saves. Settings must also use a local Windows disk.
Existing-target replacement retries only IOException0x80070497/error1175 while prepared temporary,
original target and previous backup bytes/absence remain unchanged. At most five attempts use
10/20/40/80ms waits within a200ms monotonic retry-admission budget; other errors/changed files fail
immediately. The budget does not bound an OS syscall or make this a cross-process transaction.
There is no delete/copy/rename fallback or automatic corrupt-settings recovery.
`--settings <path>` selects an isolated
development configuration. Opening a corrupt/unknown schema does not silently replace it.
The Windows host installs versioned worker bundles under each distro user's
`~/.local/share/devdeck/workers/<bundle-hash>/`, leaving system toolchains and profiles alone.

`--integration-check --report <path>` checks real card status and exits; it never issues project
actions. `--sample-render <png>` renders only a synthetic card without WSL or actual project data.
Add `--sample-remote` for a remote card and `--language ru` (or en/de/es/fr/it) for a language sample.
`--sample-state stopped` / `paused`, `--sample-busy` and `--sample-collapsed` exercise local layouts.
`--sample-docker`, `--sample-settings`, `--sample-account`, `--sample-attention` and
`--sample-notifications` render synthetic
Docker gating and scrollable forms/lists; settings samples contain seven invented projects.
`--window-check --report <path>` runs native synthetic HWND checks for local/remote desktop, floating,
hide/show and summon transitions, transparency preservation and ordinary settings/list windows.
It also checks native tray registration/callback decoding without sending notifications, Docker gating,
and scrollable settings/account/attention layouts in all six languages. It neither starts
workers nor uses actual project/account data.

## Per-user package

`build.ps1` publishes a self-contained `.exe`, worker archives, installer/rollback/uninstaller and
a checksum manifest. Run the package's `install.ps1` to install immutable versions in
`%LOCALAPPDATA%\DevDeck\Versions` and create a Start menu shortcut. `rollback.ps1` selects the
previous verified package. `uninstall.ps1` removes owned app packages while preserving settings,
credentials, WSL runtimes and projects. No administrator rights are needed.
Installation enables no autostart. An existing owned startup shortcut follows upgrade and rollback;
uninstallation removes only owned startup entries and requires the installed app to quit first.

Packages remain unsigned development artifacts with `releaseQualified: false`. Checksums verify
file consistency, not publisher authenticity. The separate Windows package workflow only uploads
dry-run artifacts. Native ARM64 installer/upgrade/rollback/uninstall fixture checks pass.

Windows release archives must be named `Windows-DevDeck-<version>-win-arm64.zip` or
`Windows-DevDeck-<version>-win-x64.zip`. The Mac updater accepts `DevDeck-*.zip`, so Windows assets
must never use that prefix. Windows Check Now selects its own architecture and opens release notes;
automatic update installation is not implemented.

The tray shows shared attention in waiting/needs-fixing/stuck/informational tiers. Click an enabled row
to open the account's browser profile, token settings, project log, Docker Desktop or checkout terminal.
Alt offers an exact personal Inbox read or permitted local-problem Dismiss alternate; the expanded
list exposes the same named action explicitly. Live health/sync faults remain visible until recovery.
Notifications default off. First observations after launch/reconnect/configuration changes are quiet;
the last 200 candidate IDs are persisted and three simultaneous new events become one summary.
Account/project switches control reviews, blocked work, failed main-branch runs and project failures.
Changing notification switches preserves worker sessions and project watch history. Hidden cards do
not fetch. All-account failure preserves previous rows and adds safe account diagnostics.

Known worker and host failures use translated guidance in all six languages: WSL setup, DDEV,
Linux Node/Fusion/Compose, Docker port conflicts, account refresh/read actions, credential storage
and missing browsers. A port conflict asks you to change this project's mapping; DevDeck never stops
an unrelated Docker stack. Fixed English protocol diagnostics retain the exact port for inspection.
Unknown worker rejection messages use safe generic guidance. Owned fake-process checks verify that
reconnecting a failed distro does not replace another distro's healthy session; actual WSL shutdown
and Docker recovery still need controlled acceptance.

## Provider-specific account settings

GitLab has an instance Address before the token and provider-specific help/browser/profile. GitHub
organizations/repositories and failed-run switches are hidden for GitLab; Notifications shows an
accessible not-applicable dash for that failed-run preference. New unsaved provider switching keeps
endpoint/scope drafts in place, then the first commit locks provider and keeps the account ID.

Native request credentials validate the current account and project unused GitLab scope fields to
empty arrays. Stored inactive arrays and failed-run bits stay untouched, including settings-valid
raw/duplicate/null-element entries. Unedited GitHub arrays stay exact and still face strict worker
validation; only explicit comma edits reparse them. Captured revisions preserve edits made during a
pending save. New GitLab accounts store empty scopes/failed-run false. Test uses the current valid
endpoint/browser/profile; nonempty token save/Return retain the guarded verify/write/commit path.

The historical Preview39204/package99b3f7da4605432e9bba23fcf965ce5d qualified this subset: Core focused4/
full222, native1541/0 exit0/170.35s, installer8/0 exit0/23.64s and read-only7local+2remote exit0/
9.62s. Completed312 six-language synthetic views include30 provider scenes; App/manifest match the final package. The26 provider groups drive real form/controller bodies with fake request,
credential/browser/discovery dependencies. Six exact unchanged-worker wire checks have no usable
token/HTTP call; worker379/runtime16/Arc4/metadata5/Git30+60 remain reused qualification.
Only restored owner6168 was replaced by39204. All nine0x80080 HWNDs and prior card IDs/XY/compact/raw scopes/accounts/preferences/distributions/original configuration/shortcut/full backup/defaults/startup are preserved; absent size stays omitted, singleton0 and old worker proxies0. Mac119/graph/spec140/204 remain unchanged.

Token-creation links and empty-field stored-token Verify were separate local gaps then, closed by
the later ACC-03 subset below. Live credentials/browser identity and the deck-wide Actions watchlist
remain open, alongside SET-08/display/summon/update/release gates.
[ADR0042](../docs/adr/0042-windows-account-provider-applicability.md).

## Account token actions

Create token opens GitHub's hosted page or the current GitLab instance-prefix page using the
selected browser/profile. Other GitHub API endpoints show a blank Enterprise token-page prompt
with the exact captured API address for context. Return and Escape cancel; explicit Open uses
the bounded HTTPS address once without storing it. Creating a link does not require a complete
new-account name/scope draft or perform a credential read, worker acquisition or provider mutation.

Verify saved token and an empty replacement Return check the committed credential once through
the isolated configured settingsChecks route. A half-entered replacement is preserved; nonempty
Verify and save retains its existing verified write/commit/cleanup path. Cached presence is distinct
from API acceptance or repository/Inbox/Actions permission. Identity, full worker route, password
revision and form-owner epoch guard the result. Token feedback keeps ordinary metadata errors;
stored verification writes no credentials/metadata and resets no attention, queues or check time.

Each distribution can now own five lazy channels: ordinary local, shared remote, checkout,
settingsChecks local and settingsChecks remote. GetExactAsync changes only a mismatched check
client; legacy worker reuse is unchanged. These are logical ownership slots, not five mandatory
running processes.

Preview68312/package04928307578842e6b1c3337fdf206cf0 is qualified and active: Core focused4/full226,
component30/0 in32.83s, fullnative1571/0 in189.8s, installer8/0 in24.29s and read-only7local+2remote
in12.09s pass. Completed342 synthetic scenes include30 token scenes in six languages; six new
English/Russian scenes were visually reviewed. All use the correlated final App/manifest.
Only recorded39204 was replaced; all nine0x80080 HWNDs and prior IDs/XY/compact/raw accounts/scopes/
preferences/distributions/configuration/shortcut/full backup/defaults/startup are preserved,
absent geometry stays omitted, singleton0/old proxies0. Mac119/graph/spec140/204 remain intact;
worker379/runtime16/Arc4/metadata5/Git30+60 are reused by exact hash.

The30 native groups use owned stores, fake credentials/openers/verifiers and one owned fake child
through the actual worker manager; they do not qualify real accounts, WSL API requests or browser
identity. The existing nonempty replacement's maximum128-byte account-ID namespace limitation and
legacy slash-bound metadata-save limitation remain; stored checks preserve the exact saved slash
and use a bounded fixed verification namespace. Native Mac/x64/live permissions/browser/phone/
display/shell/signing/clean-machine and full migration gates stay open. Expanded SET-08 provenance
remains unimplemented.
See [ADR0043](../docs/adr/0043-windows-account-token-actions.md) and
[qualification](../docs/windows-qualification.md); releaseQualified=false.

## Remaining release work

Expanded display/shortcut/recovery checks, remaining feature and diagnostic wording parity,
signing/updater, clean-machine install, Linux x64 bundle
and full Mac/Windows regressions remain open. Windows x64 has not been qualified on x64 hardware.
Mac source/manifest hashes supplement its required native suite/build and manual checks.
See [full migration plan](../docs/windows-migration.md) and [protocol](../docs/worker-protocol.md).
The [qualification matrix](../docs/windows-qualification.md) distinguishes locally passed checks
from required native Mac/x64/manual/signing gates.
