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
   ├─ owns CardState<PullRequestsSnapshot>
   ├─ refresh loop: fetch → succeed/fail → RefreshPolicy.nextDelay → sleep
   └─ knows which cards are active; a hidden card is never fetched

PullRequestsService → GitHubClient → APITransport → HTTPClient → URLSession
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
