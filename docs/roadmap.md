# Roadmap

## Done

- **Foundation** - configuration, card catalog and layout, HTTP transport with conditional
  requests, rate-limit parsing, retry and refresh policies, Keychain token storage.
- **GitHub · my pull requests** - one GraphQL query, health derivation, the card, the panel,
  the menu bar count.
- **GitHub · inbox** - unread notifications with reason chips, priority ordering, the unread
  badge in the menu bar, and the server's own poll interval feeding the refresh loop.
- **GitHub · Actions** - success rate over a window, running and failed runs, one request per
  repository with per-repository caching and per-repository failure tolerance.

- **Several GitHub accounts** - one token per account, all feeding the same cards, with
  partial failures shown in the footer instead of blanking the card.
- **A browser and profile per account**, so a row opens as the identity that owns it, plus
  per-row account chips and click-to-expand cards.

- **Arc XP projects** - one card per project: editable link templates opened in the project's
  own browser, local Fusion stack status from the engine's health URL, and start, stop and
  restart running the Arc CLI in the project folder.
- **Settings with sections** - GitHub accounts, Arc projects and General kept apart in one
  window, and a menu-bar icon that says which app it belongs to.
- **Settings as one list and a form** - grouped by kind with General pinned at the top, one item
  edited at a time, forms
  built by `FormLayout` so they stretch with the window instead of leaving dead space (since
  replaced by `SettingsForm`, see [adr/0018](adr/0018-settings-like-system-settings.md)).

- **DDEV projects** - one card each, fed by a single `ddev list` for the whole deck, with PHP
  and database versions read from the checkout, paused treated as its own state, and a global
  power off in the menu. Shipped as 0.2.

- **Plain projects** - a card for anything with a folder and a command: the folder is read for
  a suggestion when the project is added, a command that holds its process is started detached
  with a log and a pid, and the health URL decides whether it is running. Shipped as 0.3.
- **The Docker gate** - one probe for the whole deck, and cards that need containers say
  "Docker is not running" and offer to start it rather than a Start that cannot work.
- **The card redesign** - one focal point per card: the state at 17 points, the pill and the
  footer gone, chips wrapped into one block, quieter controls with icons, the vendors' real
  logos parsed from their own SVGs, a card 352 points wide so `Terminal` fits, and glass that
  is glass again rather than grey paint. Three directions were mocked up first; see
  [adr/0009-card-hierarchy.md](adr/0009-card-hierarchy.md).
- **Commands find version-managed tools** - the `PATH` is resolved from an interactive shell
  once per launch, so `npx` and `pnpm` work from a card and not only from a terminal.
- **Buttons act on the first click**, and a stop that did not take effect says so instead of
  being repainted green by the next poll.
- **The phone and the work in flight** - the running site as a QR code addressed to this Mac on
  the wifi, offered only while the project is up; and one card for every checkout at once, showing
  what is uncommitted, unpushed or behind. Shipped as 0.8.
- **Signed and notarised releases** - the Keychain mode and the updater's check follow the
  signature the app finds itself under, `build.sh` signs with whatever `CODESIGN_IDENTITY`
  names, and the release workflow imports the Developer ID, signs with hardened runtime and a
  timestamp, notarises, staples and only then packages, all behind five secrets. Tokens are
  bound to the app on every machine, and a first install opens without the right-click dance.
  Shipped as 0.12. See [adr/0017-signature-decides.md](adr/0017-signature-decides.md).
- **Settings like System Settings** - four pages instead of one General three screens long,
  accounts and projects in one sidebar with their marks and a dot only when it means something,
  search and the keyboard in the list, forms in the order they are filled in with the rarely
  touched fields under Advanced, answers next to the button that asked, a health check that reruns
  when the address changes, and "Settings for This Card…" on every card. Shipped as 0.13. See
  [adr/0018-settings-like-system-settings.md](adr/0018-settings-like-system-settings.md).
- **What needs you, named** - the menu-bar badge in four shapes for four tiers, waiting on you,
  needs fixing, your work is stuck and good to know; the menu listing the things themselves with
  where, who and how long, one click from each; GitLab counted, a review counted once, a rejected
  token no longer calm; projects on this Mac that stopped on their own, did not start, stopped
  answering or lost their file sync, and Docker quitting under them as one row; workflows failing
  on a main branch; commits only on this Mac for more than three days; banners that say what
  happened, per project switches, and one set of row codes for both services. Shipped as 0.15. See
  [adr/0019-attention-in-tiers.md](adr/0019-attention-in-tiers.md).
