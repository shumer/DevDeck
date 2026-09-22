# Working in this repository

## Before every commit - not optional

Run this every time, including for a one-line change. Skipping it because the change "obviously
cannot break anything" is how the README ended up describing a version, a module list and a
settings window that had not existed for weeks.

```bash
./run-tests.sh   # must end in "0 failed"
swift build      # must add no warnings
```

Then, before writing the commit:

1. **Tests.** New behaviour has a test. A fixed bug has a test that fails without the fix.
   A red suite is never committed - not "temporarily", not "to fix in the next one".
2. **README.** Update it whenever user-visible behaviour changed: a new card, a new setting, a
   changed default, a new prerequisite. Check the counts and examples it quotes are still true.
3. **`docs/`.** Update the file the change belongs to - `architecture.md` for structure,
   `development.md` for how to work on it, `github-api.md` for API behaviour. Add an ADR when a
   *decision* was made rather than a detail implemented, and record the alternatives that were
   rejected and why.
4. **`docs/roadmap.md`.** Move what shipped into the done list; add what the change revealed.
5. **Commit message.** Say what was wrong and why the fix is the right shape, not which files
   moved. The diff already lists the files.

A change that alters behaviour and touches no documentation is not finished, and neither is one
committed on an unrun suite.

## Toolchain constraints

Xcode is **not** installed - only the Command Line Tools. Consequences that keep coming back:

- `swift test` does not work: no `XCTest`, no `swift-testing`. The suite is the executable
  target `Tests/DevDeckTests` using `Tests/TestHarness`. Do not add an XCTest target.
- No `.xcodeproj`, no WidgetKit extension. Panels are borderless `NSWindow`s hosting SwiftUI.
- `./build.sh` assembles `DevDeck.app` by hand and signs it with the Developer ID it finds, ad-hoc
  otherwise.
- **No `@State` in `DevDeckUI`.** From the macOS 27 SDK on, that attribute resolves to a macro
  whose plugin only Xcode ships, so it does not compile here. Write the storage out instead, a
  stored `State(initialValue:)` and a computed property over it; `ClickableHighlight` shows
  the shape. The other wrappers (`@ObservedObject`, `@Published`) are still plain wrappers.

## Invariants

- **Card identifiers are persisted strings** (`github.pullRequests`). Never rename one.
- **`DevDeckCore` and integration modules stay AppKit-free** so the head-less suite can cover
  them.
- **Tests are offline and instant.** No network, no Keychain, no `UserDefaults`, no real
  sleeping. Use `FakeHTTPClient`, `InMemoryTokenStore`, `InMemoryPreferences`,
  `RecordingSleeper`, `MutableDateProvider`. Live checks belong in `Tools/Smoke`.
- **Tokens only ever go to the Keychain.** Never into the repository, `UserDefaults`, a
  dotfile, a log line or a commit. A stored token is never written back into a text field -
  the settings row says one exists, and typing replaces it. How an item is protected follows
  from `CodeIdentity.current()` through `KeychainAccessPolicy`, never from a build flag: open
  for an ad-hoc build, bound to the app for a signed one. Never downgraded by itself: a copy
  without an identity leaves bound tokens bound, and never writes a new token open once they are.
  `scripts/seed-token.sh` follows the same recorded mode. `build.sh` signs with the Developer ID
  it finds, so a local rebuild does not install a copy that cannot read them.
- **Account ids are Keychain filenames.** `GitHubAccount.id` is never renamed, and the first
  account keeps the un-suffixed key `github`.
- **A card fails only when every account fails.** Partial failures go on the snapshot as
  `[AccountFailure]` and are drawn in the footer of the list cards.
- **Cache keys are namespaced per account**, or two tokens polling one endpoint share an
  `ETag` and serve each other's data.
- **A hidden card fetches nothing.** New cards must respect `DeckController.setActiveCards`.
- **Row height and panel height come from `CardMetrics`.** The card and the window it lives in
  must not compute it separately, or the last row gets clipped.
- **Links open through `LinkOpener` with the row's account**, never `NSWorkspace.open` directly
  - that is what puts a work pull request in the work browser profile.
- **`statusCode` and `statusLine` mirror each other case for case.** The code is on the row,
  the wording is in its tooltip; the two drifting apart is worse than either alone. A code means
  the same on every card: `MC` conflict, `CF` checks or pipeline failed, `RV` your review.
- **Everything that asks for attention is an `AttentionItem`.** The icon, the tooltip, the
  menu's rows and the banners are built from the same items by the builders in the kits and
  `DeckAttention`, never assembled separately in the app. A new signal gets a tier, a builder and
  a test, and one thing is counted once.
- **Local commands run through `ShellCommandRunner`** (a login shell) in the project folder.
  A bare `Process` with `npx` cannot find node when the app is launched from Finder.
- **Local stack state comes from the health URL**, never from the process table - the stack is
  often started by hand, and a card that says "stopped" while the site serves is worse than no
  card.
