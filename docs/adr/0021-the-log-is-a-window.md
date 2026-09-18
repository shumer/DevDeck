# 0021 - The log is a window, not a tray on the card

## Status

Accepted. Replaces the tray decided in [0011](0011-two-sizes.md) and referred to in
[0012](0012-automatic-movement.md).

## Context

The log was six lines inside the card: 9.5-point monospace on a panel 352 points wide, opened by
a switch in the card's header. Two things were wrong with it, and both were in the original
design rather than in the implementation.

It could not be read. Six lines at that size answer "is it moving" and nothing else; a stack
trace from a failed start, which is the one thing worth reading, arrives as six ribbons of
truncated text. There was no selecting, no copying, no searching, and no way to see the line
before the six.

It moved the deck. An open tray made the card about 120 points taller, so the column under it
jumped every time somebody looked at a log, and jumped back when they closed it. The arrow in the
corner already admitted the problem: it opened the file in Console, which is a context switch to
read what the card was showing badly.

## Decision

**The log opens in a window of its own, one per project.** Dark, monospaced, resizable,
remembering its size and place per project, several open at once. The card's header button opens
and closes it and is lit while it is open; so is the card's context menu item and the row a
banner or the attention menu points at.

**The card loses the tray entirely.** Its height no longer depends on anything a log does, which
is what stops the deck moving. What is left on the card is the narration line a running command
already writes, which is what answered "is it moving" in the first place.

**The window reads while it is watched.** Every two seconds when it is visible, and not at all
when it is minimised or behind another window. The deck's own pass still re-reads the logs that
are on screen, and an action re-reads straight after it settles.

**It is text, so it behaves like text.** Selectable, copyable, ⌘F through the Edit menu's Find
items and the find bar the system draws. A footer says where the lines come from, keeps a Follow
switch that turns itself off the moment somebody scrolls up, and opens the whole file.

**The window is asked for more lines than a card was.** `LogTail.windowLineLimit` rather than
six, and a bigger tail of the file to find them in. The limit travels with the request, so the
same three services answer both.

## Rejected

- **A panel in the deck's own glass.** It looks better in a screenshot and worse in use: no
  system window controls, no Cmd-Tab, no minimising, no remembered frame, and a find bar would
  have to be built by hand. A log is the one thing on the deck that is not a glance.
- **One window with a project switcher.** Two logs side by side is the reason to have windows at
  all; a switcher makes the second one cost the first.
- **Following the file with a watcher.** `docker logs` and `ddev logs` are commands, not files,
  so two of the three cannot be watched anyway. A two-second read of the last few hundred lines
  costs less than the machinery to tell them apart.
- **Colouring the output.** The escapes are stripped for good reasons (see `LogTail`), and
  guessing at severity from the words is how a `GET /error-handler 200` line turns red.

## Consequences

- `CardLogTray` is gone; `CardHeaderToggle` moved to its own file. `ProjectCardMetrics.height`
  lost its `logs` argument, and the three project cards take `isShowingLogs` instead of `logs`.
- The Edit menu grew a Find submenu. It was needed anyway: ⌘F is routed through the main menu,
  and an agent app has to build that menu itself.
- The Dock icon is now counted rather than flagged: settings and every log window ask for it
  while they are open (`WindowPresence`), and the last one to close gives it back.
- `open -a DevDeck --args --logs [card]` opens a log window without a hand on the mouse, for
  looking at it and for a screenshot, the way `--settings` and `--menu` already did.
