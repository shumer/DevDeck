# 0029 - Where a panel goes is decided in the engine, and the shell moves windows

## Status

Accepted, 2026-10-09. Part of [0024](0024-one-engine-two-shells.md). Keeps every rule of
[0012](0012-automatic-movement.md) and [0022](0022-the-deck-parks-folded.md); moves where they
are applied.

## Context

The arithmetic of placement was already in Core: `DeckLayout`, `DeckParking`, `PanelPlacement`,
`PendingMoves`. The decisions that use it were not. `PanelCoordinator` decided which panels to
open and close, where a new card goes, whose hole to close and how, which size changes move the
column, when a move is the user's and is written down, and what is parked, reading and writing
window frames as it went. Windows would have needed all of it again, and the most fragile part of
the deck, a monitor unplugged and plugged back in, could only be tested by unplugging one.

## Decision

`DeckPlacement` in the engine keeps a frame per panel and makes those decisions. Each call
(`sync`, `syncSizes`, `tidy`, `packAllColumns`, `placeAfterScreensChanged`) answers with an
ordered list of changes: close a panel, open one at a frame, place one at a frame. The shell
applies them and does not report them back. What only the shell sees comes in: a panel it did not
move (`moved`, which keeps the frames true), the screens changing, how big a card draws
(`measure`, since that depends on the platform's fonts) and which displays are connected
(`displays`). Timing stays a rule of the engine (`PendingMoves`' quiet period, `screensSettle`);
the shell only owns the timers.

Frames are in the Mac's coordinates, points with y growing upward. A Windows shell converts at
its edge, once, rather than every rule being written twice.

The runtime owns the placement (`placePanels(measure:displays:)`), which lets saved arrangements
move into the engine with it: the submenu, saving under a name the shell asks for, and putting
one back.

## Consequences

- An unplugged monitor is a test now: the window server's shove, the screen change after it, the
  cards parked and folded with nothing written down, and every card home to the point when the
  display returns. Before, the coordinator could not run without windows.
- A card's height is still measured by the shell, from the model, in the shell's fonts.
- The window level, the summon key's raise and whether a panel can be dragged stay the shell's:
  they are about windows, not about where cards go.

## Alternatives

- **Moving only the remaining arithmetic** and leaving the decisions in the coordinator. It
  would have left the Windows shell to repeat the rules that took 0.19 to get right.
- **A neutral coordinate system** with y growing downward. Every rule and every stored placement
  is in the Mac's coordinates; converting them all would risk exactly the scattering this step
  was not allowed to change.