- **Docker state comes from the daemon** (`docker version`), never from a running Docker.app -
  Colima, OrbStack and a remote context all serve `docker` with no application at all. One
  probe per refresh feeds the whole deck.
- **A card never offers a Start that cannot work.** Anything containerised goes through
  `DockerGate`, which owns the wording, the colour and the button for that condition in one
  place.
- **A plain project's start is detached with a log and a pid.** A background child holding the
  runner's pipes never returns, and Stop kills the process tree rather than the recorded pid -
  a wrapper left behind keeps the port.
- **Project ids are card identifiers** (`arc.project.<id>`, `ddev.project.<id>`,
  `project.<id>`) and are never renamed.
- **The bundle is stamped with the SDK it was built against**, by the `-platform_version` flag in
  `build.sh`. Without it macOS draws the settings window with the previous era's title bar. The
  deployment target is a separate number and stays at macOS 14. The stamp also switches on every
  behaviour Apple keys to "linked on or after", and that is how 0.17 shipped with panels that
  could not be dragged: SwiftUI now claims a click on the card for its own gestures before the
  window can start a background drag. Anything the window used to do by itself for SwiftUI
  content has to be checked by hand after the SDK moves, and dragging is now asked for
  explicitly (`PanelDrag` in `CardHostView`).
- **Sidebar metrics come from `SidebarMetrics`**, which follows the Mac's own "Sidebar icon size"
  setting. Never hard-code a row height or an icon size there, and that includes the marks in the
  menu-bar menu: one account has one mark at one size, in the window and in the menu alike.
- **A control that depends on a switch is disabled while that switch is off**, the way System
  Settings greys out what a master switch turns off.
- **Settings forms are built with `SettingsForm`**, never with hand-computed frames, and with
  its four row shapes only: `settingRow`, `fieldRow`, `statusRow`, `linkRow`. An explanation is
  one line under a group or behind a section's help button, never a paragraph. A switch is an
  `NSSwitch`, not a checkbox, except in a link row.
- **An answer updates the row it belongs to.** A check coming back calls `StatusLine.update`, a
  button's answer is `ButtonAnswer` at that button. `reloadDetail` is for a change of shape only,
  and never while something is being typed; nothing says "Saved.".
- **Panel positions anchor on the top-left corner**, and a shift caused by a card growing is
  never persisted - that pair is what stops the deck creeping apart between launches.
- **Menus are populated by `menuNeedsUpdate`, never built and handed to a view.** A menu built
  once keeps the checkmarks it had at creation, which is how the lock toggle looked stuck on.
- **An update is never installed without a click, and the running copy is never touched
  before the new one is unpacked and verified.** The check runs by itself; the download and
  the swap wait for a person, and the old bundle goes to the Trash, not away. `UpdateCheck`
  decides, `Updater` does; keep it that way so the deciding stays under tests.
- **Attention messages answer three questions: what happened, to what, and what a click does.**
  A bare number is not a message. Name the thing (`2 reviews`), not the category (`2 waiting`).
  One idea has one phrase in the menu, the tooltip, the card, the banner and Settings. A greyed
  menu item is only a header or a status; anything naming a thing is clickable. An error names
  the account or project, what is wrong and the next step, never an HTTP class, and never
  `GitHub` on a GitLab card. A banner's title says what happened in about 40 characters.
- **Every word on screen is a key, never a literal.** `L("key")`, `L("key", argument)` for a
  sentence with something in it, `LN("key", count)` for anything counted, and the same key in all
  six tables under `Resources/Localizations`. English is the table the others are measured
  against, and the suite fails on a hole in any of them and on a word left in the table after the
  thing that said it went away. The key is a literal at the call site, never built from a
  condition, or the sweep that checks this cannot see it. Terms stay as they are written - `pull
  request`, `pipeline`, `Docker` - and logs stay English. Nothing caches a translated string: the
  language changes while the deck is up.
- **A layout is measured, never counted in English characters.** A translation can be half again
  as long: a settings group sizes its label column to its own labels, a card's button row gives
  up whole words before it cuts one. A new row that assumes a fixed width is a row that breaks in
  German.
- **A popover is bound both ways.** `.constant(...)` cannot be written back, so a popover closed
  by a click somewhere else leaves the view believing it is open and the next redraw puts it
  straight back. What closes it is a dismissal, not a toggle: a dismissal can arrive twice
  before the view is drawn again, and a toggle run twice reopens what it just closed.
- **Settings apply on change, not on a button.** Only the token waits for a press, because it
  is verified first. A control that silently does nothing until some other button is pressed
  is how the browser choice failed to take effect at all.

## Style

- Comments in English, ending with a period. They explain *why*; if a comment is needed to
  say *what*, rename something instead.
- Match the surrounding code. `IRTrafficWidget` in `~/Projects/Notified` is the sibling
  project and the source of the panel conventions.
- Communication with the user is in Russian; code, comments and documentation are in English.
- Never mention Claude or AI authorship in commit messages.
