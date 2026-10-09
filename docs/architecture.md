# Architecture

## Layers

```
DevDeckApp     AppKit shell - windows, menu bar, placement, settings
    │              depends on everything below
DevDeckUI      SwiftUI cards - pure rendering of a CardState
    │
DevDeckEngine  DeckRuntime - what the deck knows and decides, on every platform;
    │              protocol v2, portable card models, intents and event stream
GitHubKit      one integration: GraphQL documents, models, services
GitLabKit      one integration: accounts per host, the merge requests query
ArcKit         one integration: projects, link templates, local Fusion stack
DDEVKit        one integration: projects, ddev list, .ddev/config.yaml
ProjectKit     one integration: plain projects - folder probe, detached start, health check
    │
DevDeckCore    no AppKit, no integration specifics: config, HTTP, tokens, code identity,
               policies, command runner, the Docker probe, the update check, the words
               every layer above reads through `L` and `LN`
    │
KeychainACL    C shim for the one deprecated Keychain call Swift cannot silence
```

The rule that keeps this honest: **`DevDeckCore` and every integration module must build and
be testable without AppKit**. The suite is a plain executable running head-less, so anything
that reaches for a window cannot be covered by it.

## Engine protocol

`DevDeckEngine` is the portable boundary between platform shells and deck behaviour. The Mac
app links it and calls `DeckRuntime` directly. A shell in another process talks to `DeckSession`,
which wraps the same runtime, over protocol v2: JSON Lines, intents in (displays, sizes, moves,
log windows, and clicks as the commands the events carried), events out (card models and their
menus, the tray status and menu, panel changes, log lines, banners and effects).
`DevDeckEngineHost` exposes that stream over standard input and standard output, so a shell can
restart without taking a project down. The contract is [engine-protocol.md](engine-protocol.md);
the decision is [adr/0033-protocol-on-the-runtime.md](adr/0033-protocol-on-the-runtime.md).

`DevDeckEngineTests` compare two kinds of golden transcripts byte for byte with the committed
files:

- the runtime's, `Tests/EngineTests/RuntimeGolden.swift`: every card's model before and after a
  pass, folded and expanded; the menu-bar menu, a card's menu and the status; the banners over
  two passes and a summary; and placement through an unplugged monitor and back;
- the protocol's, `Tests/EngineTests/SessionGolden.swift`: a session driven by intent lines as a
  shell writes them, in English and Russian, with every event it sends back;

One JSON object per line, sorted keys, clocks in UTC, every input fixed. The same bytes on the
Mac and on Windows are what keeps two shells drawing one deck; a change that alters them is
regenerated on purpose (see development.md) and the diff read.

## The deck runtime

`DeckRuntime` holds the data every card renders and the two loops that keep it fresh, and it
makes every decision about them: when to poll, what a failed poll means, what a button does to a
card, what is worth a banner, what is folded, parked or expanded. It lives in `DevDeckEngine`, so
it builds on Windows, and on the main actor, so a shell that folds a card reads the folded state
on the next line ([adr/0025-the-deck-runtime-on-the-main-actor.md](adr/0025-the-deck-runtime-on-the-main-actor.md)).

It talks to a shell in two ways. `onChange` names every stored field that was assigned,
including an assignment that left it equal, because that is what `@Published` did and what the
Mac's subscriptions rely on. `onEffect` carries what only the platform can do: post banners,
open or close a log window, launch Docker Desktop, redraw the menu-bar item. Time, sleeping, the
local address and the HTTP client come in at `init`, which is what lets `DeckRuntimeTests` run
it without a network, a clock or a shell.

On the Mac, `DeckController` is now an adapter: it mirrors each field into the same
`@Published` property, forwards every call, and carries out the effects with AppKit. It decides
nothing, and a line in it that does is in the wrong place.

## Data flow

