# DevDeck on Windows

How the deck gets from a Mac app to a Mac app and a Windows app built on one engine. The decision
itself is [adr/0024-one-engine-two-shells.md](adr/0024-one-engine-two-shells.md); this is the
order of work.

## Where it stands

The proof of concept is finished and every question it asked was answered yes:

| Question | Answer |
| --- | --- |
| The core builds natively on Windows | Yes |
| Live GitHub from Windows | Yes |
| A WSL project outlives the engine and stops as a whole, with no global WSL setting | Yes, [0023](adr/0023-project-process-lifetime.md) |
| A Windows-folder project outlives the engine and stops as a whole | Yes, [0023](adr/0023-project-process-lifetime.md) |
| One scenario gives byte-identical engine output on Mac and Windows | Yes, three golden transcripts |
| A thin WPF shell can draw cards without deciding anything | Yes |

Measured there: engine 6 MB private memory, WPF shell 83 MB, about 0.2% CPU at idle, first card
after 1.4 s, delivery 255 MB. Not yet measured: two monitors with different scaling, ARM64.

**Supported Windows: Windows 11 22H2 and later.** No Windows 10 fallback anywhere.

## How work is done

- One branch per task from a fresh `main`: `mac/<id>-<name>` for Mac-side work, `win/<id>-<name>`
  for Windows-side work.
- The Mac side runs `./run-tests.sh`, `swift build` with no warnings and, from M-2 on, the golden
  transcripts. The Windows side builds the Windows graph and runs the Windows suites. Neither side
  reports the other's checks as passed.
- A branch is merged when both platforms it touches are green. Releases only when asked for.
- The usual rules hold: English in code and docs, no client names, secrets only in the OS store,
  one ADR per real decision.

## Phase 1 - the engine in `main`, and the Mac app on it

The rules move to one place, and the Mac app already uses them. After this phase the Windows shell
only has to draw.

- **M-1. Portable core.** The Windows adapters of the core, the file preferences store, the
  Windows graph in `Package.swift`, and project launching split into a launcher per platform
  instead of `#if` inside `LocalProjectService`. The Mac behaves exactly as before.
- **M-2a. Engine foundation.** Protocol v2, the engine host, the golden infrastructure and the
  localisation resources target build on both platforms. The Mac application does not use them
  yet. Done.
- **M-2b. Mac application on the engine.** `DeckController`'s logic moves into `DeckRuntime`: polling,
  smoothing, project actions, the inbox and attention. A portable change stream replaces
  `@Published`, and the Mac shell wraps it for SwiftUI. Done; see
  [adr/0025-the-deck-runtime-on-the-main-actor.md](adr/0025-the-deck-runtime-on-the-main-actor.md).
- **M-3. Every card model in the engine.** Done; see [adr/0027](adr/0027-card-models-in-the-engine.md). Text, tones, badges, order and footers move out of the
  SwiftUI cards into model builders. The views draw models; presentation tests stop depending on
  SwiftUI.
- **M-4. Menu, attention and notifications in the engine.** `DeckMenu` builds an `NSMenu` from a
  menu model; `Notifier` shows what the engine decided. Done; see
  [adr/0028](adr/0028-the-menu-in-the-engine.md).
- **M-5. Placement in the engine.** Done; see [adr/0029](adr/0029-placement-in-the-engine.md). `PanelCoordinator` only applies frames; the engine decides
  place, parking, Tidy and column packing. A replay of a recorded monitor unplug becomes a test.
- **M-6. Settings in the engine.** The sidebar and every operation behind a form go through
  the runtime: add, save, remove, Detect, the health, stack and token checks, link tests. The
  forms and the four pages stay AppKit until W-10. Done; see
  [adr/0031](adr/0031-settings-operations-in-the-engine.md).
- **M-7. The update check in the engine.** Installing stays in the shell. Done; see
  [adr/0032](adr/0032-the-update-check-in-the-engine.md).
- **M-8. Golden transcripts** for every card, the menu, notifications and placement, in English
  and Russian. Done; see `Tests/EngineTests/RuntimeGolden.swift`, byte for byte on both platforms.

Phase 1 is done when the Mac app behaves as before, every suite is green and neither `DevDeckApp`
nor `DevDeckUI` decides anything by the rule in 0024.

## Phase 2 - the full contract, and the Windows host from `main`

- **C-1. Protocol v2 in full**: every intent and event, plus what the Windows style needs: where a
  project runs, the branch with its link, the effective command, header buttons, the health strip,
  semantic icons, and why Stop cannot reach a project (`LocalProjectStatus.stopBlock`, see
  [adr/0026](adr/0026-stop-only-what-the-deck-holds.md)). Documented in
  [engine-protocol.md](engine-protocol.md), together with the [Windows style guide](windows-style.md).
  In three steps: the session and its events
  ([adr/0033](adr/0033-protocol-on-the-runtime.md)), settings and updates on the wire, and the host
  moved onto the session. Done.
