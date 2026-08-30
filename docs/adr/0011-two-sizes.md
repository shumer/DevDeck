# 0011 - A card has two sizes and only two

## Status

Accepted. Extends [0009-card-hierarchy.md](0009-card-hierarchy.md).

## Context

Six cards on this machine come to 1218 points, which is taller than the laptop screen. The deck
already wraps into a second column when it is tidied, and the second column is where cards go to
be forgotten. Most of those cards, most of the time, are not being read: they are being checked.
"Is it still up" does not need a branch, five chips and four buttons.

Three shapes were drawn at true scale before anything was written: a hotkey that summons the deck
over everything, saved layouts that give each card a size, and a card folded down to one row. The
drawing settled two of them. A layout is a size per card, so a layout without a collapsed card can
only move panels around, which dragging and `restack()` already do. The collapsed card is the
piece both of the others are made of, and it is the only one of the three that needs no second
mode, no new permission and no extra window.

## Decision

A card is either whole or one row of 44 points. There is no third size.

- **44 points**, as 10 top, a 24-point row and 10 bottom, from `CollapsedCardMetrics`. Fixed,
  because a collapsed row has no wrapping chips and so nothing to measure.
- **What survives**: the vendor mark at 15 points, the state dot at its full size with its halo,
  the project name at 12.5 points, one monospaced note, and one 24-point icon button.
- **What goes**: the branch, the meta row, every chip, three of the four buttons and the clock.
  A collapsed card can tell you something is wrong. It cannot tell you what, and it should not
  pretend otherwise: opening it is one item in the panel's own menu away.
- **The name grows** from the 10.5-point caps title to 12.5 points at weight 500. With no hero
  line beneath it, the name is the card.
- **The note** is the running detail when the project is up, the container count, the pid or a
  mutagen warning, and the state word otherwise. The dot has already said which of the two this
  is, so the words do not repeat it.
- **The action is not chosen.** It is the first entry of the `lifecycle` array each card already
  builds, so stopped offers Start, running offers Stop, and a card mid-command offers nothing
  pressable.
- **The corner radius drops to 14.** It is the one number a collapsed card cannot inherit: at 44
  points tall, a 20-point radius reads as a pill rather than as a card.
- **Collapsing closes the log tray.** Six lines of log under a one-line card is not a card.
- Collapsed is remembered per card, under `panels.<id>.collapsed`, because the point is that the
  projects you are not working on today take one row each while the one you are stays whole.

## Consequences

- A collapsed Arc card saves 165 points, 209 down to 44. Six collapsed cards come to 324 points
  against 1218, which is a deck that fits a laptop screen with room left over.
- A two-line variant carrying the branch was drawn and dropped. At about 62 points the saving
  against a full 182 is no longer decisive, and the deck would have three sizes. Two sizes is a
  rule anyone can hold in their head. Three is a settings screen.
- Named layouts are now a small feature rather than a large one: a layout is a set of cards that
  are collapsed plus the positions the deck already remembers. It is deliberately not built yet,
  because the deck may already fit the screen without it.
- The GitHub cards are not collapsible yet. Their one row would say something different, a count
  rather than a state, and nothing in this decision tells us what their single action should be.
