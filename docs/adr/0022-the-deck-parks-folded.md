# 0022 - The deck parks folded, and a move waits to be believed

## Status

Accepted. Amends the parking described in [0012](0012-automatic-movement.md) and the display
identity that positions are kept against.

## Context

A colleague unplugged the monitor the deck lived on. The cards fell onto the laptop screen in a
pile, and when the monitor came back they did not go where they had been: some exactly, some a
column's width off. Nobody had touched a card.

A probe (`scripts/probe-displays.swift`, four borderless windows built like the panels) showed
what happens, on a real unplug and a real replug:

- The window server moves every window it finds off all screens onto the nearest one that is
  left, to its top edge, all of them to the same spot. A window that happens to fall inside the
  remaining screen in the new coordinate space is left where it is, which is now somewhere else.
- Each of those moves posts `windowDidMove`, about 8 ms **before** `didChangeScreenParameters`,
  and `NSScreen.screens` already describes the new arrangement when it does.
- On reconnect the window server puts back the windows it moved itself, again before the
  notification. Windows the app moved in between are not its business.
- The Dock follows the main display in a second notification 300 to 500 ms after the first, and
  the visible frames change again with it.

The deck could not tell the second bullet from a drag: `isRepositioning` was false, so
`persistPosition(userMoved: true)` ran, computed the placement against the fresh screen list, and
recorded the card as living on the laptop at the spot the window server had dropped it. From then
on the card was *home* on the laptop: packing and resizing wrote positions and heights there
freely, the rule against saving while parked never fired because nothing was parked any more, and
on replug the cards the window server moved back were re-recorded at their old frames while the
ones the deck had rearranged stayed where the deck had put them. That is both pictures.

Even without that, parking was one clamp per card. Offsets taken on a display 1440 points tall
mostly do not exist on one 949 tall, and every card that did not fit was pulled to the bottom
edge, on top of the others.

## Decision

**A move is written down only after the screens have kept quiet for 150 ms.** `PendingMoves`
holds each card's last move; a screen change throws away everything waiting, because whatever
those moves were they were not the user's, and the deck is about to be laid out from its
placements anyway. A drag ends with a last move and 150 ms of silence, which nobody notices.

**The parked deck is one column of folded rows.** `DeckParking` lays out every card whose display
is absent at once: the cards keep the order the deck reads in, home's columns left to right and
top to bottom within each, fold to the 44-point row from [0011](0011-two-sizes.md), and stand at
the side of the borrowed screen the deck stood on at home, wrapping into a second column only
when the rows do not fit. Folding while parked is the deck's doing, not a choice: it is not
written to preferences, the context menu says so in place of the fold item, and neither the
position nor the 44-point height is remembered. The moment the display is back the plan has every
card home, at the placement that was never touched, standing at the height its data gives it.

## Consequences

- A card that comes home stands up again on its own, and a card that was folded by choice stays
  folded, because the two states are kept apart: `isCollapsed` is either, `isCollapsedByChoice`
  is what an arrangement saves.
- Dragging a parked card still makes the laptop its new home, as [0012](0012-automatic-movement.md)
  decided, and so does tidying: those moves have quiet screens after them.
- Two hidden cards remembered at the same spot open beside each other rather than on top of each
  other. It is the same `settle` a new card gets.
- The arithmetic is tested in the core against the probe's timeline. The AppKit glue that applies
  it is thin and is not, since a headless suite cannot unplug a monitor.
- `Displays.fallback()` still means `NSScreen.main`, which with separate Spaces per display is
  the screen being worked on, the one the Dock is on. The parked column lands where the eyes are.