- **W-1. The engine host on Windows from `main`**, with every golden transcript identical. Done
  with C-1: `5dbdb0b` builds clean on Windows, all eleven transcripts match, and the live host
  starts, survives and stops a Windows and a WSL project.
- **W-2. Windows CI** on `windows-latest`: core and engine build, engine tests, shell tests. The
  Mac workflow is unchanged. Done for the Swift side: the `windows` job in `tests.yml` builds
  with Swift 6.4 and runs both suites, with golden transcripts compared byte for byte. W-3 adds
  the .NET build and shell tests to the same job.

## Phase 3 - the Windows shell

Every task ends with screenshots on neutral data and a check against the shell rule.

- **W-3.** A WPF shell on protocol v2, then the first Windows style pass for review lists and
  Windows and WSL project cards: Acrylic, system rounding, fonts, icons and shared brand vectors.
  Done: `Windows/`, drawn from the golden sessions and tested against them, the three reference
  cards next to the mock at 100%, 150% and 200% in `docs/poc/windows-ui`.
- **W-4.** Finish the style for Inbox, Actions, GitLab, Work in flight, Arc, DDEV, the folded row
  and the expanded list. Done: every card of the golden sessions, checked next to the Mac's
  drawing of the same transcript (`CardPreview`), captures in `docs/poc/windows-ui/w4-*.png`.
- **W-5.** Tray icon and menu from the engine's menu model. Done: the tray icon by tier with the
  Mac icon's rules, the tray and card menus from `menu.changed` and `card.changed`, confirmation
  and prompt dialogs in the model's words; captures in `docs/poc/windows-ui/w5-*.png`.
- **W-6.** Toast notifications with the source's logo; a click goes where the engine says. Done:
  one toast per `notify` model through Windows App SDK, registered without a package or a
  shortcut, the command sent back on a click; captures in `docs/poc/windows-ui/w6-*.png`.
- **W-7.** Windows and displays: moves reported to the engine, plans applied, parking on unplug,
  two monitors with different scaling, sleep and wake. Done in the shell: stable device interface
  ids, full work areas in primary-display DIPs, Per Monitor V2 rendering, one move after a drag,
  no feedback from engine placement, and full display lists after display, work area, DPI and
  resume changes. Hardware acceptance passed with a 250 percent primary display and a 100 percent
  external display: drag, Tidy, restart, disconnect parking, reconnect restore, sleep and resume.
- **W-8.** The log window with search. Done: one window per card from `openLogs`, lines, source
  and detail from `log.changed`, the tail appended and followed, a local search, and
  `logWindow.changed` both ways; captures in `docs/poc/windows-ui/w8-*.png`.
- **W-9.** Summon: a global key raises the deck and dims the rest.
- **W-10.** Settings, starting from a mock that is agreed first: accounts with tokens in
  Credential Manager, projects with Detect and Test, a Windows or WSL folder.
- **W-11.** Browsers and profiles, the terminal and the folder for both Windows and WSL projects,
  the phone QR code.
- **W-12.** Docker Desktop, DDEV natively and in WSL, Arc in WSL; the 0023 scenarios become
  standing checks.
- **W-13.** Start at login.

## Phase 4 - delivery

- **W-14.** Delivery size: framework-dependent .NET, a trimmed single file, or a smaller Swift
  runtime, chosen from measurements.
- **W-15.** Installer.
- **W-16.** Code signing.
- **W-17.** Updates on Windows: download, verify the signature, install, restart.
- **W-18.** Release builds in CI next to the Mac release: one tag, two archives.
- **W-19.** ARM64.
- **W-20.** README and install notes for Windows.
- A beta for colleagues, then a public release.

## Order

```
M-1 -- M-2a -- M-2b -- M-3 -- M-4 -- M-5 -- M-6 -- M-7 -- M-8
          |                         |       |       |
         W-1 -- W-2               C-1 -----+-------+
                                    |
                                   W-3 -- W-4 -- W-5 -- ... -- W-13
                                                                  |
                                                  W-14 -- ... -- W-20 -- beta
```

W-1 and W-2 can start right after M-2a; W-3 right after C-1; W-14 any time after W-1.

## Risks

| Risk | What is done about it |
| --- | --- |
| Swift on Windows is younger than on the Mac | The toolchain version is pinned and rechecked with each Swift release |
| A 255 MB delivery | W-14, before the first beta |
| Monitors with different scaling | Its own acceptance in W-7, on two real monitors |
| Phase 1 changes how the Mac behaves | Every step runs the full Mac suite and the golden transcripts |
| The settings window is large | A mock is agreed before it is built |
| WSL behaves differently on different machines | The 0023 scenarios become standing checks in W-12 |
