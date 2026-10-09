# 0025 - The deck runtime lives on the main actor and reports every assignment

## Status

Accepted, 2026-10-09. Part of [0024](0024-one-engine-two-shells.md): the first piece of the Mac app
to move into the shared engine.

## Context

`DeckController` was the Mac app's whole live state: polling and backoff, smoothing, project
actions, marking the inbox read, Docker, folding and parking, banners. It was a `@MainActor
ObservableObject` with eighteen `@Published` fields, in the app module, so nothing in it could be
tested and none of it could run on Windows.

Moving it into the engine raised two questions the move itself must not change the answers to.

**Where it runs.** The shell reads it synchronously all the time: `PanelCoordinator` folds a card
and reads the folded height on the next line, SwiftUI asks `isCollapsed` while it draws. An actor
of its own would turn every one of those reads into an `await` and every toggle into a hop, and
the order the deck has always relied on would become a race.

**How a shell hears about changes.** Combine does not exist on Windows. And the Mac's
subscriptions were written against `@Published`, which publishes every assignment, not every
change: the menu-bar item is redrawn each time the ten-second Docker probe assigns its answer, even
an identical one, and that redraw is what keeps rows like "Docker down for 5 minutes" current.
A stream of changed values only would have quietly stopped those rows from ageing.

## Decision

`DeckRuntime`, in `DevDeckEngine`, is a `@MainActor` class, exactly as isolated as the controller
was. The main actor exists on Windows too, so the engine host can own a runtime the same way.

Each former `@Published` field is a stored property that calls `onChange` with its name from
`didSet`, on every assignment. The Mac's `DeckController` stays, as an adapter: it mirrors each
named field into the same `@Published` property, so every view and every Combine subscription sees
what it saw before, one assignment for one assignment.

What only a platform can do leaves as a `DeckEffect` through `onEffect`: banners, log windows,
launching Docker Desktop, redrawing the menu-bar item. Time, sleeping, the local address and the
HTTP client come in at `init`.

## Consequences

- The Mac behaves as before, and the suite now covers what the controller did:
  `DeckRuntimeTests` run the runtime with a fake network, clock, sleeper and shell.
- The runtime does all its work on the main thread, as the controller did. Commands, HTTP and
  `git` run in their own tasks and processes; what the main thread does is decide and assign.
- `RefreshCycle.run` and the test harness take the caller's isolation, which Swift 6 needs for a
  main-actor owner to hand them main-actor work.
- The protocol front-end of the engine still has its own polling from the proof of concept. It
  moves onto `DeckRuntime` in C-1, and until then the golden transcripts are its check.

## Alternatives

- **An actor of its own.** Portable and tidy, but every synchronous read in the shell becomes
  asynchronous, and a fold followed by a layout pass becomes a race.
- **A class with no isolation**, used from whichever actor owns it. Swift 6 cannot check that the
  owner is the only caller, which is exactly the guarantee the shell relies on.
- **One `DeckState` value, published when it changes.** Simpler to send over the protocol, but it
  publishes changes, not assignments, and the Mac's time-dependent rows stop updating.
- **Keeping Combine and adding OpenCombine on Windows.** A dependency for one platform, to keep an
  API the Windows shell, in C#, would never see.
