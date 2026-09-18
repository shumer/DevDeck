# Architecture

## Layers

```
DevDeckApp     AppKit shell - windows, menu bar, placement, settings
    │              depends on everything below
DevDeckUI      SwiftUI cards - pure rendering of a CardState
    │
GitHubKit      one integration: GraphQL documents, models, services
GitLabKit      one integration: accounts per host, the merge requests query
ArcKit         one integration: projects, link templates, local Fusion stack
DDEVKit        one integration: projects, ddev list, .ddev/config.yaml
ProjectKit     one integration: plain projects - folder probe, detached start, health check
    │
DevDeckCore    no AppKit, no integration specifics: config, HTTP, tokens, code identity,
               policies, command runner, the Docker probe, the update check
    │
KeychainACL    C shim for the one deprecated Keychain call Swift cannot silence
```

The rule that keeps this honest: **`DevDeckCore` and every integration module must build and
be testable without AppKit**. The suite is a plain executable running head-less, so anything
that reaches for a window cannot be covered by it.

## Data flow

```
DeckController (@MainActor)
   ├─ owns CardState<…> for each card, and one RefreshSource per remote card
   ├─ refresh loop: RefreshCycle.run(sources) → sleep(pass.delay)
   │     RefreshCycle asks each active source in order, keeps the one failure counter
   │     the deck shares, and turns it into a wait through RefreshPolicy
   └─ knows which cards are active; a hidden card is never fetched

GitHubWorkspace  ── one GitHubClient per configured account, fanned out concurrently
   └─ PullRequestsService / NotificationsService / ActionsService
                        → GitHubClient → APITransport → HTTPClient → URLSession
                                          │
                                          ├─ HTTPCache: ETag / If-None-Match, 304 handling
                                          ├─ RateLimit: parses x-ratelimit-* headers
                                          └─ RetryPolicy: backoff for 5xx and transport faults
```

`CardState` keeps the last good value across failures on purpose. A panel showing a slightly
old number with a visible staleness marker beats a panel that blanks itself whenever the
network hiccups.

## Arc projects and the local stack

An `ArcProject` is a card: an organisation, a set of link templates, a browser, a folder and
the commands that run in it. Projects are stored as a list, and each one contributes a
`CardDescriptor` with the identifier `arc.project.<id>` through `CardCatalog.all(including:)`.
Everything downstream - the layout merge, the menu, the panel sizing - works against that
merged catalog, so adding a project in settings creates a card with no code change.

`LocalStackService` answers "is it running" by requesting the project's health URL rather than
inspecting processes, and runs its commands through `ShellCommandRunner`. Both decisions, and
why the obvious alternatives are wrong, are in [adr/0005-local-stack.md](adr/0005-local-stack.md).

Local status polls on its own 10-second loop in `DeckController`, separate from the API
refresh: a stack that just came up should appear within seconds, and the probe is local and
cheap. A project mid-command is skipped by the poll so the card cannot flicker back to
"stopped" during a restart.

**Commands run with the `PATH` a terminal has.** `zsh -lc` is a login shell but not an
interactive one, so it reads `.zprofile` and never `.zshrc` - which is where nvm, rbenv and
pyenv install themselves. The symptom is as confusing as symptoms get: `ddev` and `docker` work,
because they are in `/usr/local/bin` and come from `/etc/paths`, while `npx` reports "command
not found" from a machine that plainly has it. `ShellPath` asks an interactive login shell for
its `PATH` once per launch, finds the answer by a printed marker - an interactive profile prints
things, this one prints `exec zsh` - and every command afterwards runs non-interactively with
that `PATH` in its environment. Running everything interactively would also work, and would put
that banner in the middle of output something is parsing.

**One bad answer is not news.** A poll asked every couple of minutes comes back wrong every so
often: the daemon misses a `docker version` while it is busy, `ddev list` is slow while a project
starts, an engine drops a request as it reloads. Left alone the card flips to "stopped" or
"Docker is not running" and is right again seconds later, which watched for an hour reads as a
deck that lies. `StateSettler` holds a *worse* answer back until it has been given twice, and
lets a better one through at once. Pressing a button resets it, because a decision is not a
hiccup and a stop must show immediately.

