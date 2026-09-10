# 0015 - The application layer is objects with one job each, and a module per card kind

## Status

Accepted.

## Context

By 0.9 the module that touches AppKit was three files of a thousand lines each. `AppDelegate`
owned the panels and where they sit, saved arrangements, the summon key, the menu bar, and the
wiring that makes an app out of the rest. `DeckController` owned the data, both refresh loops,
the backoff, the menu-bar counting and which repositories the Actions card follows.
`SettingsWindowController` owned the window, the list, and a form, an add, a remove and a test
for each of five kinds.

None of the logic in those files was covered by the suite, because all of it sat next to a
window. And adding a kind of card touched five of them: an `if` in `CardHostView`, a case in
its size switch, a group in the menu, a branch in the catalog, a form in the settings window.
Nothing in the code said "this is a kind of card".

## Decision

**What decides moves to where the suite can reach it.** `RefreshCycle` in Core runs the
remote cards as a list of sources and owns the shared failure counter and the wait.
`ActionsWatchList` in GitHubKit groups the watched repositories. `DeckStatusSummary.make`
assembles the tooltip and the two counts. The controller keeps the fetching and the card
state.

**The delegate becomes a composition root.** `PanelCoordinator` owns the windows and the two
placement rules, stated on the two functions they belong to. `DeckMenu` fills every menu as it
opens. `Summoner` owns the key, the latch and the veils. `ArrangementsController` owns saved
decks. `DeckCards` is the list the others read. `AppDelegate` builds them and wires the
events, and does nothing itself that one of them could do.

**A kind of card is a module.** `CardModule` says which identifiers it owns and gives their
view, size, dashboard, catalog entries and menu group. `CardHostView` and `DeckCards` ask the
modules and know no kind by name. A kind with things to configure is also a
`SettingsSection`: its rows in the list, its form, its add and its remove. The window keeps
the list and the form column and nothing about any kind. The three project kinds are one file
each, card and section together; the GitHub cards share a file with the accounts section that
feeds them, and GitLab likewise.

**Not moved: the per-kind plumbing inside `DeckController`.** The status dictionaries, the
local refresh loop and the three `perform` functions still name Arc, DDEV and plain projects.
They are data plumbing rather than presentation, the local loop's settling behaviour took two
releases to get right, and moving them would have meant the controller publishing through a
protocol so the panel coordinator can still observe height changes. That is the next cut if a
fourth kind of project arrives, and it is the one place the "one module per kind" claim does
not yet hold.

## Consequences

- `AppDelegate` is under two hundred lines, `SettingsWindowController` under three hundred,
  and the two placement rules live in a file whose name says what it is about.
- Fourteen tests cover what moved to Core and the kits, including two rules that were only
  ever checked by hand: one failing card backs the whole deck off, and a hint from the server
  slows the deck down but never speeds it up.
- `CardHostView.modules` is a static set once at launch. A SwiftUI view cannot carry the app's
  objects any other way without threading them through every panel, and no card is drawn
  before they exist.
- The one menu item about a kind rather than a card, "Power off all DDEV", stays in the menu
  by name. A protocol for it would have one conformer.
- `SettingsWindowController.Section` survives as an enum because its raw values are what the
  `--settings` launch argument takes.