- **What the documentation audit after 0.13 found** - the README checked line by line against the
  code and brought up to date, and four places where the code had drifted from it: a DDEV site's
  local link dims again while the project is down, no install starts under a running command
  whichever way it was asked for, a copy without an identity and `seed-token.sh` no longer write
  a token open on a machine where tokens are bound, and the update banner obeys the app's own
  notifications switch. Shipped as 0.14.
- **The lock is back in the menus** - a checkmark in the menu-bar menu and in a card's own
  right-click menu, next to Tidy, because it is toggled in the middle of arranging cards.
  Settings keeps its switch; both write the same preference.
- **The app updates itself** - a check against the latest GitHub release after launch and
  every six hours, one line at the top of the menu and one banner when there is a newer build,
  and an install only on a click: download, `ditto`, the unpacked bundle checked against the
  release, the old copy to the Trash, relaunch. No quarantine on what the app fetches itself,
  so the right-click dance ends after the first install. Shipped as 0.11. See [adr/0016-self-update.md](adr/0016-self-update.md).
- **The application layer in pieces** - the refresh loop decides in Core under tests and
  only fetches in the app, the app delegate is a composition root over five objects with one
  job each, and a kind of card is one module: its view, size, catalog entries, menu group and
  settings section in one file. The smoke test covers every GitLab instance as well, and the
  app builds against the macOS 27 SDK without Xcode. Shipped as 0.10. See
  [adr/0015-application-layer-in-pieces.md](adr/0015-application-layer-in-pieces.md).
- **Monorepos read properly** - a Turborepo of a Next front end and a Nest API is a plain
  project like any other, but the probe now walks its workspaces for the app that serves the
  site, reads the port off the script line or `.env`, follows the dev script one level to find
  the Docker it starts, and picks a mark that names the framework rather than the runtime. Next,
  Nest and Bun joined the brand marks. Shipped as 0.10. See [adr/0014-monorepos-and-marks.md](adr/0014-monorepos-and-marks.md).
- **A day of somebody else's use** - paste works in settings, a card no longer believes one bad
  poll, a folded card keeps its controls, and the settings window lost a column and gained the
  margins it never had. Shipped as 0.9.
- **The deck's own housekeeping** - the refresh interval and the Actions repository list are
  controls rather than model fields, a right-click on a panel is about that card, project kinds
  are submenus, powering off every DDEV project asks first, the four settings forms all open the
  same way, a project can carry a link of its own, an inbox row can be marked read, and the deck
  can be saved as a named arrangement and put back. Shipped as 0.7.
- **The Keychain stops asking** - tokens are stored with an access list that a rebuild does not
  invalidate, so an update no longer costs one password prompt per token (for ad-hoc builds;
  signed builds bind tokens to the app since 0.12).
- **A release builds itself** - publishing a release on GitHub runs the suite, builds the bundle
  and attaches it to the tag, and every push runs the tests. Shipped as 0.6.
- **Notifications** - a banner when somebody asks for your review, and optionally when something
  of yours is blocked, carrying the service's own mark, switched on per account and per kind, with
  nothing announced twice or on the first pass after a launch.
- **GitLab merge requests** - a card of its own, yours and the ones waiting on your review, from
  one GraphQL request per instance, with the host on the account because GitLab is routinely
  self-hosted. See [adr/0013-gitlab.md](adr/0013-gitlab.md).
- **Both icons, drawn in code** - an application icon at last, one card carrying the hero row,
  rendered at all ten sizes and packed by `build.sh` (artwork in `Resources/AppIcon` since 0.17);
  and a menu-bar icon with
  three states instead of a red glyph that meant three different things at once. Shipped as 0.5.
- **The menu is for doing, Settings is for deciding** - placement, locking, packing, summoning
  and start-at-login moved out of the menu-bar menu into Settings under General (placement and
  summoning are on the Deck page since 0.13). Shipped as 0.4,
  together with the log tray, the collapsed card, summoning and the placement fixes.
- **The deck stops moving cards nobody asked it to move** - restarting reproduces a layout
  exactly, and closing up a column is a switch rather than a habit. See
  [adr/0012-automatic-movement.md](adr/0012-automatic-movement.md).
- **Summoning** - hold the shortcut and the panels rise over everything, let go and they drop
  back, with the screen dimmed while they are up and the combination set in Settings.
- **A card has two sizes** - whole, or one 44-point row with the mark, the state dot, the name
  and the one action the state implies, kept per card. See [adr/0011-two-sizes.md](adr/0011-two-sizes.md).
