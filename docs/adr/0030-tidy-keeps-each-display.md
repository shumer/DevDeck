# 0030 - Tidying keeps each display's cards on that display

## Status

Accepted, 2026-10-09. Amends the menu's Tidy as [0012](0012-automatic-movement.md) describes it;
the parked deck of [0022](0022-the-deck-parks-folded.md) is unchanged.

## Context

Tidy anchored on the topmost panel of the whole deck and stacked every card under it, on that
panel's display. A deck is often two groups: the cards watched on the laptop and one project kept
on the monitor beside the work. Tidying pulled that card across to the others, and since a tidy is
saved as the user's own arrangement, it stayed there: the card had moved house because of a menu
item meant to close up gaps.

## Decision

Tidy gives every panel to the display it is mostly on, by area, and tidies each display on its
own: anchored on that display's topmost card, stacking down and wrapping into columns within that
display. A card on no display goes with the main one. Order within a display is still the deck's
own. A card alone on its display stays where it is.

Parked cards are on the main display while theirs is away, so they are tidied there, and the
result is saved as the user's choice, as before.

## Consequences

- Tidy never moves a card to another display.
- Two displays' cards are two columns' worth of tidying, so a deck spread over both is closed up
  on both at once.

## Alternatives

- **Tidying only the display under the pointer.** Less surprising for that display, but the
  other one is left untidy, and Tidy in the menu-bar menu has no display under the pointer.
- **Keeping the old rule and asking before moving across displays.** A question every time for
  what is never wanted.
