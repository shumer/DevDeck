# Architecture

## Layers

```
DevDeckApp     AppKit shell — windows, menu bar, placement, settings
    │              depends on everything below
DevDeckUI      SwiftUI cards — pure rendering of a CardState
    │
GitHubKit      one integration: GraphQL documents, models, services
    │
DevDeckCore    no AppKit, no integration specifics: config, HTTP, tokens, policies
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

Locking sets `isMovableByWindowBackground = false`. Positions are stored per card and only
restored when the saved frame still overlaps a screen by at least 80×40 points, so a panel
can never come back 99% off-screen.

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