- **The log tray** - the last six lines a project is writing, on the card itself, for Arc, DDEV
  and plain projects alike, read only while the tray is open. Replaced in a later pass by a
  window of its own, see below.
- **A running command narrates itself** - its newest line sits on the card while it works, and a
  start that failed keeps the reason it printed even when the command exited zero.
- **The deck has a canonical order** - Arc, DDEV, then plain projects, alphabetical within each
  - so tidying lays cards out by a rule rather than by the order they were added in.
- **Panel positions belong to a display**, so a deck kept on the laptop screen survives an
  external monitor coming and going.
- **Arranging the deck away from home sticks** - tidying or dragging while the display a card
  belongs to is unplugged is saved against the screen it is actually on, instead of being undone
  by the next screen change.
- **The deck parks folded** - with its monitor unplugged the deck is one column of 44-point rows
  at the side it stood on, and goes home exactly when the monitor is back, because the shove
  macOS gives windows on a display change is no longer mistaken for a drag. See
  [adr/0022-the-deck-parks-folded.md](adr/0022-the-deck-parks-folded.md).
- **Pull requests waiting for your review** on the same card as your own, from a second search
  in the same request.
- **The branch on a card is a link** to the repository it came from, read from the checkout's
  own `.git/config`.
- **The deck is quieter** - colour left the chips, the palette came down about 20%, the dim text
  came up and the bright text came down, and every outline that was not the offered action came
  off. Two directions were drawn at true scale first; see [adr/0010-card-palette.md](adr/0010-card-palette.md).
- **The plain-project settings form**, in the same language: a header with the name and the
  card switch, commands with their captions above them, switches that explain themselves in one
  line instead of four footnotes, the live health answer in the group that asks about it, and
  environment rows tagged in their chips' colours.
- **The interface speaks six languages** - English, German, Spanish, French, Italian and
  Russian, the Mac's own by default and a forced choice in Settings, taking effect on the spot.
  Terms and logs stay English; the layouts measure their words instead of assuming English
  lengths. See [adr/0020-six-languages.md](adr/0020-six-languages.md).
- **The log is a window** - one per project, dark and monospaced, as big as you drag it,
  selectable and searchable with ⌘F, following the end until you scroll up, re-read every couple
  of seconds while it is visible and never while it is not. The tray inside the card is gone, and
  with it the 120 points that made the column jump every time somebody looked. See
  [adr/0021-the-log-is-a-window.md](adr/0021-the-log-is-a-window.md).
- **Cards say why they are quiet** - an empty Actions card says there are no open pull requests
  to follow and links straight to the field for a list of its own, a card with nothing run says
  so by name instead of "n/a", and its footer says where the repositories came from.
- **The inbox can be cleared from the card** - "mark as read, except the ones for you", or all of
  it with ⌥ or when only one kind is left, across the whole box rather than the page the card
  loaded, with its progress in the footer and GitHub's refusal named when there is one. The
  count says "50+" when the box did not fit, and the reason chips are in the interface's
  language.

## Next

1. **Bundle versions on the project card** - live version per environment, which needs an org
   token and the Developer Center endpoints pinned down against a real organisation.
2. **Resizable panels** - dragging the bottom edge instead of the expander, if the three-row
   default plus expansion turns out not to be enough.
3. **A tunnel, when the wifi is not enough** - `ddev share` for DDEV projects, and ngrok or
   Tailscale for the rest. The QR code covers the same network; this covers the customer on a
   call.

## Not planned

- WidgetKit widgets in Notification Center. They need Xcode and their own refresh budget; the
  panels already sit on the desktop. Revisit only if Xcode gets installed.
- A standalone Linux desktop release. Linux is the worker platform for the Windows migration.

## Windows migration in progress

- Current Windows completeness fixes are qualified and active118080/package781a6f: log Follow/
  current-target/header state, unchanged raw account metadata endpoints,128-byte verification IDs,
  guarded replacement→stored checks and shared bounded6 Inbox bulk reads. Components6/native1593/
  installer8/read-only9/render372 pass; Core226/worker382 are reused by70/208 identical inputs,
  while ADE5 runtime25/Git90 are new checks. Nine widgets/settings remain, with only two admitted
  runtime-route transitions. See [ADR0045](adr/0045-windows-completeness-logs-accounts-inbox.md).
  This scoped batch leaves notification/settings, typed Inbox outcomes, display/summon/branding/
  updater implementation and native Mac/x64/live identity/phone/input/Shell/signing/clean-machine/
  full migration gates open; no release is claimed.