**A command's outcome is verified, not assumed.** `fusion daemon` returns before the engine
serves and `fusion stop` returns before the containers are down, so both are followed by a wait
- `waitUntilRunning` and `waitUntilStopped`. The second one matters more than it looks: without
it a stop that quietly did nothing was repainted green by the next poll, as though the button
had never been pressed. Now the card stays on "running" and says why.

**A tray reads, it does not tail.** `LogTail` in `DevDeckCore` turns whatever a project prints
into the six lines a card can hold: escapes stripped, blanks dropped, carriage returns treated as
line breaks so progress output is not one ribbon, and a file read from its last 64KB rather than
from the start. Each kit says where its lines come from - `LocalStackService.logs()` through
`docker logs` on the containers carrying the compose label, `DDEVEnvironment.logs(for:)` through
the CLI, `LocalProjectService.logs()` straight off the file a detached start writes - and all
three return the same `LogLines`. The controller reads only the trays that are open, on the
regular pass and once more when an action settles; a closed tray runs no commands at all. The
switch lives in the card header rather than the control row because four buttons already need
more width than the row has.

**A command speaks while it runs.** `CommandRunning.run` takes an `onOutput` closure and
`ShellCommandRunner` drains both pipes a line at a time - splitting on carriage returns too,
since compose draws its progress with them - so the newest line reaches the card before the
process exits. A Fusion start takes a minute; with nothing shown in between, a card that says
`starting…` and then `stopped` is indistinguishable from a button that did nothing. The line
takes the meta slot on the card while the command runs, and the run's `failureLine` is passed
into `waitUntilRunning` as a hint: `fusion daemon` prints "ports are not available … address
already in use", brings up four of ten containers and then **exits zero**, so the failure lives
in what it said and not in how it ended. Without carrying that line the card could only report
the silence, never its cause.

## Local project cards

Arc, DDEV and plain project cards are the same shape and are built from the same pieces -
`CardHeroRow`, `CardMetaBlock`, `ProjectChipRow`, `CardActionRow` in `DevDeckUI`, framed by
`CardChrome`. Anything that looks like a card of a local project belongs there rather than in
one card's file: two copies of the same layout drift, and this project has already watched that
happen once.

The hierarchy - one hero, everything else quiet - is [adr/0009-card-hierarchy.md](adr/0009-card-hierarchy.md).
Two consequences show up in the code. `ProjectCardMetrics.height` is the only place a card's
height is computed, for all three of them. And because the chips now wrap, that height depends
on how many lines they take: `CardChipFlow` measures the labels in the real font and breaks
lines by the same rule `CardChipLayout` uses when it draws them. The two agreeing is what stops
a card clipping its own control row.

`DDEVEnvironment` differs from `LocalStackService` in one structural way - it is shared rather
than per project, because `ddev list -j` answers for every project at once. See
[adr/0006-ddev-projects.md](adr/0006-ddev-projects.md).

`LocalProjectService` is the third of them, for projects nothing else describes. Its one
structural difference is that it has to launch a command that may never return, so it keeps a
log file and a process id per project under Application Support - see
[adr/0007-plain-projects.md](adr/0007-plain-projects.md). Everything else is the same shape:
the health URL decides "running", and the branch comes from `.git/HEAD`.

## The Docker gate

`DockerEnvironment` in `DevDeckCore` runs one probe for the whole deck at the top of the local
loop, and `DeckController` publishes the result. Cards do not fetch it; they are handed a
`DockerStatus` and ask `DockerGate` what to draw, so the wording and the colours cannot drift
between Arc, DDEV and plain cards.

Two states carry weight beyond "not running". `unknown` means nothing has been asked yet and
must not gate anything, or the first poll of every launch greys out every button. `starting` is
set locally when the Start Docker button launches the runtime, and survives up to three minutes
of probes that still say "no" - Docker Desktop takes the better part of a minute, and flipping
back in between is what makes a button look broken. See
[adr/0008-docker-precondition.md](adr/0008-docker-precondition.md).