```
DeckRuntime (@MainActor, in DevDeckEngine; DeckController mirrors it for SwiftUI)
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

**An answer is not enough on its own.** Fusion writes the same container names in every
checkout - `fusion-engine`, `fusion-cli-api` and the rest - so only one Arc stack can run on a
machine, and two checkouts serving on the same port out of their own `.env` cannot both be up.
The card used to call the health answer "running" whoever gave it, and sat green over a project
whose stack had never started. So when the answer arrives and `docker ps` shows no container
whose compose working directory is inside this checkout, the port is looked up in the same
listing: a container from another checkout holding it means this project is stopped, and the
card says whose stack answered (`LocalStackService.stackHolding(port:in:folder:)`). With nothing
publishing the port at all the answer stands, which is what keeps a stack started by hand in a
terminal counted as running. `scripts/check-arc-stack.sh` prints the same three facts for every
configured project, for a card that still disagrees with the person looking at it.

Local status polls on its own 10-second loop in `DeckRuntime`, separate from the API
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

**A log is read, not tailed.** `LogTail` in `DevDeckCore` turns whatever a project prints into
lines something can show: escapes stripped, blanks dropped, carriage returns treated as line
breaks so progress output is not one ribbon, and a file read from its last chunk rather than from
the start. Each kit says where its lines come from - `LocalStackService.logs(limit:)` through
`docker logs` on the containers carrying the compose label, `DDEVEnvironment.logs(for:limit:)`
through the CLI, `LocalProjectService.logs(limit:)` straight off the file a detached start writes
- and all three return the same `LogLines`. The limit is what tells them who is asking: six lines
for a card, `LogTail.windowLineLimit` for a window, which also reads more of the file.

**The log itself is a window.** `LogWindowController` opens one per project, dark, monospaced,
selectable, with ⌘F through the Edit menu's Find items, a footer that says where the lines come
from, a Follow switch and a button that opens the file. It re-reads every two seconds while it is
visible and nothing at all while it is behind another window or minimised. `DeckRuntime` keeps
`logWindowCards` and `logTails`; the window subscribes to the second, so what it shows and what
the deck knows cannot disagree, and the card's header button is lit from the first. Closing the
window, by its own button or ⌘W, tells the controller, which drops the lines and stops reading.
See [adr/0021-the-log-is-a-window.md](adr/0021-the-log-is-a-window.md).

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

Arc, DDEV and plain project cards are one model, `DeckProjectCardModel`, with a builder per
kind, drawn by one `ProjectCard` from `CardHeroRow`, `CardMetaBlock`, `ProjectChipRow` and
`CardActionRow`, framed by `CardChrome`. What a project card says is changed once, in the
builder for its kind or in what they share, rather than in three views: two copies of the same
layout drift, and this project has already watched that happen once.

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

How the process is started, found again and stopped is not the service's business: it asks a
`ProjectProcessLauncher`. The Mac has one, `ShellProjectLauncher`; Windows has one for projects
inside WSL and one for projects in Windows folders. Each one keeps its process alive when the app
quits and stops the whole tree, not just the process it recorded - see
[adr/0023-project-process-lifetime.md](adr/0023-project-process-lifetime.md).

**Stop reaches only what the deck holds.** The health URL answers for a server whoever started
it, so a project started in a terminal reads as running, and DevDeck has no process and often no
stop command for it. `DeckRuntime.stopBlock` decides that as the status is read and hands it to the
card on `LocalProjectStatus.stopBlock`: `startedElsewhere` for a command that holds its process,
`noStopCommand` for one that returns. Stop and Restart then run nothing and go to `ProjectWatch` as
`cannotStop`, so the menu says DevDeck cannot stop it rather than that a stop did not work. Nothing
is ever stopped by port or by name - see
[adr/0026-stop-only-what-the-deck-holds.md](adr/0026-stop-only-what-the-deck-holds.md).

## The Docker gate

`DockerEnvironment` in `DevDeckCore` runs one probe for the whole deck at the top of the local
loop, and `DeckRuntime` publishes the result. Cards do not fetch it; they are handed a
`DockerStatus` and ask `DockerGate` what to draw, so the wording and the colours cannot drift
between Arc, DDEV and plain cards.

Two states carry weight beyond "not running". `unknown` means nothing has been asked yet and
must not gate anything, or the first poll of every launch greys out every button. `starting` is
set locally when the Start Docker button launches the runtime, and survives up to three minutes
of probes that still say "no" - Docker Desktop takes the better part of a minute, and flipping
back in between is what makes a button look broken. See
[adr/0008-docker-precondition.md](adr/0008-docker-precondition.md).

## Cards

A card is four things:

1. a `CardDescriptor` in `CardCatalog` - identifier, title, whether it is implemented;
2. whatever data it needs, added to `DeckRuntime`;
3. a model and its builder in `DevDeckEngine/Cards`, which turn that data into everything the
   card shows and every click it offers;
4. a SwiftUI view in `DevDeckUI` that draws the model, and the module that hosts it.

**The model decides; the view draws.** A model holds every word already in the reader's
language, a `DeckTone` for everything that has a colour, a `DeckMark` or `DeckGlyph` for every
picture, which rows are visible in which order, and a `DeckCommand` for every click. The Mac
turns tones, marks and glyphs into its own colours, vectors and SF Symbols in one file,
`DeckModelStyle.swift`, and a view has no `L(`, no `Date()` and no `if` about the data. A click
goes to `DeckRuntime.perform(_:)`, which changes the deck or hands the shell an effect: which
browser a link opens in, which folder a terminal opens at and which project a Stop reaches are
the runtime's to know. The Windows shell will draw the same models. See
[adr/0027-card-models-in-the-engine.md](adr/0027-card-models-in-the-engine.md).

Five builders cover eight kinds of card: `ReviewListCardModel` is both pull requests and merge
requests, which were one card with the nouns changed; `InboxCardModel`, `ActionsCardModel` and
`WorkInFlightCardModel` are one each; `DeckProjectCardModel` is the Arc, DDEV and plain project
cards. The card's height is still arithmetic in `DevDeckUI` until placement moves (M-5), but it
reads only the model.

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

**A card that acts on its data owns the job, not the view.** The inbox's mark-as-read is the
model: `DeckRuntime.markRestRead()` and `markAllRead()` take the rows off the card at once,
then do the work in the background, with `NotificationsService.markRead(_:concurrency:progress:)`
marking six threads at a time. `inboxProgress` is published for the card's footer and refuses a
second start while one runs, `pendingRead` filters the answer of any poll that lands in the
middle so it cannot put back what the job has not reached, and the job ends with a fetch of its
own. What the link on the card says and does is decided by `InboxCardModel.clearing(for:optionDown:)`,
a pure function under tests, and the model carries both versions of the link so the shell only
reads the ⌥ key; see [github-api.md](github-api.md) for the calls behind it.

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

Away from the glass the same mark is drawn on a tile: `SettingsIcons.mark` puts it on a dark
rounded square, and the settings list, a page header and an attention row in the menu all ask for
it at `SidebarMetrics.iconSize`, the Mac's own "Sidebar icon size". One account has one mark at
one size, so a row in the menu and a row in the window are recognisably the same thing.

Two of them do not wear their own colour. GitHub's octocat is black and Next's disc is black,
and black on dark glass is a hole rather than a logo, so both go white - which is what both
vendors do on a dark background themselves. Which mark a plain project gets is `ProjectKind`,
matching whole words in the start command and the caption, framework ahead of runtime: see
[adr/0014-monorepos-and-marks.md](adr/0014-monorepos-and-marks.md).

## Card sizing

`CardMetrics` in `DevDeckCore` owns the row-count and height arithmetic, because two places
have to agree on it exactly: the SwiftUI card drawing the rows and the AppKit panel being
resized around them. A disagreement shows up as a clipped last row or a strip of empty glass.

Expansion state lives on `DeckRuntime` and is published, so `DeckPlacement.syncSizes()`
resizes the panel whenever either the data or the expansion changes - keeping the top edge
fixed and shifting the rest of the column out of the way.

## Placement

**Where a panel goes is the engine's; the window is the shell's.** `DeckPlacement`, made by
`DeckRuntime.placePanels(measure:displays:)`, keeps a frame per panel (in the Mac's points, y
growing upward) and makes every decision below: which panels to open and close, where a new one
goes, how a hidden card's hole closes, which size changes move the column, packing, tidying, when
a move is believed and written down, and what is parked. Each call answers with
`DeckPanelChange`s. `PanelCoordinator` reports what only the Mac sees (a panel moved, the screens
changed, how big a card draws, which displays are connected) and applies the changes, at the
window level the summon key and the display mode set. `PlacementTests` drive it the way the shell
does, including an unplugged monitor in the order the window server reports it. See
[adr/0029-placement-in-the-engine.md](adr/0029-placement-in-the-engine.md).

`DisplayMode` lives in `DevDeckCore` so it can be persisted and tested; the app maps it to an
`NSWindow.Level`:

- `.desktop` → level `-1`: below every application window, above the wallpaper. The real
  desktop levels are unusable - the WindowManager surface sits far below and would bury the
  panels.
- `.floating` → `.floating`.

Locking sets `isMovableByWindowBackground = false`, and that flag is still what decides whether
a panel may move. What moves it is no longer the window on its own: built against a current SDK,
SwiftUI takes the click on a card for the card's gestures before AppKit can start a background
drag, so `CardHostView` carries a drag gesture that, once the mouse has travelled three points,
hands the drag to the window server with `performDrag(with:)`, the way a title bar does. It is
simultaneous with the card's own gestures, so a click and a double click, which do not travel,
are never taken for a drag.

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
by kind and names the first two; the runtime applies that grouping before it hands the shell
banners to post. The attention builders turn the same facts that make the menu's
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
every card back to where it had been parked.

**The window server's move is not a move the user made either**, and it arrives dressed as one.
When a display disappears macOS pushes every window it finds off all screens onto the nearest
one that is left and posts `windowDidMove` for each, about 8 ms *before*
`didChangeScreenParameters`, with `NSScreen.screens` already describing the new arrangement
(measured, see `scripts/probe-displays.swift` and [adr/0022](adr/0022-the-deck-parks-folded.md)).
Saved on the spot, that recorded the card as living on the laptop at the spot it was dropped, and
the deck had moved house with nobody touching it. So `windowDidMove` goes into `PendingMoves`
and is written down only once the screens have kept quiet for 150 ms after it; a screen change
in between drops everything waiting. A drag ends with a last move and 150 ms of silence.

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

A card whose display is absent is *parked*, and the deck is parked as a whole rather than a
card at a time: `DeckParking` folds every parked card to its 44-point row and stacks them in one
column at the side of the main screen the deck stood on at home, in the order the deck reads in,
wrapping only when the rows do not fit. One clamp per card was the earlier answer, and on a
screen 949 points tall it sent every offset taken on one 1440 tall to the same spot on the bottom
edge. The stored placement is left untouched so the card goes home, and stands up again, when its
display returns; the fold is `DeckRuntime.parkedCards`, not the collapsed preference, and the
44-point height is not remembered. `DeckPlacement` refuses to overwrite a placement while it is
parked, because parking is not a decision the user made. `NSApplication.didChangeScreenParametersNotification`
triggers a re-place of the whole deck, after a beat - a display that has just woken reports its
old frame for a moment, and the Dock follows the main display in a second notification a few
hundred milliseconds later.

The identity is `CGDisplayCreateUUIDFromDisplayID`, not the display id and not the screen index:
ids are handed out per connection and change on a replug, and the index changes with the
arrangement. The UUID belongs to the physical display, which is what "keep this on the laptop
screen" means.

A saved position is only used when the frame still overlaps a screen by at least 80×40 points,
so a panel can never come back 99% off-screen.

**Tidying keeps each display's cards on that display, and wraps into columns.** `DeckPlacement`
gives every panel to the display it is mostly on and tidies each display on its own, from its own
topmost card ([adr/0030-tidy-keeps-each-display.md](adr/0030-tidy-keeps-each-display.md)).
`DeckLayout.tidy` in `DevDeckCore` returns the top-left corner for each panel: down from the anchor, and into a new column beside it as soon as the next panel
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

- `DeckController` is the Mac's adapter over `DeckRuntime`, which owns the data every panel
  renders and the two loops that keep it fresh: the API loop, which hands its sources to
  `RefreshCycle` and sleeps for what it is told, and a faster local loop for Docker, stacks and
  projects. See [The deck runtime](#the-deck-runtime). The rules it applies live where the suite
  can reach them: `RefreshCycle` and `ProjectWatch` in Core, `ActionsWatchList` and
  `GitHubAttention` in GitHubKit, `DeckAttention` in the engine. See [Attention](#attention).
- The modules, one per kind of card, under `Modules/`: `PullRequestsModule`, `InboxModule`,
  `ActionsModule`, `MergeRequestsModule`, `WorkInFlightModule`, `ArcProjectModule`,
  `DDEVProjectModule` and `LocalProjectModule`. A `CardModule` says which cards it owns and
  gives their view, size, dashboard and settings page. The project modules are also their
  kind's `SettingsSection`; the two account sections, GitHub and GitLab, live in the same files
  as the cards they feed. `CardHostView` asks the modules and knows no kind by name.
- `DeckCards` is the runtime's card list, `DeckCardList`, for the parts of the shell that place
  panels and save arrangements: the built-in cards plus one per project, in deck order, and
  which of them are switched on.
- `PanelCoordinator` owns the windows and applies what `DeckPlacement` decides: which cards
  have one, how big each is, and where it sits. The two rules placement exists to keep: a
  position is written down only when a person chose it, and the deck settling into its data is
  not a layout event. See [Placement](#placement).
- `DeckMenu` owns the menu-bar item and draws every menu from the runtime's entries as it opens:
  `DeckRuntime.menu(update:samples:)` for the menu-bar menu, `cardMenu(for:)` for a card's
  right-click, `status()` for the icon and tooltip. It carries out what a row asks of the app
  (panels, settings, the updater) and decides nothing about what the menus say. See
  [adr/0028-the-menu-in-the-engine.md](adr/0028-the-menu-in-the-engine.md).
- Saved decks are the runtime's too: the submenu, saving under a name the shell asks for, and
  putting one back, after which the shell opens and places the panels.
- `Summoner` owns the key that raises the deck, the tap-to-latch rule, the veils, and the click
  or Esc that puts back a deck raised from the menu or a banner; what
  "raised" does to the panels is the coordinator's.
- `DeckUpdates` in the engine watches for a newer build: when to ask GitHub, what counts as
  newer, the one banner per version, waiting for a card that is mid-command before an install,
  and every word about it (the menu's own tier, the settings row, the banner). `Updater` is the
  Mac's installer, handed an update when someone chooses it: download, `ditto`, a check of the
  unpacked bundle, the old copy to the Trash, the new one in its place, relaunch, reporting
  progress back. What counts as an update and whether the unpacked bundle is trusted is
  `UpdateCheck` in Core, under tests. See [adr/0016-self-update.md](adr/0016-self-update.md) and
  [adr/0032-the-update-check-in-the-engine.md](adr/0032-the-update-check-in-the-engine.md).
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
  and nobody pressed Stop, why a start failed, since when a health check has been silent, that
  Stop was pressed on a project nothing here could stop. It is
  fed only what `StateSettler` let through and what a button did, and reports nothing about the
  state a launch found.
- **`DeckAttention.digest`** in the engine puts it together from the runtime's state, one
  input struct, so the suite checks what lights the icon without a controller. A hidden card
  contributes nothing.
- **`AccountFailure`** carries its kind, rejected, forbidden, rate limited, unreachable or other,
  and a card whose every account failed throws `APIError.accounts` with them whole, so the menu
  says which account and what to do rather than "Forbidden".

The controller keeps the history (`ProjectWatch`, when Docker went down, when each account
started failing) and announces per channel through `NotificationDigest`, which keeps the rule
that the first answer after a launch is never news. The runtime turns the digest into menu
entries: section headers, a subtitle under each row, the age as a badge, ⌥ twins for Dismiss,
Mark as Read and What's New, the overflow of a tier in a submenu. `DeckMenu` draws them as native
menu items, with the subtitle in a tooltip before macOS 14.4.

## The settings window

**What the window does is the runtime's; how it looks is the Mac's, for now.** The sidebar's rows
(`DeckRuntime.settingsList()`: titles, the detail in the tooltip, a dot only when it means
something, sorted by name with kinds mixed) and every operation behind a form are in the engine:
adding a project from a folder, saving a form and whether the edit asks its status line again,
removing, Detect, the health and stack checks (asked the way the deck asks them), what "test the
link" opens, and the token checks, which keep a typed token only once it works. The sections in
`DevDeckApp/Modules` lay out the forms, ask for folders and confirmations, and call these. The
pages (General, Deck, Cards, Notifications) and the forms' own words stay AppKit until the
Windows settings are designed in W-10. See
[adr/0031-settings-operations-in-the-engine.md](adr/0031-settings-operations-in-the-engine.md).

A sidebar and a form column, built the way System Settings is built: an `NSSplitViewController`
whose first item is a real sidebar item, so the sidebar is translucent and runs the full height of
the window, and a toolbar, which is what gives the window the standard title bar. The two panes
apply their own top inset, because a window that draws its content full height reports no safe
area to the views inside a split item.

```
sidebar                     form column (stretches, 440 to 760 points)
⌕ Search                    [mark] harvest-app                 Show on deck ●
⚙ General                   Start
▦ Deck                      ┌ Folder         [~/Projects/…   ] [Choose…] ┐
▤ Cards                     │ Start command  [bun run dev    ] [Detect ] │
◉ Notifications             │ Long-running command                   ●  │
Accounts                    └───────────────────────────────────────────┘
  GitHub, GitLab, Work  Health check (?)
Projects                    ┌ Check URL …  ● Running  answered at …  [Check Now] ┐
  harvest-app  ●             Links …
  Intranet                › Advanced  Name, caption, stop command, Docker, browser
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
`CardModule.settingsTarget`; `open -a DevDeck --args --settings project harvest-app` does the same
from a terminal. See [adr/0018-settings-like-system-settings.md](adr/0018-settings-like-system-settings.md).

## Words

Every string on screen is a key. `Sources/DevDeckCore/Localisation/Strings.swift` is the only
place that reads a table; call sites say `L("key")`, `L("key", argument)` for a sentence with
something in it, and `LN("key", count)` for anything counted. Nothing caches what comes back,
because the language can change while the deck is up.

The tables are `Resources/Localizations/<code>.lproj/Localizable.strings`, one per language, with
`Localizable.stringsdict` beside them for the plural forms. `build.sh` copies the folders into
the bundle and lists them in `CFBundleLocalizations`. The chain is: the chosen language, then
English, then the key itself, which is how a missing translation shows up as something obviously
wrong rather than as an empty row.

`Strings.use(_:lookingIn:)` picks the language: `.system` hands the choice to macOS through
`Bundle.main`, anything else loads that `.lproj` directly. The setting lives in `Preferences`, the
General page sets it, and the settings window rebuilds itself on the spot. The suite has no
bundle of its own, so it points the same call at the repository.

Two rules keep the layout honest when a translation is longer than the English:

- A settings group measures its own labels and sets its label column to the widest of them
  (`SettingsForm.endGroup`), so the fields still line up and nothing is cut.
- A card's button row (`CardActionRow.layout`) shrinks a little, and when that would start
  eating a word it gives up whole words instead - the quiet buttons first, from the right -
  leaving the icon with the word in its tooltip.

Terms are not translated: `pull request`, `merge request`, `pipeline`, `commit`, `Docker`,
`DDEV`, `Arc XP`. Logs stay English. See
[adr/0020-six-languages.md](adr/0020-six-languages.md).

## Windows portability

The deck is heading for one engine and two thin shells - see
[adr/0024-one-engine-two-shells.md](adr/0024-one-engine-two-shells.md) and
[windows-migration.md](windows-migration.md). `DevDeckCore`, every integration kit,
`DevDeckEngine`, its host and its golden suite build on Windows 11 from the same `Package.swift`.
The Windows graph has no AppKit targets and no `KeychainACL`; it adds `DevDeckProcessHost`, the
Windows suite, lifecycle tools and a network smoke check.

Where the platforms differ, the difference is a type picked at construction, not a branch inside
shared logic:

| Concern | Mac | Windows |
| --- | --- | --- |
| Running a command | `ShellCommandRunner`, login zsh | `WSLCommandRunner` in one distribution, or `NativeWindowsCommandRunner` |
| A project's process | `ShellProjectLauncher` | `WSLProjectLauncher`, `NativeWindowsProjectLauncher` with `DevDeckProcessHost` |
| Preferences | `UserDefaults` | `FilePreferencesBackend`, `%LOCALAPPDATA%\DevDeck\preferences.json` |
| Tokens | Keychain | in memory only; Credential Manager belongs to the Windows shell |
| HTTP | `URLSession` | `URLSession` from FoundationNetworking |
| Plural forms | the stringsdict, through Foundation | `PluralCategory`, because Foundation on Windows cannot expand it |

`PluralCategory` is checked against Foundation on the Mac for every language, every counted key
and every count up to 125, so the two cannot drift. The few Mac-only files that remain shared,
`ShellPath` and `LocalAddress`, are excluded from the Windows graph by name.

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
3. Add the state to `DeckRuntime`, as a field that reports its assignments, and a
   `RefreshSource` for it; the cycle only asks it while the card is active. Mirror the field in
   `DeckController` and test the behaviour in `DeckRuntimeTests`.
4. Write the card's model and builder in `DevDeckEngine/Cards`, add it to `DeckCardModel` and
   `DeckRuntime.model(for:)`, give every click a `DeckCommand`, and test the builder in
   `CardModelTests`: every branch that decides what the card says.
5. Write the SwiftUI view in `DevDeckUI` that draws the model, and a `CardModule` under
   `DevDeckApp/Modules` that owns the identifier and returns the view and the size, add it to
   the list in `AppDelegate`, and flip
   `isImplemented`. A kind with things to configure is a `SettingsSection` too, and goes in
   the settings window's list in the same place.
6. If the card can need somebody, give it an attention builder next to its model, returning
   `AttentionItem`s and the `DeckAlert`s for the same facts, add it to `DeckAttention.digest`,
   and test the wording. See [Attention](#attention).
7. Update `README.md`, this file and `docs/roadmap.md`.

What is still per kind by name is inside `DeckRuntime`: the status dictionaries, the local
refresh loop and the three `perform` functions. That is the data plumbing, and it is the next
thing to move if a fourth kind of project ever arrives.
