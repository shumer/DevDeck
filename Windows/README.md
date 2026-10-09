# DevDeck on Windows

The Windows shell is a WPF client for protocol v2. `DevDeckEngineHost` owns all product decisions
and state. The shell reports displays and user interaction, applies panel frames, draws card models
and returns commands without changing their JSON.

## Build and test

Windows 11 22H2 or later, Swift 6.4 and the .NET 10 SDK are required.

```powershell
swift build --jobs 1
dotnet build Windows/DevDeck.Windows.slnx --configuration Release -warnaserror
dotnet run --project Windows/DevDeck.Shell.Tests --configuration Release --no-build
Tools/Build-WindowsShell.ps1
```

The build script writes a self-contained package to `dist/windows-x64`. It contains the shell, the
engine host, the process host and Swift runtime libraries. Test assemblies are excluded.

## Deterministic replay

Replay reads protocol events from a golden transcript instead of starting the engine. It performs
no network request and reads no token.

```powershell
dotnet run --project Windows/DevDeck.Shell -- --replay Tests/EngineTests/Golden/session-en.expected.jsonl
dotnet run --project Windows/DevDeck.Shell -- --replay Tests/EngineTests/Golden/session-ru.expected.jsonl
```

Screenshots must use these neutral golden sessions.

English replay:

![Protocol v2 English replay](../docs/poc/windows-ui/w3-pr1-session-en.png)

Russian replay:

![Protocol v2 Russian replay](../docs/poc/windows-ui/w3-pr1-session-ru.png)

The style reference replay uses the final GitHub review model and the plain project model from
the English golden session. It adds only the engine-owned `meta.place` values needed to show the
Windows and WSL variants:

```powershell
dotnet run --project Windows/DevDeck.Shell -- --replay docs/poc/windows-ui/windows-style-sample.jsonl
```

The left side of each comparison is the accepted HTML mock. The right side is the WPF renderer
at the same scale:

![Windows cards compared at 100 percent](../docs/poc/windows-ui/windows-style-comparison-100.png)

![Windows cards compared at 150 percent](../docs/poc/windows-ui/windows-style-comparison-150.png)

![Windows cards compared at 200 percent](../docs/poc/windows-ui/windows-style-comparison-200.png)

Live Acrylic and the solid fallback use the same neutral replay data:

![Windows cards with Acrylic](../docs/poc/windows-ui/windows-style-acrylic.png)

![Windows cards with transparency effects disabled](../docs/poc/windows-ui/windows-style-solid.png)

The shared button template gives every control a two-stroke keyboard focus indicator and distinct
hover, pressed and disabled states. The screenshot below shows hover on the left, pressed on the
right and the disabled Restart control in both halves.

![Windows button states](../docs/poc/windows-ui/windows-style-button-states.png)

## Backdrop behavior

The Windows 11 test confirms that a borderless WPF window receives the system backdrop when
`AllowsTransparency` stays false. DevDeck extends the DWM frame through the whole client area,
keeps the WPF composition target transparent, sets `DWMWA_SYSTEMBACKDROP_TYPE` to
`DWMSBT_TRANSIENTWINDOW`, opts into dark mode and asks DWM for rounded corners. On the tested
machine DWM returned backdrop value `3`, dark mode value `1` and corner preference value `2`.

The card surface adds the specified `#28282C` tint at 66 percent opacity. When Windows transparency
effects are off, it switches to the opaque `#2B2B2F` surface. The shell still leaves corner
clipping to DWM, so neither mode produces square corner artifacts.

## Live development

Run the shell against a locally built host:

```powershell
dotnet run --project Windows/DevDeck.Shell -- --engine .build\out\Products\Debug-windows-x86_64\DevDeckEngineHost.exe
```

The development commands add and remove a local project through the engine settings operation and
print the matching protocol answer:

```powershell
dotnet run --project Windows/DevDeck.Shell -- --add-project C:\projects\sample-api
dotnet run --project Windows/DevDeck.Shell -- --add-project \\wsl.localhost\Ubuntu-24.04\home\developer\sample-web
dotnet run --project Windows/DevDeck.Shell -- --remove-project project.sample-api
```

The host stores tokens in Windows Credential Manager. The shell contains no token storage code and
never reads a token.

## Current boundary

The shell renders the five card model kinds and collapsed rows, applies `deck.changed` and
`panels.changed`, reports measurements, moves and display changes, executes the supported system
effects and restarts a failed host. It shows the last stopped model and stopped status while the
host is unavailable.

The `reviewList` and `project` cards use the Windows visual system in
[`docs/windows-style.md`](../docs/windows-style.md). Other card kinds keep the protocol v2
renderer until W-4. The project log control is a 24 px icon button: `header.logHelp` is its
tooltip and `header.logIsOn` is its highlighted state. The phone icon appears only when the
engine supplies `header.phoneURL`; the QR interaction remains part of W-11.

The following protocol features are intentionally deferred:

- The engine menu model and tray UI are W-5.
- Notifications are W-6.
- Full per-monitor placement, mixed scaling, unplug and sleep behavior are W-7.
- The log window is W-8.
- Settings UI is W-10. The development flags are command line helpers only.
- Browser profiles and the full Windows and WSL terminal and folder behavior are W-11.
- Effects for logs, settings, menus, updates and application exit are logged by kind and ignored.

`openURL` uses the system browser. `openTerminal` and `revealFolder` use the Windows system tools.