- The [Mac functional specification](macos-functional-spec.md) now enumerates 140 source-referenced
  acceptance items and explicit Windows gaps. Source/control/resource drift is checked by
  `scripts/check-macos-spec.py`; presentation fixtures cannot certify production worker fields.
- Original DD panel-stack notification-area artwork replaces generic system icons. Shared attention
  tiers retain their distinct ring/ink-dot/red-dot shapes, with theme/DPI and owned handle lifetime.
  Complete Arc/xhgui/probe/browser/tray/default/display/summon/update flows remain tracked in the spec.

The [full migration plan](windows-migration.md) preserves the native Mac shell and release path.
[ADR 0023](adr/0023-windows-shell-and-wsl-worker.md) supersedes the earlier exclusion of Windows.

- Implemented locally: Mac source/manifest baseline, portable shared libraries and worker protocol,
  owned lifecycle/cancellation/log qualification, native ARM64 Windows local/remote cards, per-project
  Ubuntu/Debian workers, Windows credential storage and development packaging/installer/rollback.
- Windows cards have a shared compact design and stay outside Alt+Tab in desktop/floating modes;
  synthetic native regression preserves ordinary settings/log/list windows.
- Shared account/project/review attention and alerts, intentional-stop/two-poll/health/sync policies,
  tiered tray/list targets, bounded notification history and per-account/project switches now work
  through Windows-only adapters. Six-language synthetic settings/card layouts are checked locally.
- Known WSL/tool/account/credential errors have six-language guidance. Owned fake-process recovery
  preserves healthy distro sessions; real WSL/Docker recovery still needs controlled acceptance.
- Windows now has searchable contextual settings and metadata autosave, singleton live log windows
  with search/Follow/file/terminal viewing, conditional LAN QR popups, collapsed controls, shared
  repository/DDEV tooling links, project browsers and remote expansion/refresh preferences.
  [The parity audit](windows-feature-parity.md) retains the unimplemented Mac behavior explicitly.
- Next: remaining parity details and expanded native release qualification.
- Supplied Mac screenshots now guide Windows card surfaces/brand marks/status/branch/action rows,
  compact controls with a utility context menu, colored settings sidebar and grouped project forms.
  Built-in tool visibility, persistent TEST/UAT/PROD switches and selected-distro folder picking are implemented.
- Terminal folder/log launches now explicitly select a stable Windows cwd before WSL --cd; the
  inherited Preview directory regression and actual Ubuntu/Debian execution checks pass locally.
- Release gates still open: native Mac build/suite and interactive regression, Windows parity,
  supported-distribution worker runtime, clean-machine packaging and real-stack qualification.

- Windows Preview account setup now shows shared PR/Inbox cards; Actions is opt-in and GitLab setup
  shows MR. Tray and Settings/Cards expose visibility with stable IDs/scopes/positions. Removing an
  account detaches references; inactive scopes stop polling. Work in flight was pending for that batch; its later qualification is recorded in ADR0038.

- Windows Preview column layout now uses measured visible heights and the Mac 12-DIP gap, preserving the deck anchor and live window state. Compact mode has visible header/context/settings controls; see ADR 0025.

- Windows DDEV production metadata now includes PHP/database versions beside framework/checkout,
  retained while stopped/paused/unknown or warning; xhgui capabilities reach saved host switches
  with new-project default off. Full worker/DTO/native and existing-checkout qualification passed;
  Mac UI/product graph stays frozen. See ADR0027; template/kind and external release gates remain.

- Windows local cards now share the Mac ten-second cadence and one DDEV inventory per explicit
  cycle, with fresh manual/action observations and separate local/remote worker connections.
  Busy/closed cards skip polling and a slow cycle coalesces later ticks; see ADR0028.

- Windows compact cards keep cancellation icon-sized during start/stop/restart. Expanding or
  collapsing during a command preserves progress and keeps idle lifecycle controls hidden;
  six-language native regressions cover all three local project kinds and repeated operations.

- Windows Arc settings and worker preserve organization/site/local origin/health/custom commands
  and the shared local PageBuilder URL. Typed dynamic links preserve templates and tool/site kinds;
  hosted-only Arc cards need no status worker and keep identity when attaching a checkout. See ADR0029.
  Short tool/site groups fit one row; phone QR controls hide while stopped or working and survive
  view changes with correct availability.

- Windows plain projects now offer the shared Compose/package/workspace/Make Detect flow. It
  preserves entered caption/health/name/opening address, ignores results for a changed checkout
  and keeps separate check/open URLs. Captions and framework marks match the original model;
  command metadata remains separate and follows compact visibility. See ADR0030.

