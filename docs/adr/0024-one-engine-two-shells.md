# 0024 - One engine, two thin shells, and Windows 11

## Status

Accepted, 2026-10-09. Amends [0001](0001-native-macos-app.md): the Mac app stays native, and
Windows is no longer a rewrite.

## Context

0001 chose a native Mac app and accepted that Windows would be a rewrite. Colleagues on Windows
now want the deck. A second app written from scratch would have to repeat every rule this one has
learned: how a GitHub state is smoothed, what a card says and in which tone, when something is worth
a notification, where a card goes when a monitor disappears. Two copies of those rules would drift,
and this project has already watched one pair of copies drift.

A cross-platform UI toolkit would cost the Mac its widget feel, which is the reason the deck exists.
A different language for the whole thing would throw away the half of the code that already runs
on Windows: the proof of concept built `DevDeckCore`, `GitHubKit` and `ProjectKit` natively there,
talked to real GitHub, and kept projects alive in WSL and in Windows folders.

## Decision

**One engine.** `DevDeckEngine`, in Swift, holds everything that decides anything: polling and
smoothing, card models with their finished, translated text, order, tone, attention, menus,
notifications, placement and parking, the settings model and its checks, starting and stopping
projects, logs, the update offer.

**Two thin shells.** The Mac shell is today's AppKit and SwiftUI app and links the engine in
process. The Windows shell is C#, WPF and a tray icon; it runs the engine as `DevDeckEngineHost.exe`
and talks to it in JSON lines.

**The rule that keeps it honest.** A shell decides nothing: not a word, not an order, not a tone,
not whether something is shown, not when, not what is saved. A line of shell code that does any of
these is in the wrong place, and that is an acceptance criterion for every change on either side.
The same scenario must produce byte-identical engine output on both platforms; golden transcripts
check it.

**Windows 11 only**, version 22H2 and later. Windows 10 support ended in October 2025, and the
materials the Windows style is made of, Acrylic and system-rounded windows, exist only on Windows 11.
There is no Windows 10 fallback to design, build or test.

## Consequences

- Most of the remaining work moves Mac code from the shell into the engine before any Windows card
  is drawn. The Mac app must behave exactly as before at every step; the full suite and the golden
  transcripts are the check.
- Portable code builds on both platforms from one `Package.swift`, which has a Windows graph of its
  own. Platform differences live in small types chosen at construction, not in `#if` blocks spread
  through shared logic.
- Windows builds and tests need a Windows machine; Mac changes are checked on the Mac. A change is
  merged only when both sides that it touches are green.
- The Windows delivery carries the Swift runtime and .NET, about 255 MB in the proof of concept.
  Shrinking it is planned work, not an afterthought.
- The plan, the order of work and who does what are in [windows-migration.md](../windows-migration.md).