## Cards

A card is three things:

1. a `CardDescriptor` in `CardCatalog` - identifier, title, whether it is implemented;
2. a branch in `CardHostView` - the SwiftUI view and the panel size;
3. whatever data it needs, added to `DeckController`.

`CardLayout` holds one thing: which cards are on. **The order belongs to the catalog** - the
built-in cards, then Arc projects, then DDEV, then the plain ones, each group alphabetical, via
`CardCatalog.projectOrder`. It used to come from the stored settings, where a card was appended
the first time it was switched on; the deck therefore sat in the sequence the projects happened
to be added in, and "Tidy panels" faithfully reproduced that sequence - which read as scrambling
rather than tidying.

The layout is merged with the catalog on every read, so:

- a card added in a newer build appears with its default visibility instead of vanishing;
- an identifier removed from the catalog is dropped from the user's list silently;
- a card that is enabled but not implemented never renders - `visibleCards()` filters it.

Card identifiers are persisted strings (`github.pullRequests`). **They must never change.**

## Accounts

`GitHubAccount` is one identity with one token: a slug id, a label, a base URL, the
organisations it covers, and an enabled flag. `GitHubAccountsStore` persists the list; the
token lives in the Keychain under the account's own key.

`GitHubWorkspace` fans a card's fetch out over every enabled account and merges the results.
The rule everywhere: **a card fails only when every account fails.** A partial failure is
carried on the snapshot as `[AccountFailure]` and drawn in the footer of the list cards, because blanking a
card over one expired token is how a deck stops being trusted.

Two details worth keeping in mind when adding a card:

- Every model carries `accountID`. Cross-account work needs it - the Actions card groups
  repositories by account, since asking every account about every repository would spend most
  of its requests on 404s.
- Cache keys are per account (`github.notifications.<account>`). Two accounts polling the same
  endpoint with different tokens would otherwise share one `ETag` and serve each other's data.

The first account keeps the un-suffixed Keychain key, so a token stored before accounts
existed keeps working with no migration.

## Opening links

`BrowserChoice` (a bundle identifier plus an optional Chromium `--profile-directory`) hangs off
the account; `LinkOpener` in the app target does the opening. Chromium only reads
`--profile-directory` at launch and routes the request to its running process itself, so the
open is issued with `createsNewApplicationInstance` - the API equivalent of `open -na … --args`.
Anything that fails, or a browser that has since been uninstalled, falls back to the system
default rather than doing nothing.

`ChromiumProfiles.parse(localState:)` lives in `DevDeckCore` so the suite can cover it; the app
supplies the bytes from `~/Library/Application Support/<browser>/Local State`.

## Legibility on glass

Panels are a blur over the wallpaper, and `NSVisualEffectView` takes its brightness from
whatever is behind it - so over a bright desktop the palette's near-white text turns to mush.
Three things keep the surface honest, and they work together:

- the window is pinned to `darkAqua`, so the `hudWindow` material stays dark whatever the system
  appearance is doing;
- a veil of `black` at 30% sits between the blur and the content;
- a 1-point white hairline at 16% gives the panel an edge over a busy wallpaper.

The veil is the only dial on this surface, and it has been set twice from opposite complaints.
At 42% it is enough black to stop being glass and start being grey paint, which is how the cards
read next to the sibling widget. At 22% each panel takes the colour of whatever is behind it, so
on a wallpaper with dark trunks on one side and sunlight on the other, six panels looked like
six different materials. 30% keeps the desktop's colour and keeps the panels agreeing with each
other. Contrast is a property of the surface, not something to chase by nudging text colours per
card - but neither is it something to buy by draining the colour out of it.

`DeckTheme`'s three state colours are that widget's values to the digit. Two decks side by side
with greens a shade apart look like a mistake rather than a decision.

## The brand marks

