# 0033 - The protocol is the runtime's, spoken by a session

## Status

Accepted, 2026-10-09. Part of [0024](0024-one-engine-two-shells.md). Replaces the proof of
concept's `DevDeckEngine` actor as the thing the host runs, once the host moves onto it.

## Context

The proof of concept had its own engine behind the pipe: one pull request card, plain projects,
a layout that stacked cards down the first display. It proved the shape, but every rule in it was
a second copy of a rule in the Mac app. Since M-2b to M-8 every rule lives in `DeckRuntime`: card
models, menus, banners, placement, settings, updates. What the Mac does around the runtime
without deciding anything (mirroring fields, applying panel changes, timing the settling of a
drag, feeding a log window) is what a shell in another process needs done for it too.

## Decision

`DeckSession` in the engine wraps one `DeckRuntime` for a shell on the other side of a pipe.

- **Intents in** are what only the shell sees: displays, a card's drawn size, a move it did not
  make, a log window opening or closing, and clicks, which are the `DeckCommand` the event carried,
  sent back unchanged.
- **Events out** are what changed: a card's model and its menu, the tray status and menu, panel
  changes, the deck's lock and layer, log lines, banners and effects. A model is sent only when it
  differs from the last one sent, and always whole.
- **The session keeps the timing** the Mac keeps with its own timers: when a drag counts as the
  user's, how long the displays settle before the deck is put back, how often an open log is
  read. On the wire that timing would otherwise be the shell's.
- **Coordinates** are the shell's, y down; the session mirrors them about y = 0 into the
  placement's y-up space and back, which keeps every distance and so every decision.
- **Two decisions moved out of the Mac** to make this possible, and the Mac now uses them too:
  where a clicked banner goes (`DeckCommand.followAlert`) and what showing a card means (on the
  deck, its log open, then the deck brought up). The release notes link is the runtime's as well.

The contract is [engine-protocol.md](../engine-protocol.md).

## Consequences

- A shell's code is drawing, input and platform effects. A line of C# that picks a text, a tone,
  an order or a delay is in the wrong place, and the protocol gives it nowhere to get one from.
- The protocol is pinned by `session-en` and `session-ru` golden transcripts, byte for byte on
  both platforms, alongside the runtime's own.
- Commands look like Swift's synthesized coding, `{"toggleCard":{"_0":"github.inbox"}}`. That is
  fine because a shell never reads them; the one it fills in, a prompt's name, is documented.
- The Mac keeps calling the runtime in process. It does not speak the protocol, so a change to
  the runtime shows on both platforms, and a change to the session only on Windows; the session
  transcripts are what catch the second kind.

## Alternatives

- **Growing the proof of concept's engine card by card.** Every card would have been written a
  second time, which is the thing 0024 set out to stop.
- **A protocol of fine-grained field changes**, mirroring `DeckField`. The shell would then have
  to build models out of fields, which is deciding.
- **Commands as names plus arguments the shell assembles.** More readable on the wire, and one
  more place for a shell to get a click wrong.
