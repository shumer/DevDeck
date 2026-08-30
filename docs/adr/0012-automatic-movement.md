# 0012 - The deck moves a card only when it was asked to

## Status

Accepted. Extends [0011-two-sizes.md](0011-two-sizes.md) and the placement rules in
[architecture.md](../architecture.md).

## Context

Panel positions are absolute: each card remembers a display and a top-left offset on it. The deck
also moved cards relatively, through `shiftColumn`, so that a card growing made room for itself by
pushing the ones under it. Those two ideas are fine on their own and wrong together, and a restart
proved it. Measured on a real deck, one launch produced this:

- Two full Arc cards overlapping by 149 points, and a 133-point hole above the collapsed group.
- One stored placement rewritten by the launch itself, from offset 261 to 155.

The mechanism had three parts.

**A card that has not heard back computes the height of an empty card.** The pull-requests card
sizes itself from `state.value?.pullRequests.count ?? 0`, so before the first answer it is three
rows and an expander shorter: 3 x 28 + 22 = 106 points, which is exactly the displacement that was
measured. The panel opened at its remembered height, shrank by 106 when the first empty publish
arrived, pushed the column up, then grew back and pushed it down again. The two pushes hit
different sets of cards, because which cards count as "below" is decided geometrically at the time
and the geometry had changed in between.

**The collapsed set was read after the panels were built.** `setActiveCards` is where the
controller learns which cards are collapsed, and it ran at the end of `syncPanels`, so every
collapsed card spent the first moments of each launch believing it was whole. That is a 138-point
round trip per collapsed card, on every launch.

**Transient positions were being written down.** `syncPanelSizes` persisted the position of the
card it had just resized. A resize keeps the top edge, so there was nothing to record except in
the one case that should never have been recorded: a card a neighbour's resize had displaced
moments earlier, saved at the displaced position and loaded from there next time.

## Decision

**Automatic movement happens only for a change somebody asked for.** Collapsing a card, opening a
log tray, expanding a list: those make room. Data arriving does not move anything, ever. The deck
settling into its own contents is not a layout event.

**A card that has never had data keeps the height it last settled at.** It opens at the remembered
height and waits rather than resizing to the shape of an empty card.

**The collapsed set is read before any panel is built**, so a panel is created at the size it is
going to be.

**A resize never writes a position.** The top edge does not move, so there is nothing to write.

**Packing a column is a switch, off by default.** With it on, a card changing height closes up its
column: same column, same on-screen order, anchored on whichever card is already at the top. It is
deliberately the timid version of tidying:

- it never moves a card to another column, because a card jumping sideways on its own, because its
  neighbour grew a line, is worse than the gap it was closing;
- it never re-sorts, so dragging a card up the column still means something. The menu's Tidy stays
  the one thing that sorts into the canonical order and wraps into a second column;
- membership is horizontal overlap of more than half a card's width, so a deck dragged into place
  by eye counts as a column and a card parked off to the side does not;
- it does not run while a card is being dragged. Packing during a drag would fight the mouse.

## Consequences

- Restarting twice now produces byte-identical placements and pixel-identical geometry. That was
  the acceptance test, and it is the one that was failing.
- With packing off, which is the default, a card that grows can overlap the one below it until
  something asks the deck to move. That is the honest cost of absolute positions, and it is the
  cost the previous design was trying to avoid by moving cards nobody had asked it to move.
- A deck whose stored positions are already inconsistent stays inconsistent: the fix stops new
  damage rather than repairing old. One Tidy repacks it.
- `shiftColumn` lost its `persist` parameter. Every move it now makes belongs to the layout, so
  there was nothing left for the flag to say.
