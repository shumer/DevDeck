# 0026 - Stop reaches only what the deck holds, and says so when it cannot

## Status

Accepted, 2026-10-09. Narrows point 3 of [0007](0007-plain-projects.md).

## Context

A plain project is "running" when its health URL answers ([0007](0007-plain-projects.md), point
4), and the URL answers for a server whoever started it. That is on purpose: a dev server started
in a terminal should not read as stopped while it serves.

Stop is narrower than that. DevDeck can stop a project in two ways only: run the stop command the
person set, or kill the process tree it started itself and still finds alive. A project started in
another terminal or tool has neither, so `LocalProjectService.stop` returned without running
anything. The runtime then asked the health URL again, found it answering, and filed the result as
a stop that did not take: the menu said "Stop didn't take effect, it still answers" about a stop
that had never been tried.

The same happens to a project whose start command returns on its own, such as `docker compose up
-d`, when no stop command was set: there is no process to kill and nothing to run.

## Decision

1. **The runtime decides whether Stop can reach a project.** `DeckRuntime.stopBlock` looks at a
   running project with no live process from its own start and no stop command, and calls it
   `startedElsewhere` when its command holds a process and `noStopCommand` when it returns. It is
   decided as the status is read, so a stop command added in Settings counts at once. The card is
   handed the answer on `LocalProjectStatus.stopBlock` and only words it.
2. **Nothing is run for a project out of reach.** Stop and Restart go to `ProjectWatch` as
   `cannotStop` instead of to the launcher. Restart is blocked too, because it would start a second
   copy onto a port that is taken.
3. **The card says it before anyone presses anything.** The note that carries the pid reads
   `started outside DevDeck` or `no stop command`, with the full sentence in the tooltip. Restart is
   disabled. Stop stays pressable: pressing it is how a person finds out, and the menu then says
   why.
4. **The menu row is good to know**, `DevDeck can't stop Shop` with `Started outside DevDeck ·
   stop it where you started it` or `No stop command set · add one in Settings` under it. Nothing
   is broken and nothing here can fix it, so it does not light the icon, and there is no banner,
   because the person is looking at the card. The row goes when the project stops or the next
   button is pressed, and that later stop is not reported as a stop on its own.
5. **A stop that was tried and did not take keeps its own wording.** A stop command that ran, or a
   tree that was killed, with the URL still answering, is still "Stop didn't take effect".

## Consequences

- DevDeck never stops a process it did not start. The cost is a project left running that the
  person has to stop where it was started, and the card says exactly that.
- A pid file lost while the server kept running (the wrapper died, Application Support was
  cleared) reads as started outside DevDeck. That is honest about what the deck holds, and Stop
  in a terminal is the right answer there too.
- The engine's protocol front-end does not carry the block yet. It moves onto `DeckRuntime` in
  C-1, and the Windows card model needs the field then.

## Alternatives

- **Stop by port**: find whatever listens on the health URL's port and kill it. Rejected: a local
  port is a shared resource ([0007](0007-plain-projects.md) learned that from a container of
  another project holding 8080), and killing somebody else's server from a card is far worse than
  not stopping one.
- **Find the process by its folder or command line** and kill that. Rejected for the same reason:
  a match is a guess, and a second checkout of the same project runs the same command.
- **Disable Stop as well.** Consistent with never offering a Start that cannot work, and tried in
  the mockups, but then nothing ever explains it except a tooltip, and the menu row it would leave
  behind only appears in the race between a press and a poll.
- **Keep running the stop and change only the wording afterwards.** Leaves the decision to the
  outcome of a call that does nothing, and Restart still starts a second copy.
