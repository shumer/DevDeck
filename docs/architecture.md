# Architecture

## Layers

```
DevDeckApp     AppKit shell — windows, menu bar, placement, settings
    │              depends on everything below
DevDeckUI      SwiftUI cards — pure rendering of a CardState
    │
GitHubKit      one integration: GraphQL documents, models, services
ArcKit         one integration: projects, link templates, local Fusion stack
DDEVKit        one integration: projects, ddev list, .ddev/config.yaml
ProjectKit     one integration: plain projects — folder probe, detached start, health check
    │
DevDeckCore    no AppKit, no integration specifics: config, HTTP, tokens, policies,
               command runner, the Docker probe
```

The rule that keeps this honest: **`DevDeckCore` and every integration module must build and
be testable without AppKit**. The suite is a plain executable running head-less, so anything
that reaches for a window cannot be covered by it.

## Data flow

```
DeckController (@MainActor)
   ├─ owns CardState<…> for each card
   ├─ refresh loop: fetch → succeed/fail → RefreshPolicy.nextDelay → sleep
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
Everything downstream — the layout merge, the menu, the panel sizing — works against that
merged catalog, so adding a project in settings creates a card with no code change.

`LocalStackService` answers "is it running" by requesting the project's health URL rather than
inspecting processes, and runs its commands through `ShellCommandRunner`. Both decisions, and
why the obvious alternatives are wrong, are in [adr/0005-local-stack.md](adr/0005-local-stack.md).

Local status polls on its own 10-second loop in `DeckController`, separate from the API
refresh: a stack that just came up should appear within seconds, and the probe is local and
cheap. A project mid-command is skipped by the poll so the card cannot flicker back to
"stopped" during a restart.

## Local project cards

Arc, DDEV and plain project cards are the same shape and are built from the same pieces —
`CardHeroRow`, `CardMetaBlock`, `ProjectChipRow`, `CardActionRow` in `DevDeckUI`, framed by
`CardChrome`. Anything that looks like a card of a local project belongs there rather than in
one card's file: two copies of the same layout drift, and this project has already watched that
happen once.

The hierarchy — one hero, everything else quiet — is [adr/0009-card-hierarchy.md](adr/0009-card-hierarchy.md).
Two consequences show up in the code. `ProjectCardMetrics.height` is the only place a card's
height is computed, for all three of them. And because the chips now wrap, that height depends
on how many lines they take: `CardChipFlow` measures the labels in the real font and breaks
lines by the same rule `CardChipLayout` uses when it draws them. The two agreeing is what stops
a card clipping its own control row.

`DDEVEnvironment` differs from `LocalStackService` in one structural way — it is shared rather
than per project, because `ddev list -j` answers for every project at once. See
[adr/0006-ddev-projects.md](adr/0006-ddev-projects.md).

`LocalProjectService` is the third of them, for projects nothing else describes. Its one
structural difference is that it has to launch a command that may never return, so it keeps a
log file and a process id per project under Application Support — see
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
of probes that still say "no" — Docker Desktop takes the better part of a minute, and flipping
back in between is what makes a button look broken. See
[adr/0008-docker-precondition.md](adr/0008-docker-precondition.md).

## Cards

A card is three things:

1. a `CardDescriptor` in `CardCatalog` — identifier, title, whether it is implemented;
2. a branch in `CardHostView` — the SwiftUI view and the panel size;
3. whatever data it needs, added to `DeckController`.

`CardLayout` holds the user's preference: which cards are on and in what order. It is merged
with the catalog on every read, so:

- a card added in a newer build appears with its default visibility instead of vanishing;
- an identifier removed from the catalog is dropped from the user's list silently;
- a card that is enabled but not implemented never renders — `visibleCards()` filters it.

Card identifiers are persisted strings (`github.pullRequests`). **They must never change.**

## Accounts

`GitHubAccount` is one identity with one token: a slug id, a label, a base URL, the
organisations it covers, and an enabled flag. `GitHubAccountsStore` persists the list; the
token lives in the Keychain under the account's own key.

`GitHubWorkspace` fans a card's fetch out over every enabled account and merges the results.
The rule everywhere: **a card fails only when every account fails.** A partial failure is
carried on the snapshot as `[AccountFailure]` and drawn in the card footer, because blanking a
card over one expired token is how a deck stops being trusted.

Two details worth keeping in mind when adding a card:

- Every model carries `accountID`. Cross-account work needs it — the Actions card groups
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
open is issued with `createsNewApplicationInstance` — the API equivalent of `open -na … --args`.
Anything that fails, or a browser that has since been uninstalled, falls back to the system
default rather than doing nothing.

`ChromiumProfiles.parse(localState:)` lives in `DevDeckCore` so the suite can cover it; the app
supplies the bytes from `~/Library/Application Support/<browser>/Local State`.

## Legibility on glass

Panels are a blur over the wallpaper, and `NSVisualEffectView` takes its brightness from
whatever is behind it — so over a bright desktop the palette's near-white text turns to mush.
Three things keep the surface honest, and they work together:

- the window is pinned to `darkAqua`, so the `hudWindow` material stays dark whatever the system
  appearance is doing;
- a veil of `black` at 22% sits between the blur and the content;
- a 1-point white hairline at 16% gives the panel an edge over a busy wallpaper.

The veil used to be 42% and nothing else. That is enough black to stop being glass and start
being grey paint, which is exactly how the cards read next to the sibling widget on the same
desktop. Contrast is a property of the surface, not something to chase by nudging text colours
per card — but neither is it something to buy by draining the colour out of the surface.

`DeckTheme`'s three state colours are that widget's values to the digit. Two decks side by side
with greens a shade apart look like a mistake rather than a decision.

## The brand marks

Each card's title carries the logo of what it is about, and those are the real logos: `BrandMark`
holds the `d` attributes from the vendors' own SVGs, and `SVGPath` parses them into a `Path` at
draw time — full command set, including elliptical arcs, because Docker's whale and DDEV's mark
use them. This is what an asset catalog would normally do, and this toolchain has none.

The first attempt approximated the marks with circles and triangles and looked exactly like
that, which is why the parser is worth its hundred lines. The suite checks every mark parses,
lands inside the box it was given, and is not a speck in the corner of it — a logo that silently
comes out empty looks, on a card, identical to one that was never added.

## Card sizing

`CardMetrics` in `DevDeckCore` owns the row-count and height arithmetic, because two places
have to agree on it exactly: the SwiftUI card drawing the rows and the AppKit panel being
resized around them. A disagreement shows up as a clipped last row or a strip of empty glass.

Expansion state lives on `DeckController` and is published, so `AppDelegate.syncPanelSizes()`
resizes the window whenever either the data or the expansion changes — keeping the top edge
fixed and shifting the rest of the column out of the way.

## Placement

`DisplayMode` lives in `DevDeckCore` so it can be persisted and tested; the app maps it to an
`NSWindow.Level`:

- `.desktop` → level `-1`: below every application window, above the wallpaper. The real
  desktop levels are unusable — the WindowManager surface sits far below and would bury the
  panels.
- `.floating` → `.floating`.

Locking sets `isMovableByWindowBackground = false`.

Two details keep a deck stable across launches, and both were bugs first:

- **Positions anchor on the top-left corner**, not AppKit's bottom-left origin. Cards change
  height as their data arrives, so a card restored at its stored bottom starts with its top
  lower than the user left it and then grows downwards from there.
- **A panel opens at the height it last settled at**, remembered per card, and a shift caused
  by a card growing is never persisted. Without the first, every launch began with a short
  panel that shoved the column down as it filled; without the second, that shove was saved and
  the deck crept apart a little further each time.

A saved position is only used when the frame still overlaps a screen by at least 80×40 points,
so a panel can never come back 99% off-screen.

**Tidying wraps into columns.** `DeckLayout.tidy` in `DevDeckCore` returns the top-left corner
for each panel: down from the anchor, and into a new column beside it as soon as the next panel
would hang below the visible frame. It is arithmetic in the core rather than a loop in the
delegate because it decides whether a panel ends up somewhere the mouse can reach — six cards
are over a thousand points tall, and a single column buried the last of them under the bottom
edge and then saved that position. The column grows towards whichever side of the anchor has
more room, and a new column is clamped inside the screen: overlapping panels can be dragged
apart, off-screen ones cannot.

## The settings window

Four sections and three columns: the sections, the things in the selected section, and the form
for one of them.

```
sections          list                     form
GitHub accounts   ● Governance             ┌ Name        [ Governance        ] ┐
Arc projects        whistleblower          │ Folder      [ /Users/…  ][Choose]│
DDEV projects ▸   ○ nasdaqir               └───────────────────────────────────┘
General             NasdaqIR               Links on the card …
                  [+] [−]
