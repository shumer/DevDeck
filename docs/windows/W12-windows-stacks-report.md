# W-12 Windows stack checks

Branch: `win/W-12-stacks`. Base: `402ff42`, including the engine changes in `e4f1671`.

## Implementation

The shell executes `launchDocker` by starting the standard Docker Desktop executable
without waiting. Every state, message and action remains in the engine model.
Both lifecycle tools accept `ddev-start`, `ddev-status`, `ddev-stop` and `docker-format`.
DDEV project ids in their configuration must match the DDEV project names.

Live checks found three engine issues. They are separate commits:

- `0493189`: a native list from a shared Docker daemon could replace the correct WSL
  record. Status now uses the project's own place and candidate merging prefers a
  reachable record over an unknown duplicate.
- `6b2ed82`: Arc compared Linux compose labels with a UNC folder and reported its own
  stack as a different checkout holding the port. Windows comparisons use the Linux
  path of the configured WSL folder. Native DDEV candidates also exclude Linux folders
  that its client cannot use.
- `3065a80`: an unavailable native DDEV client was presented as a project missing from
  a successful list. A typed status flag now supplies `ddev.silent.*` in the Windows
  card model and disables Start. Mac card presentation is unchanged.

## Local checks

- Swift 6.4.0, .NET SDK 10.0.401.
- `swift build`: passed, no project warnings.
- `DevDeckWindowsCoreTests`: 15 passed, 0 failed.
- `DevDeckEngineTests`: 25 passed, 0 failed. All 11 golden transcripts matched.
- `dotnet build Windows/DevDeck.Windows.slnx -warnaserror`: passed, 0 warnings.
- `DevDeck.Shell.Tests`: 71 passed, 0 failed.
- Mac checks were not run locally. CI checks both platforms.

## Live checks

Docker Desktop served daemon 29.8.2. DDEV was 1.25.4 on Windows and Ubuntu-24.04.
The native portable DDEV directory was also verified in the system user PATH through
the registry provider. The neutral Arc project used Fusion CLI 3.3.0 with Node 24.21.0 in Ubuntu.
No tokens were entered. The test deck had isolated preferences and neutral projects.

| Check | Result |
| --- | --- |
| Docker Desktop absent | DDEV and Arc cards showed the engine's Docker gate and Start Docker action. |
| Docker launch | A live host emitted `launchDocker`; the real shell started Docker Desktop. Existing polls recovered without restarting that host. |
| Native DDEV candidates | The candidate used a Windows project folder and `addDDEVProject` returned its id. |
| WSL DDEV candidates | With a project configured in Ubuntu, the candidate used a `\\wsl.localhost\Ubuntu-24.04\...` folder and addition succeeded. |
| DDEV actions | Start, Stop and Restart ran through the commands supplied by each project's card model. Both sites and both Mailpit URLs returned HTTP 200. |
| DDEV survival | Separate starter processes exited; new status processes reported running; new stop processes reported stopped. |
| DDEV logs | Native and WSL hosts returned real lines with source `ddev logs -s web`. |
| Native DDEV absent | Removing the portable native executable did not affect the WSL client or crash the host. The Windows model uses the unavailable CLI message. |
| Arc WSL | Actual `npx fusion daemon` started the stack. The card reported running and 9 containers; `/release` returned HTTP 200. Stop and Restart worked through the host. |
| Arc logs | The host returned real lines with source `docker logs fusion-engine`. |
| Docker quoting | Native `cmd /d /s /c` and WSL Bash produced identical version and compose label output, including tabs. No runner fix was needed. |

A first WSL format query during the initial Fusion image downloads failed with
`WSL command timed out; its cleanup could not be verified`. The retry after downloads
completed passed and matched the native output. It did not repeat in the later checks.
Fusion's first launch also needed its required external cache volume. Only the neutral
test project's volume was created. Node 18 could not run this CLI dependency set; Node 24
was installed inside the test workspace.

Actions were exercised through the commands from the card models. An automated mouse
click on the nonactivating card windows was not used.
Native Arc was not tested because Fusion does not support it.

## Real captures

These PNGs contain actual screen pixels from the Windows shell. Card captures are from
the live neutral deck. Log windows replay the unmodified `log.changed` events collected
from those live projects. No composite or renderer export was used.

- [DDEV Docker gate](ui/w12-ddev-docker-off.png).
- [Arc Docker gate](ui/w12-arc-docker-off.png).
- [Native DDEV running](ui/w12-native-ddev-running.png).
- [WSL DDEV running](ui/w12-wsl-ddev-running.png).
- [Arc WSL running](ui/w12-wsl-arc-running.png).
- [Native DDEV log](ui/w12-native-ddev-log.png).
- [WSL DDEV log](ui/w12-wsl-ddev-log.png).
- [Arc log](ui/w12-arc-log.png).
- [Native DDEV unavailable](ui/w12-native-ddev-unavailable.png).

## Cleanup

Both final DDEV cycles passed in separate invocations: Start reported running, a new
Status process reported running, and a new Stop process reported stopped. The Arc test
stack was stopped through the host. The format-check container was removed and temporary
shell instances were closed. The Start Menu shortcut was restored to the installed shell.
Neutral project folders and downloaded development tools were retained outside the repo.