- Windows QR opens availability guidance for routed DDEV/missing LAN addresses and accepts a
  separate explicitly configured phone URL. Copy dismisses, status updates refresh an open code,
  failed reads prevent stale codes. No project/server/network setting is changed; see ADR0031.

- Windows project cards now use a recognizable Git fork with three commit nodes beside the branch
  label, replacing the U-shaped drawing; the label and glyph share vertical alignment.

- Windows settings/browser parity is qualified and active in the Preview: Ctrl+F/sidebar arrows and shared
  cancel-default removal confirmation, explicit token Return, quiet editable autosave and fresh
  scoped Arc/plain health rows using the original worker summary. Ephemeral `project.check` and its
  separate settings transport keep draft checks from changing live card observations or canceling
  other worker requests. Invalid metadata retains its editable draft until corrected. Installed browser discovery,
  friendly Chromium profiles and missing/start-failed default fallback preserve saved choices;
  Firefox profile arguments are ignored. See ADR0032. Core96/0, portable worker317/0, native1034/0,
  installer8/0 and read-only seven-local/two-remote/runtime/Arc/DDEV checks pass. The updated Preview
  preserves all nine windows and existing configuration/defaults/startup. Full local/Arc synthetic
  forms were inspected; the subsequent ordering batch fixes the standalone browser's vertical profile
  clipping; TRAY-05 below also qualifies the right-edge Grid fixture correction. Natural ordering is qualified below. Native Mac/x64, live
  browser identities/real accounts and the remaining external migration gates stay open.

- Windows Preview tray and explicit Tidy now share one qualified natural catalog order: resolved
  built-in remote roles and extras, then Arc/DDEV/plain projects with numeric/case-insensitive titles
  and permanent-ID ties. It retains saved array order, legacy role resolution, scopes/visibility/
  compact flags and hidden placements, and moves existing live windows without rebuilding them.
  See ADR0033. Core104/0, native1041/0, installer8/0 and read-only seven-local/two-remote/runtime16/
  Arc4/metadata5 pass; the unchanged worker317 archive retains its qualified baseline. Owned
  Preview380656 preserves all nine windows and prior configuration/defaults/startup. Forty-eight
  synthetic scenes were generated and full local/Arc/account forms inspected; the standalone browser
  then showed its profile but needed the right-edge fixture correction qualified in TRAY-05 below.
  SET-04 sidebar live-state remained separate/partial at that catalog checkpoint; native Mac/x64
  and live/external gates stay open.

- Windows TRAY-05 is qualified and active: native visible subtitle/account/age rows, three urgent/two
  informational entries, single-leftover direct and same-tier overflow with preserved action identity.
  Trimmed text keeps full tooltip/accessibility detail; non-actions remain disabled and menu bitmap
  resources are disposed on rebuild. The calm local HH:mm uses the Windows receipt of a validated
  attention observation, not an event timestamp or settings draft; unknown time falls back to now.
  Previous five-row and actual package-width reds are retained; explicit main/overflow sizing and
  bounded native title prefixes prevent clipping, including enlarged fonts. Core112/native1103/
  installer8 and fresh read-only7+2/tray10s/three-transport checks pass; worker317/runtime16/Arc4/
  metadata5 remain the unchanged byte-identical qualified baseline. Twenty-four final synthetic views
  qualify main/overflow/calm/browser, including the Grid-root profile/right-edge fixture fix. Mac119/
  product graph/spec140/204 and whitespace pass. Owned Preview408076 preserves all nine0x80080
  windows and original settings/configuration/shortcut/backup/defaults/startup, singleton0 and old
  proxies0. See ADR0034. TRAY-06/07 and full migration/external gates
  remain open; original Mac and worker sources stayed unchanged for that batch.

- Windows UI-08 visibility/context is qualified and active, using exact permanent IDs and retaining hidden native owners,
  operations/snapshots/list/log state while stopping new polling. Hide does not wait for an unrelated
  lifecycle action or reset sibling attention/session history. Settings reconcile matching visibility
  controls in place; current Enabled survives queued metadata, and invalid drafts/focus/errors remain.
  Optional activeProjectIDs bounds local/Docker attention without deleting original watch/status/jobs;
  visibility revisions discard obsolete attention only and quiet reveal seeds old own notifications.
  Card menus now include current compact/log/lock state, Tidy and all-active-card refresh; Inbox
  explicit read-rest/read-all rows preserve displayed per-account cutoffs and current mutation guards.
  Core122/0, portable worker328/0, native1165/0 and installer8/0 pass with a warning-free ARM64
  package. Fresh read-only7+2/tray10s/three-transport, generic runtime16/Arc4/DDEV metadata5 and sixty
  synthetic views pass; Mac119/product graph/spec140/204 and whitespace remain clean. Only owned
  Preview408076 was replaced by413076/package9b16d53b1d9d46fca8bca9fcacca4ad4, preserving all
  nine0x80080 windows and prior IDs/settings/positions/compact/scopes/preferences/distributions/
  original configuration/shortcut/full backup/defaults/startup, singleton0 and old proxies0.
  See ADR0035. At that visibility checkpoint SET-04, all-DDEV poweroff and TRAY-07 attention modifier
  twins remained open. Full external release gates remain open; original Mac sources/graph are preserved.