Each card's title carries the logo of what it is about, and those are the real logos: `BrandMark`
holds the `d` attributes from the vendors' own SVGs, and `SVGPath` parses them into a `Path` at
draw time - full command set, including elliptical arcs, because Docker's whale and DDEV's mark
use them. This is what an asset catalog would normally do, and this toolchain has none.

The first attempt approximated the marks with circles and triangles and looked exactly like
that, which is why the parser is worth its hundred lines. The suite checks every mark parses,
lands inside the box it was given, and is not a speck in the corner of it - a logo that silently
comes out empty looks, on a card, identical to one that was never added.

`swift run GlyphPreview out.png` draws the lot at 15 points and blown up, on the glass they
sit on, which is the only way to tell a mark that fills correctly from one whose
knocked-out letter has gone solid.

Two of them do not wear their own colour. GitHub's octocat is black and Next's disc is black,
and black on dark glass is a hole rather than a logo, so both go white - which is what both
vendors do on a dark background themselves. Which mark a plain project gets is `ProjectKind`,
matching whole words in the start command and the caption, framework ahead of runtime: see
[adr/0014-monorepos-and-marks.md](adr/0014-monorepos-and-marks.md).

## Card sizing

`CardMetrics` in `DevDeckCore` owns the row-count and height arithmetic, because two places
have to agree on it exactly: the SwiftUI card drawing the rows and the AppKit panel being
resized around them. A disagreement shows up as a clipped last row or a strip of empty glass.

Expansion state lives on `DeckController` and is published, so `PanelCoordinator.syncPanelSizes()`
resizes the window whenever either the data or the expansion changes - keeping the top edge
fixed and shifting the rest of the column out of the way.

## Placement

`DisplayMode` lives in `DevDeckCore` so it can be persisted and tested; the app maps it to an
`NSWindow.Level`:

- `.desktop` → level `-1`: below every application window, above the wallpaper. The real
  desktop levels are unusable - the WindowManager surface sits far below and would bury the
  panels.
- `.floating` → `.floating`.

Locking sets `isMovableByWindowBackground = false`.

**The deck moves a card only when it was asked to.** A card growing because its data arrived is
the deck settling, and nothing moves for it; a card growing because somebody collapsed it, opened
its log or expanded its list is a request to make room, and `shiftColumn` runs. `DeckController`
records which of the two happened and hands the set over once per pass. Two rules keep the
settling quiet: a card that has never had data keeps the height it last settled at rather than
computing the height of an empty one, and the collapsed set is read before any panel is built so a
panel is created at the size it will be. A resize never writes a position, since it keeps the top
edge. `Preferences.packsColumns`, off by default, adds `DeckLayout.pack`: same column, same
on-screen order, anchored at the top card, never moving a card to another column and never
sorting, which is what separates it from `tidy`. Why all of this, with the measurements:
[adr/0012-automatic-movement.md](adr/0012-automatic-movement.md).