```

The middle column is the answer to a real problem: with every project's fields stacked down one
page, it was impossible to see where one ended and the next began. Only the selected item has a
form, and the list carries the identity — name, what tells it apart, and a state dot.

Forms are built by `FormLayout`, which places from the top down and moves its cursor by what it
actually placed; a control passed a `nil` width shares whatever is left over. That is both
halves of what was wrong before: labels drawn over the controls above them, and a fixed-width
form leaving dead space down the right of the window. The form is rebuilt on resize, which is
cheap and keeps every field stretched to the window.

`General` has nothing to list, so its page takes the list column's width as well.

Everything applies as it is edited. Only a token waits for a button, because it is verified
against the API before being stored.

## Concurrency

`DevDeckCore`, `GitHubKit` and the tests build in Swift 6 language mode with strict
concurrency. `DevDeckUI` and `DevDeckApp` build in Swift 5 mode — see
[adr/0002-spm-only-toolchain.md](adr/0002-spm-only-toolchain.md).

Shared mutable state uses actors (`HTTPCache`, `APITransport`, `FakeHTTPClient`) rather than
locks: `NSLock` is unavailable from async contexts under strict concurrency.

## Secrets

Tokens live in the login Keychain and nowhere else — not in the repository, not in
`UserDefaults`, not in a dotfile. `CompositeTokenStore` reads Keychain first, then the
environment, so a stale `GITHUB_TOKEN` export cannot shadow the token set in Settings.

## Adding a card

1. Add a `CardDescriptor` to `CardCatalog` with `isImplemented: false`.
2. Build the integration in its own module (or extend `GitHubKit`), with tests.
3. Add the state to `DeckController` and fetch it only when the card is active.
4. Write the SwiftUI card in `DevDeckUI` against a `CardState<…>`.
5. Wire it into `CardHostView` (view + size + dashboard URL) and flip `isImplemented`.
6. Update `README.md`, this file and `docs/roadmap.md`.