- Windows TRAY-06 dashboard/active-refresh/arrangements and precise Deck modes subset is qualified
  and active. Fixed public pulls dashboard uses the first enabled saved GitHub browser/profile or
  system. Refresh coalesces existing active reads and skips hidden/hosted/busy cards without cancelling
  jobs/transports. Arrangements capture full IDs/chosen Enabled/compact/saved XY; fresh current-state
  Match ticks, trimmed in-place case-insensitive overwrites and explicit new-save limit eight preserve
  legacy identity/order. Save/Forget keep attention/check time/Seen/queues/native owners; Apply uses
  scoped visibility→compact→XY and leaves unrelated/new cards and in-flight work intact. Busy remote
  collapse may remain partial with honest match state and finish on idle retry. Tray and Deck expose
  explicit named Forget; localized rounded name prompt supports Save/Return and Cancel/Escape.
  Deck floating/locked use precise setters and reconcile open controls/drafts in place.
  Core132/0, native1261/0 and installer8/0 pass with a warning-free ARM64 package;
  worker328/b5c1 suite/archive are unchanged and explicitly reused, not rerun. Fresh read-only7+2,
  runtime16/Arc4/DDEV metadata5 and84 synthetic views pass; Mac119/product graph/spec140/204 and
  whitespace stay clean. Only owned Preview413076 was replaced by437068/package
  db0486ac622a43e083fbda7abbd848fb, preserving all nine0x80080 windows and prior IDs/settings/
  positions/compact/scopes/preferences/distributions/defaults/startup/original configuration/shortcut/
  full backup, singleton0 and old proxies0. See ADR0036. That active package does not include the next poweroff batch;
  SET-04/TRAY-07 remained open at that command checkpoint. Native Mac/x64/live identities/phone/
  display/shell/signing/full migration gates remain open.

- Windows DD-05/all-DDEV poweroff and the remaining TRAY-06 action are qualified and active446868.
  The frozen-route, Cancel-default product dialog explains all DDEV on connected Docker servers,
  including off-deck/other-WSL projects, router and SSH agent. Enter/Escape/X decline; only explicit
  Power off accepts. Typed prepare/run/finalize/abort captures each polling actor, requires all-actor
  barriers/lease renewals and executes the unchanged shared CLI serially once per unique confirmed
  DDEV-bearing distribution. Lost runs are never retried or moved to a replacement actor. Worker
  epochs/intent overlays/non-cancelling inventory and monotonic 600-second lease cleanup preserve
  unrelated watches and restore never-run state exactly; final typed physical states/diagnostics
  remain honest for unknown/partial outcomes. Native group presentation keeps hidden/compact owners,
  HWNDs/positions/logs/actual CTS and settings/Seen/queues, with stale-read/token guards and no dead
  group Cancel or oversized compact Stop. Final Core149/worker345/native1328/installer8 pass, with
  a warning-free ARM64 package,102 synthetic views, fresh read-only7+2 capability hello on the one
  configured DDEV distribution (lifecycleInvoked=false), runtime16 in Ubuntu/Debian, Arc4/metadata5
  and Mac119/product graph/spec140/204/whitespace checks. Only owned437068 was replaced by446868/
  package bf3c10f14d724c7b90bcbfe51df429aa, qualifieda9 archive/1203 binary; all nine0x80080 HWNDs,
  previous IDs/settings/positions/compact/scopes/preferences/distributions/defaults/startup/original
  configuration/shortcut/full backup, singleton0 and old proxies0 are preserved. Lifecycle
  qualification uses fake CLI only; no real poweroff command is used for these checks.
  See ADR0037. SET-04/TRAY-07 remained open at that poweroff checkpoint. Native Mac/x64/live remote
  identities/phone/display/shell/signing and full migration gates remain open.