**The menu-bar glyph is code, the application icon is artwork.** There is no asset catalog here
and no Xcode to build one, so the application icon lives in `Resources/AppIcon` as an iconset,
every size drawn at that size rather than resampled from the largest, with the SVG and the
geometry beside it; `build.sh` packs it with `iconutil`. `DeckIcon` draws
the menu-bar glyph and its four states: calm, a ring for stuck work, a dot for something to fix, a
red dot for a person waiting. All but the red one are real template images so the menu bar tints
them; the one carrying red cannot be, so it draws itself in `labelColor`, which resolves against
the appearance drawing it - a menu-bar icon painted in plain black is invisible on a dark bar.
Which state is showing comes from the attention digest's most urgent tier. See
[Attention](#attention).

**Deciding whether to interrupt somebody is the feature; posting the banner is four lines.**
`NotificationDigest` in `DevDeckCore` holds the rules and is where the tests are: the first
answer after a launch is never announced, nothing is announced twice, what was *seen* is
remembered rather than only what was said, and three at once become one summary that counts them
by kind and names the first two. The attention builders turn the same facts that make the menu's
rows into `DeckAlert`s, so a banner and a row cannot disagree, and a stuck item carries its state
in its identity - broken, fixed and broken again is news twice. An alert has a title for what
happened, a subtitle for where, a body for what a click does, a target (a page, a card, an
account's form, or the menu) and whether it is quiet: only a person waiting on you makes a sound. `Notifier` in the app is the only part that talks to
`UNUserNotificationCenter`, asks for permission at the moment the switch is turned on rather than
at launch, and opens what a clicked banner is about: a page in the browser profile of the account
that owns it, a project's card with its log, an account's form, or the menu. Whether
a given alert is wanted is a property of the account it came from, per kind, because one token is
your own work and another is a customer's, and of the project it is about, stored as the
exceptions so a project added later is covered without asking. The mark on the banner comes from
`NotificationArtwork`, which draws the source's mark, a service, Arc, DDEV or Docker, onto a dark
tile in the caches directory:
macOS puts the application icon on every notification and will not be talked out of it, and an
attachment is the only place left to say who is asking.

**Summoning is a window level, not a mode.** The cards were never the problem; being underneath
everything was. So the shortcut raises the same panels, with the same frames and the same
rendering, from level -1 to `.floating`, and puts them back on key up. There is no second layout,
no centred overlay and no second copy of a card, because a summon that rearranges the deck has to
put it back afterwards and that is where this kind of feature goes wrong. The one thing it does
add is `VeilWindow`, one borderless window per display at level 2 holding black at 45%: dark glass
takes the colour of what is behind it, and over a white editor the cards wash out. `GlobalHotKey`
is Carbon's `RegisterEventHotKey` rather than `NSEvent.addGlobalMonitorForEvents`, for two
reasons: a global key monitor needs the Input Monitoring permission, and only Carbon reports the
key going up, which is what makes holding possible at all.

**A move the deck makes is not a move the user made.** AppKit posts `windowDidMove` for
programmatic moves as well as dragged ones, so every time the deck repositioned itself - growing
a card, closing a gap, putting panels back after a display change - it saved that as though
somebody had arranged it. `isRepositioning` wraps those moves and keeps the notification quiet.
The other half of the same rule is `PanelPlacement.shouldRecord`: a card parked on a borrowed
display keeps the placement it already has, so unplugging a monitor for an hour does not make the
deck move house, **unless the user moved it there themselves**. Dragging a parked card or tidying
the deck while its own monitor is unplugged is a decision and outranks the placement it replaces.
Without that exception the arrangement was dropped on the floor and the next screen change hauled
every card back to where it had been parked - which, on a smaller screen, is the bottom edge,
because offsets that do not fit are clamped there.

**The panels act on the first click.** `PanelHostingView` overrides `acceptsFirstMouse`, because
AppKit's default - a click on an inactive window activates the app and goes no further - is
exactly wrong here. These panels live *behind* other windows and are never frontmost, so without
it every button needs pressing twice and the first press looks like a button that does nothing.

Two details keep a deck stable across launches, and both were bugs first:

- **Positions anchor on the top-left corner**, not AppKit's bottom-left origin. Cards change
  height as their data arrives, so a card restored at its stored bottom starts with its top
  lower than the user left it and then grows downwards from there.
- **A panel opens at the height it last settled at**, remembered per card, and a shift caused
  by a card growing is never persisted. Without the first, every launch began with a short
  panel that shoved the column down as it filled; without the second, that shove was saved and
  the deck crept apart a little further each time.

**A position names its display.** `PanelPlacement` is a display UUID plus an offset from that
display's top-left corner, and `Displays` maps it onto the screens attached right now. macOS
lays every screen out in one coordinate space and re-lays it whenever a display comes or goes,
so a global point that meant "top left of the laptop screen" means somewhere else - often
off every screen - the moment the external display that happens to be the main one is unplugged.

A card whose display is absent is *parked*: the same offset applied to the main screen, clamped
back inside it, with the stored placement left untouched so the card goes home when its display
returns. `persistPosition` refuses to overwrite a placement while it is parked, because parking
is not a decision the user made. `NSApplication.didChangeScreenParametersNotification` triggers
a re-place of the whole deck, after a beat - a display that has just woken reports its old frame
for a moment.

The identity is `CGDisplayCreateUUIDFromDisplayID`, not the display id and not the screen index:
ids are handed out per connection and change on a replug, and the index changes with the
arrangement. The UUID belongs to the physical display, which is what "keep this on the laptop
screen" means.

A saved position is only used when the frame still overlaps a screen by at least 80×40 points,
so a panel can never come back 99% off-screen.

**Tidying wraps into columns.** `DeckLayout.tidy` in `DevDeckCore` returns the top-left corner
for each panel: down from the anchor, and into a new column beside it as soon as the next panel
would hang below the visible frame. It is arithmetic in the core rather than a loop in the
delegate because it decides whether a panel ends up somewhere the mouse can reach - six cards
are over a thousand points tall, and a single column buried the last of them under the bottom
edge and then saved that position. The column grows towards whichever side of the anchor has
more room, and a new column is clamped inside the screen: overlapping panels can be dragged
apart, off-screen ones cannot.

## The application layer

`DevDeckApp` is the only module that touches AppKit. `AppDelegate` is its composition root:
it builds the stores and the objects below, wires the events between them, and does nothing
itself that one of them could do.

- `DeckController` owns the data every panel renders and the two loops that keep it fresh: the
  API loop, which hands its sources to `RefreshCycle` and sleeps for what it is told, and a
  faster local loop for Docker, stacks and projects. The parts of it that decide rather than
  fetch live where the suite can reach them: `RefreshCycle` and `ProjectWatch` in Core,
  `ActionsWatchList` and `GitHubAttention` in GitHubKit, `DeckAttention` in the UI module. See
  [Attention](#attention).
- The modules, one per kind of card, under `Modules/`: `PullRequestsModule`, `InboxModule`,
  `ActionsModule`, `MergeRequestsModule`, `WorkInFlightModule`, `ArcProjectModule`,
  `DDEVProjectModule` and `LocalProjectModule`. A `CardModule` says which cards it owns and
  gives their view, size, dashboard, catalog entries and menu group. The project modules are
  also their kind's `SettingsSection`; the two account sections, GitHub and GitLab, live in the
  same files as the cards they feed. `CardHostView` and `DeckCards` ask the modules and know no
  kind by name.
- `DeckCards` is the card list: the built-in cards plus whatever the modules add, in module
  order, and which of them are switched on.
- `PanelCoordinator` owns the windows: which cards have one, how big each is, and where it
  sits. The two rules it exists to keep are stated on `persistPosition` and `syncPanelSizes`: a
  position is written down only when a person chose it, and the deck settling into its data is
  not a layout event. See [Placement](#placement).
- `DeckMenu` owns the menu-bar item and every menu, all filled in as they open.
- `ArrangementsController` owns saved decks: naming one, applying one, offering them.
- `Summoner` owns the key that raises the deck, the tap-to-latch rule, the veils, and the click
  or Esc that puts back a deck raised from the menu or a banner; what
  "raised" does to the panels is the coordinator's.
- `Updater` asks GitHub for the latest release and, when told to, installs it: download,
  `ditto`, a check of the unpacked bundle, the old copy to the Trash, the new one in its place,
  relaunch. What counts as an update and whether the unpacked bundle is trusted is
  `UpdateCheck` in Core, under tests. See [adr/0016-self-update.md](adr/0016-self-update.md).
- `SettingsWindowController` owns the settings window, its sidebar and the form column. The
  four pages at the top are `SettingsPage`s; each kind of account or project is a
  `SettingsSection`. See [The settings window](#the-settings-window).

All of them are `@MainActor`. The panels themselves are `PanelWindow`, a borderless `NSWindow`
hosting `CardHostView`, which is the one place that maps a card identifier onto its SwiftUI
view and its size.

## Attention

What the menu-bar badge, the menu's rows and the banners say all comes from one place, so they
cannot disagree about what needs you. See [adr/0019-attention-in-tiers.md](adr/0019-attention-in-tiers.md).

- **`AttentionItem`** in Core is one thing that wants a person: a tier, a mark, a title that
  says what happened to what, a subtitle with where and who, when it started, and what choosing
  it does. **`AttentionDigest`** deduplicates by id, sorts by tier and age, cuts sections to three
  rows with the rest in a submenu, and counts for the tooltip.
- **The tiers** are `waiting`, `needsFixing`, `stuck` and `goodToKnow`, in the order the menu
  lists them. The icon wears the most urgent tier that lights it: a red dot, a dot in the bar's
  ink, a ring. Good to know never lights it.
- **Builders per source**, pure and under tests: `GitHubAttention` for pull requests, the inbox
  and Actions, `GitLabAttention` for merge requests, `AccountAttention` for accounts that could
  not be read, `ProjectAttention` for the projects on this Mac and Docker, `CheckoutAttention`
  for work only on this Mac, `UpdateAttention` for a new version. Each also builds the banners for
  the same facts, as `DeckAlert`s.
- **`ProjectWatch`** remembers what a card stops saying a poll later: that a project was running
  and nobody pressed Stop, why a start failed, since when a health check has been silent. It is
  fed only what `StateSettler` let through and what a button did, and reports nothing about the
  state a launch found.
- **`DeckAttention.digest`** in the UI module puts it together from the controller's state, one
  input struct, so the suite checks what lights the icon without a controller. A hidden card
  contributes nothing.
- **`AccountFailure`** carries its kind, rejected, forbidden, rate limited, unreachable or other,
  and a card whose every account failed throws `APIError.accounts` with them whole, so the menu
  says which account and what to do rather than "Forbidden".

The controller keeps the history (`ProjectWatch`, when Docker went down, when each account
started failing) and announces per channel through `NotificationDigest`, which keeps the rule
that the first answer after a launch is never news. `DeckMenu` renders the digest as native menu
items: section headers, a subtitle under each row (a tooltip before macOS 14.4), the age as a
badge, ⌥ twins for Dismiss and Mark as Read.

## The settings window

A sidebar and a form column, built the way System Settings is built: an `NSSplitViewController`
whose first item is a real sidebar item, so the sidebar is translucent and runs the full height of
the window, and a toolbar, which is what gives the window the standard title bar. The two panes
apply their own top inset, because a window that draws its content full height reports no safe
area to the views inside a split item.

```
sidebar                     form column (stretches, 440 to 760 points)
⌕ Search                    [mark] agrica-qdd                 Show on deck ●
⚙ General                   Start
▦ Deck                      ┌ Folder         [~/Projects/…   ] [Choose…] ┐
▤ Cards                     │ Start command  [bun run dev    ] [Detect ] │
◉ Notifications             │ Long-running command                   ●  │
Accounts                    └───────────────────────────────────────────┘
  GitHub, GitLab, Notified  Health check (?)
Projects                    ┌ Check URL …  ● Running  answered at …  [Check Now] ┐
  agrica-qdd  ●             Links …
  Governance                › Advanced  Name, caption, stop command, Docker, browser
[+ ⌄] [−]
```

**Four pages, then accounts, then projects.** General, Deck, Cards and Notifications are
`SettingsPage`s. Accounts of both services sit under one heading and projects of every kind under
another, alphabetical, because a person looks for a project by its name, not by its tooling. Each
kind is still its own `SettingsSection`, which fills its rows and its form and adds and removes
its own things; the window knows no kind by name. The `+` menu lists the kinds.

**A row's dot means something or is absent.** On a project it is the live state from the deck,
green running, orange starting; on an account, orange when there is no token. A thing that is not
on the deck is dimmed. Every row used to wear a green dot meaning "enabled", which is the opposite
of what green means everywhere else in the app.

**Forms are built by `SettingsForm`**, with four row shapes: `settingRow` (a title, an optional
one-sentence subtitle, a control at the trailing edge), `fieldRow` (a label in a 130-point column
and fields to the edge), `statusRow` (a dot, a state and a detail, updated in place) and `linkRow`
(a toggle, a tag in the card's colours, an address, an open button). Above them `pageHeader`,
`section` with an optional help button, `footnote` of one line, `textButton` and `disclosure` for
Advanced. The column has a fixed width, so the form is never rebuilt on a resize, which is what
used to throw away whatever field had focus.

**An answer goes where the question was asked.** A health check or a token check updates its
status row in place. A button's answer, Detect or Test, appears in a popover at that button
(`ButtonAnswer`). Nothing reserves an empty line for an answer that may never come, and nothing
says "Saved.": settings apply as they change, and on a Mac that needs no announcement.

**An answer is only shown next to the address it answered for.** `CheckSummary` in Core, built
by `LocalProjectStatus.summary` and `LocalStackStatus.summary`, drops a result whose address has
since changed, and a change of address, folder or command starts a new check.

**The form is rebuilt only for a change of shape**: a link added, a fold opened. Before it is,
the edit in progress is ended, which is what saves it. Answers arriving and live state changing
touch a row or the sidebar, never the form.

"Settings for This Card…" on a card's right-click menu opens its own form, through
`CardModule.settingsTarget`; `open -a DevDeck --args --settings project agrica-qdd` does the same
from a terminal. See [adr/0018-settings-like-system-settings.md](adr/0018-settings-like-system-settings.md).

## Concurrency

Every target except `DevDeckUI`, `DevDeckApp` and the two render tools (`IconPreview`,
`GlyphPreview`) builds in Swift 6 language mode with strict concurrency. Those
build in Swift 5 mode - see
[adr/0002-spm-only-toolchain.md](adr/0002-spm-only-toolchain.md).

Shared mutable state uses actors (`HTTPCache`, `APITransport`, `FakeHTTPClient`) rather than
locks: `NSLock` is unavailable from async contexts under strict concurrency.

## Secrets

Tokens live in the login Keychain and nowhere else - not in the repository, not in
`UserDefaults`, not in a dotfile. `CompositeTokenStore` reads Keychain first, then the
environment, so a stale `GITHUB_TOKEN` export cannot shadow the token set in Settings.

How an item is protected follows from the signature the app finds itself under.
`CodeIdentity.current()` asks the running process; `KeychainAccessPolicy` turns the answer into
a mode: an ad-hoc build writes the open access list, because binding to a signature that
changes every build costs a prompt per token per update, and a signed build lets the Keychain
bind the item to the application. The mode is remembered, and the first launch under a
different signature rewrites the items once, but never from a bound mode down to the open one: a
copy without an identity leaves bound tokens bound, and a token it saves gets the default access
list rather than the open one (`KeychainAccessPolicy.opensAccess(for:storedMode:)`). If a prompt is dismissed during a rewrite,
the mode is not recorded and the next launch tries again. The same identity is what the updater compares a
downloaded build against. See [adr/0017-signature-decides.md](adr/0017-signature-decides.md).

## Adding a card

1. Add a `CardDescriptor` to `CardCatalog` with `isImplemented: false`.
2. Build the integration in its own module (or extend `GitHubKit`), with tests.
3. Add the state to `DeckController` and a `RefreshSource` for it; the cycle only asks it
   while the card is active.
4. Write the SwiftUI card in `DevDeckUI` against a `CardState<…>`.
5. Write a `CardModule` under `DevDeckApp/Modules` that owns the identifier and returns the
   view, the size and the dashboard, add it to the list in `AppDelegate`, and flip
   `isImplemented`. A kind with things to configure is a `SettingsSection` too, and goes in
   the settings window's list in the same place.
6. If the card can need somebody, give it an attention builder next to its model, returning
   `AttentionItem`s and the `DeckAlert`s for the same facts, add it to `DeckAttention.digest`,
   and test the wording. See [Attention](#attention).
7. Update `README.md`, this file and `docs/roadmap.md`.

What is still per kind by name is inside `DeckController`: the status dictionaries, the local
refresh loop and the three `perform` functions. That is the data plumbing, and it is the next
thing to move if a fourth kind of project ever arrives.
