# Windows / WSL feasibility probe

This is an isolated experiment in `Tools/WindowsProbe`, not a Windows release of DevDeck.
The production Swift targets and accepted macOS architecture remain unchanged. The user
authorized the experiment on 2026-09-30. The task plan and evidence live in `.local_docs`.

## Run

Requires Windows with .NET 8 SDK/Desktop runtime, an explicit WSL2 distribution with Python 3,
and Docker Desktop integration for the daemon check. No external .NET packages are used.
The checked-in Python worker is temporary probe code; it does not establish Swift portability.

From PowerShell in the repository:

```powershell
dotnet build Tools/WindowsProbe/WindowsProbe.csproj --nologo
dotnet Tools/WindowsProbe/bin/Debug/net8.0-windows/WindowsProbe.dll --distribution Ubuntu-24.04 --worker /home/ashumenko/Projects/DevDeck/Tools/WindowsProbe/worker.py
```

Change the distribution and Linux worker path for another checkout. `run.ps1` is a convenience
launcher, but Windows execution policy may block unsigned scripts from the WSL UNC share.
The direct commands above do not require changing the machine's execution policy.

Start creates an owned temporary HTTP server in WSL, with an ephemeral localhost port and
a harmless child process. Stop terminates that process session; Restart creates a new one.
Status is based on the server's health response and its unique probe marker. The worker reads
Docker's server version without modifying containers. Existing projects are never started or
stopped. Closing the card closes the worker input and cleans up its demo server. Temporary
diagnostic folders under `/tmp/devdeck-windows-probe-*` remain for inspection.

The header is the drag handle. The checkbox switches between Win32 bottom Z order and
topmost floating mode. The card intentionally has no blur, tray, persisted settings or tokens
yet. Bottom Z order is a candidate to test, not a guarantee of macOS desktop semantics.

## Automated checks

```powershell
dotnet Tools/WindowsProbe/bin/Debug/net8.0-windows/WindowsProbe.dll --self-test --report .local_docs/windows-probe-results.json
```

This live probe suite is separate from the application's offline Swift tests. It uses disposable
local processes, opens a sample WPF window briefly and writes a JSON report and PNG render.
Checks cover Docker readiness, JSON request correlation, health from WSL and Windows,
idempotent start, logs, restart, stop including the child, cleanup on worker EOF, rejection of
an unsupported action and a missing worker, and acceptance of both Z-order operations.

On 2026-09-30 the .NET build completed with zero warnings/errors and all 16 checks passed on
Windows 11 ARM64 + Ubuntu-24.04 aarch64, Docker server 28.4.0. The PNG was visually inspected;
it is an offscreen render of the sample card, not evidence of on-desktop behaviour.
Swift build/tests have not run because Swift is absent from the WSL PATH and macOS is unavailable.

## Manual desktop checks

Record each result as pass, fail or unavailable in `.local_docs/EVIDENCE.md`:

| Check | Expected result | Current result |
| --- | --- | --- |
| First click while another application is focused | Start or Status responds with one click | User-confirmed pass, 2026-09-30 |
| Desktop mode behind a normal application | Card stays covered; uncovered controls remain clickable | Pending |
| Win+D, twice | Behaviour is useful and recoverable; card never becomes permanently unreachable | User-confirmed pass, 2026-09-30 |
| Floating mode | Card stays above a normal window, toggling off returns it behind applications | User-confirmed pass, 2026-09-30 |
| Drag | Header moves the card without swallowing button clicks | User-confirmed pass, 2026-09-30 |
| Virtual desktop switch | Behaviour matches the agreed scope without lost windows | Pending |
| Mixed monitor DPI / hot-plug | Card remains readable and reachable | Pending |
| Fullscreen application | Desktop card does not interfere | Pending |
| Sleep/resume | Worker reconnect or actionable failure | Pending |
| Explorer restart / WSL shutdown | Recovery or actionable error; demo cleanup characterized | Pending; disruptive, run manually |

If Win+D or desktop placement fails, investigate an explicit summon/tray fallback before
choosing any Explorer-parenting technique. Do not restart Explorer/WSL automatically during
normal validation. Forced process termination, long-running cancellation, distribution loss,
certificates and VPN conditions remain outside the initial successful checks.

The user also confirmed Start/Restart/Stop status changes in the interactive card. These five
passes establish basic viability on the tested ARM64 workstation; they do not complete the
expanded desktop matrix. Sustained behaviour behind application windows remains a separate check.

## Later checkpoints

1. Disposable DDEV project, using the selected distribution and Linux paths. The Compose checkpoint below passed.
2. Actual Arc/Fusion compatibility, including Linux ARM64 images and tooling.
3. Swift toolchain installation/selection, portable Core dependencies and separate offline tests.
4. Production protocol, secure secrets, tray/summon, installer and macOS regression validation.
5. Update ADR 0001 and the roadmap only after accepting a production Windows direction.

## Compose checkpoint

Run with Windows Python 3 from PowerShell in the repository:

```powershell
python Tools/WindowsProbe/verify_compose.py --distribution Ubuntu-24.04 --worker /home/ashumenko/Projects/DevDeck/Tools/WindowsProbe/verify_compose.py --report .local_docs/windows-compose-results.json
```

The Windows verifier launches a persistent WSL worker through stdin/stdout. The worker creates
a unique temporary Compose project using `python:3.12-alpine` (pulled if absent), a random
loopback-only published port and a read-only bind mount from its own folder containing spaces.
No existing Compose project is operated. The worker removes its container and network on normal
completion/EOF; the image stays cached and the temporary folder remains for diagnosis.

On 2026-09-30 all 14 checks passed: WSL and Windows health, container ownership, Linux path
labels, bind mounts, logs, idempotent start, restart recovery, stop/start and final removal.
An independent check found no container/network left for the generated project. This is a
separate live verifier; the interactive card still controls the original disposable process demo.
DDEV-specific routing/certificates and actual Fusion remain untested.

## Existing-project inventory

The read-only inventory for this user's setup can be repeated from Windows:

```powershell
python Tools/WindowsProbe/inspect_existing.py
```

The script sends its probe code through stdin to Ubuntu-24.04 and Debian Python processes;
it does not install a probe into those project folders. It discovers Ubuntu DDEV through its
CLI and Debian Fusion checkouts under /home/ashumenko/Project, validates saved Compose files,
checks local CLI help and cached image architecture, and probes local endpoints from both
Linux and Windows. Saved output excludes arbitrary environment/token values and response bodies.

On 2026-09-30 it found five DDEV projects and two Fusion checkouts. Configuration/tool discovery
works, but all primary site endpoints are unavailable in the current stopped/paused state. The
Fusion CLI help commands succeed; port 27017 in both saved Fusion stacks is already occupied
by another project. The two distributions share Docker; per-project distribution selection is
required for subsequent prototype work. Full lifecycle and HTTPS trust remain untested.
Details are in .local_docs/WINDOWS_EXISTING_PROJECTS.md and windows-existing-projects.json.