- Windows WIF/shared cadence is qualified and active in Preview484424.
  Optional default-off fixed-ID preferences preserve null/legacy arrangements and retain disabled
  owners. All configured Arc/DDEV/plain folders, including hidden sources, are selected in saved
  kind order and deduplicated by distribution/lexical path; over1024 retains the previous cache with
  a diagnostic. Isolated one-checkout typed reads reuse the shared status/log parser and age policy,
  with child-only GIT_OPTIONAL_LOCKS=0/GIT_NO_LAZY_FETCH=1/GIT_ALLOW_PROTOCOL=,
  20-second Git limits and75-second native RPC deadlines. Original Linux numeric-other fallback
  avoids the Foundation stringsdict crash; native six-language plurals reconstruct WIF text without
  altering shared policy or Mac resources.
  Native410-DIP cards show three/twelve rows and≤76-DIP compact states, first two localized facts,
  exact typed checkout terminal targets and honest checking/partial/all-failed/stale diagnostics.
  Hidden reads retain cache/HWND without token cancellation or stale attention; no-qualified receipt
  never displays all-clean. Dedicated informational scope has no banners/queued notifications.
  A controller-owned shared cycle replaces per-remote timers: PR→Inbox→MR→Actions/extras→open logs→
  checkouts, with coalescing and the original bounded delay/backoff/reset/hints. Old omitted60 and
  new empty120-second preferences remain distinct. Tray/Cards/context/modes/arrangements/geometry
  integrations pass, with precise aggregate saves preserving unrelated optional arrays/null.
  Narrow unchanged-file atomic replacement recovery admits only1175 retries, at most five calls
  within200ms admission and no non-atomic fallback; original external locker cause is not claimed.
  Final Core183/0 (170+atomic13), worker367/0, native1396/0 observed exit0, installer8/0,
  synthetic192 (102prior+90 WIF/six languages), fresh read-only7local+2remote/four independent
  channels/shared cadence/default-off-no-Git/poweroff capability lifecyclefalse, runtime16/Arc4/
  metadata5, owned ordinary Git30/promisor60 and Mac119graph/spec140/204/diff pass. Final archive
  0ea97b/binary7f57a8 belongs to package02ea3db442754597aaeccb7315e1876d. Only recorded446868 was
  replaced by484424, preserving all nine0x80080 HWNDs/preexistingIDs/positions/compact/scopes/
  preferences/distributions/defaults/startup/original configuration/shortcut/full backup,
  singleton0/old proxies0. The first180s helper timeout is retained; the same artifact completed
  exit0 in180.05s on its bounded rerun. No actual user checkout, terminal, provider mutation or
  lifecycle action was used. Own ordinary/promisor fixtures qualify installed Ubuntu/Debian paths,
  not arbitrary repository programs/object layouts/Git packages. See ADR0038; at this checkpoint
  SET-04 still lacked flat natural sidebar ordering/runtime dots/disabled dimming, and TRAY-07 lacked
  attention modifier/Inbox read alternatives (AttentionWindow Dismiss-only). Its later subset follows.
  Native Mac/x64/live identities/
  phone/display/shell/signing/full-migration gates stay open.

- Windows TRAY-07's supported attention subset is qualified and active570836/package
  2cc50416402c48b9bab4ac6624d88107. Optional protocol1 read targets bind the original personal Inbox
  card/account/API endpoint/thread before dedupe; UTF-8 tuple identities avoid account raw-ID
  collisions while original personal eligibility/review-URL overlap remain intact. Scoped Alt and
  explicit full-list actions select read before permitted project dismissal, support URL-less reads
  and retain inert primary.none. Current admission, exact-tuple optimistic masking, honest failures
  and no replay preserve check time, sibling scopes and hidden started work. Hidden configured
  project primaries enable the same retained owner and open one log. Current-chain capture happens
  before native auto-close; visible controller rebuild closes before disposal and unhooks the adapter.
  Final Core202/0, worker379/0, native1468/0 observedexit0/181.91s (72new included, no separate final
  run), installer8/0 exit0/36.08s,228 six-language synthetics, read-only7+2 exit0/33.25s, runtime16/
  Arc4/metadata5/exact d9fc85+abd86a owned Git30/promisor60/Mac119graph/spec140/204 pass.
  Only recorded484424 was replaced; all nine0x80080 HWNDs/IDs/XY/compact/scopes/preferences/accounts/
  distributions/original configuration/shortcut/full backup/defaults/startup/singleton0/old proxies0
  are preserved. Genuine source reds/98d7's qualified product and incomplete renders remain retained;
  sample-only overflow4→5 was requalified in final2cc. No real provider write/credential/lifecycle/
  network or desktop capture was used. Independent owned STA queued delivery does not establish
  physical Alt/AltGr/IME/screen-reader or same-thread modal key isolation. See ADR0039.
  TRAY-07 stays partial for native updater install/available-update notes; SET-04 was open at that
  checkpoint. Full summon and native Mac/x64/live identities/phone/display/shell/signing/
  clean-machine/full migration remain open.

