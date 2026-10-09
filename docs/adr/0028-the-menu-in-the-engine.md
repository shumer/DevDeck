# 0028 - The menus are entries the engine builds, and the shell only draws them

## Status

Accepted, 2026-10-09. Part of [0024](0024-one-engine-two-shells.md), after cards became models
in [0027](0027-card-models-in-the-engine.md).

## Context

`DeckMenu` built the menu-bar menu and every card's right-click menu itself: which tiers and
rows to show and with what words, which cards sit in which group and how the group counts them,
when a row is disabled, what ⌥ turns a row into, when the inbox offers the rest and when all of
it, which browser "Open pull requests" uses. `DeckStatusSummary` worded the tooltip,
`Notifier` decided that three banners become one, and the card list with its groups was put
together from the modules. A Windows tray menu would have had to repeat all of it.

## Decision

The runtime builds the menus as a list of `DeckMenuEntry`: headers, separators, items and
submenus. A `DeckMenuItem` carries its title already translated, its subtitle, age badge and
image as meaning (an attention mark, calm, more), whether it is on, enabled and set in, its
tooltip, its key, its `DeckCommand`, a confirmation to ask first when there is one, and the ⌥
twin it turns into. `menu(update:samples:)` is the menu-bar menu, `cardMenu(for:)` a card's own,
`status()` the icon tier and tooltip.

Commands from a menu go to `DeckRuntime.perform(_:)` like a card's. What only the app can do
comes back as an effect: put panels on the deck, apply the lock, tidy, open Settings on a page,
show a card, install an update, open its notes, quit.

The card list moves too, as `DeckCardList`: the built-in cards, one per project, the groups and
whether each card is on. The runtime groups banners before handing them over, so `Notifier` only
delivers.

Two things stay in the shell for now, behind their own entries: the saved arrangements submenu,
which belongs to placement (M-5), and the update offer, which the updater describes and the
runtime only words (M-7).

## Consequences

- What the menus say is tested without AppKit, in `MenuModelTests`.
- `DevDeckUI` no longer words anything; the last of it was the tooltip.
- Moving it found a bug: a project card's right-click menu was titled with its identifier,
  `project.feed`, because the title came only from the built-in catalog. It now comes from the
  whole card list.
- Menu entries are not `Codable` yet: attention marks and actions are not. They become so with
  the protocol in C-1.

## Alternatives

- **Sending the attention digest and letting each shell lay out its menu.** Short, but every
  rule about the layout, from the overflow submenu to the inbox's two readings, would exist
  twice.
- **One `NSMenu`-shaped model with selectors.** It would leak AppKit's shape into the engine;
  entries and commands are what a Windows tray menu needs too.
