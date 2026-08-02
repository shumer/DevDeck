# Working in this repository

## Definition of done

No change is finished until all four are true. Check them before reporting back:

1. `swift build` is clean and `./run-tests.sh` is green.
2. New behaviour has tests. Fixed bugs have a test that fails without the fix.
3. Documentation matches the code: `README.md` when user-visible behaviour changed, the
   relevant file under `docs/`, and a new ADR when a decision was made rather than a detail
   implemented.
4. `docs/roadmap.md` reflects what moved.

## Toolchain constraints

Xcode is **not** installed — only the Command Line Tools. Consequences that keep coming back:

- `swift test` does not work: no `XCTest`, no `swift-testing`. The suite is the executable
  target `Tests/DevDeckTests` using `Tests/TestHarness`. Do not add an XCTest target.
- No `.xcodeproj`, no WidgetKit extension. Panels are borderless `NSWindow`s hosting SwiftUI.
- `./build.sh` assembles and ad-hoc signs `DevDeck.app` by hand.

## Invariants

- **Card identifiers are persisted strings** (`github.pullRequests`). Never rename one.
- **`DevDeckCore` and integration modules stay AppKit-free** so the head-less suite can cover
  them.
- **Tests are offline and instant.** No network, no Keychain, no `UserDefaults`, no real
  sleeping. Use `FakeHTTPClient`, `InMemoryTokenStore`, `InMemoryPreferences`,
  `RecordingSleeper`, `MutableDateProvider`. Live checks belong in `Tools/Smoke`.
- **Tokens only ever go to the Keychain.** Never into the repository, `UserDefaults`, a
  dotfile, a log line or a commit. A stored token is never written back into a text field —
  the settings row says one exists, and typing replaces it.
- **Account ids are Keychain filenames.** `GitHubAccount.id` is never renamed, and the first
  account keeps the un-suffixed key `github`.
- **A card fails only when every account fails.** Partial failures go on the snapshot as
  `[AccountFailure]` and are drawn in the footer.
- **Cache keys are namespaced per account**, or two tokens polling one endpoint share an
  `ETag` and serve each other's data.
- **A hidden card fetches nothing.** New cards must respect `DeckController.setActiveCards`.
- **Row height and panel height come from `CardMetrics`.** The card and the window it lives in
  must not compute it separately, or the last row gets clipped.
- **Links open through `LinkOpener` with the row's account**, never `NSWorkspace.open` directly
  — that is what puts a work pull request in the work browser profile.

## Style

- Comments in English, ending with a period. They explain *why*; if a comment is needed to
  say *what*, rename something instead.
- Match the surrounding code. `IRTrafficWidget` in `~/Projects/Notified` is the sibling
  project and the source of the panel conventions.
- Communication with the user is in Russian; code, comments and documentation are in English.
- Never mention Claude or AI authorship in commit messages.