- At the Windows SET-04 checkpoint, sidebar state/order qualified in601784/package
  9563ba2b2a4242fa9a58c76f8b166764: separate flat natural account/project groups preserve saved ties
  and independent deck order. Current retained hidden local owners supply semantic Running/Busy dots;
  disabled rows stay selectable with dimmed icon/title and undimmed dot. Exact-target credential
  availability is a cached bounded metadata boolean. Constructing a new window/committing its current
  credential target may read metadata; re-show/search/project callbacks consume caches only.
  Current-owner/replacement/lifetime reconciliation preserves form/draft/password/query/caret/focus/
  selection/scroll/debounce/CTS and attention/Seen/check time. Genuine c5 opening, e61 initial focus
  premise and eced stale expected-order failures remain retained, with original production reds.
  Final Core214/0 (12new), native1492/0 observedexit0/296.17s, installer8/0 exit0/118.88s with
  identical manifest,252 six-language synthetics (24sidebar), read-only7+2 exit0/32.34s pass.
  New24 are extracted from the full run (`standaloneRun=false`); separate4988 component24 is
  historical. Final standalone legacy navigation68/0 exits0/11.83s. Exact unchanged TRAY worker379/
  runtime16/Arc4/metadata5/owned Git90 proofs are reused with final package/hash correlation,
  not rerun. Mac119graph/spec140/204 pass. Only recorded570836 was replaced by601784; all nine
  0x80080 windows and previous IDs/XY/compact/scopes/preferences/accounts/distributions/original
  configuration/shortcut/full backup/defaults/startup remain, singleton0/old proxies0.
  See ADR0040. SET-02/08, TRAY-07 updater install/notes, full summon and native Mac/x64/live
  identities/phone/physical input/accessibility/display/shell/signing/clean-machine/full migration
  gates remained open at that checkpoint. The later settings-size qualification follows.

- Windows settings-size persistence is qualified and active627264/package
  3779f95e4665421bb0c218a54cea339e. Resizable width/height retain1020×720-DIP defaults/min880×440;
  only completed normal user resize creates the optional size. Supported-area effective clamp
  leaves chosen size stored. Current-model persistence bypasses project actions, preserves actual
  forms/drafts/password/focus/error/health CTS and retained cards/attention/Seen/queues/check time/
  polls; queued metadata cannot overwrite newer size. Closing invalidates pending receipts before
  Flush; separate localized errors permit a later explicit resize retry. Footer actual bounds pass
  unchanged. Original reopen/closing/first-full Arc-link diagnostic failures remain retained;
  the Arc fixture now seeds canonical links before initial Save with strict assertions unchanged.
  Actual apphost Core4/full218, native1515/0 exit0/232.51s, installer8/0 exit0/38.33s with same
  manifest,282 six-language synthetic views (30geometry) and read-only7+2 exit0/45.58s pass.
  New23 are extracted from full1515 (`standaloneRun=false`); historical standalone12a56923/0 in
  31.75s is separate. Exact d9fc85/abd86a worker379/runtime16/Arc4/metadata5/owned Git30+promisor60
  baseline is reused, not rerun. AppEC4C62/manifest95207F and Mac119graph/spec140/204 correlate.
  Only recorded601784 was replaced; all nine0x80080 HWNDs and prior IDs/XY/compact/scopes/preferences/
  accounts/distros/original config/shortcut/full backup/defaults/startup remain, absent geometry
  stays absent, singleton0/old proxies0. See ADR0041. SET-02 remains partial for OS sidebar metrics
  and physical display acceptance; XY/display-home/DPI and full summon remain separate.
  ACC-03 is partial for missing token creation/stored-empty Verify; ACC-09 already reads current
  browser draft at click without new live-click qualification. SET-11 fresh/missing120 and legacy
  omitted60 are deliberate; per-account repositories still differ from Mac's deck-wide/Actions-off
  watchlist. Provider applicability is not shipped/qualified by this package. SET-08/updater install/
  notes/native Mac/x64/live identities/phone/physical input/accessibility/display/shell/signing/
  clean-machine/full migration remain open.
