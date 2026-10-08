# One-engine POC report

Date: 2026-10-08. Scope: accepted step 1 and step 2 implementation on Windows x64.

## Acceptance status

| Question | Result | Evidence or remaining work |
| --- | --- | --- |
| Q1: native Windows core | Accepted with an external toolchain exception | Project code builds without warnings. Remaining warnings originate in the Swift 6.4 WinSDK module, tracked by swiftlang/swift#91000. Windows tests: 8 passed, 0 failed. User-run Mac tests: 405 passed, 0 failed; Mac build has no warnings. |
| Q2: real authenticated GitHub | Live result pending | Native host and GitHubKit integration build. User-operated hidden-input smoke check is ready. Offline unauthorized-card checks pass in en and ru. PR GraphQL and REST ETag/304 are separate checks. |
| Q3: real WSL lifecycle | Verified with an explicit environment prerequisite; acceptance pending | Native host start/health/restart discovery/stop pass. Linux timeout and cancellation cleanup pass. Default WSL idle shutdown fails persistence; approved instanceIdleTimeout=-1 is required. |
| Q4: identical transcripts | Not started | Engine, host and cross-platform transcript tests await earlier acceptance. |
| Q5: thin WPF shell | Not started | No Windows desktop shell exists yet. |
| Q6: measurements | Not started | Host size, startup, idle memory, CPU and mixed-DPI behavior remain unmeasured. |

The user accepted Q1 on 2026-10-08 with the external WinSDK warning exception. Step 2 may
proceed after GitHub CLI authentication and the initial branch push. Recheck a clean Windows
build when a Swift release fixes issue 91000, and record whether the external warnings disappear.
Q1 acceptance does not establish the later POC answers.

## Environment

| Tool or location | Value |
| --- | --- |
| Architecture | AMD64, x86_64-unknown-windows-msvc |
| Swift | Swift 6.4, swift-6.4-RELEASE, assertions enabled |
| Swift compiler | %LOCALAPPDATA%/Programs/Swift/Toolchains/6.4.0+Asserts/usr/bin |
| Swift SDK | %LOCALAPPDATA%/Programs/Swift/Platforms/6.4.0/Windows.platform/Developer/SDKs/Windows.sdk |
| Visual Studio Build Tools | 2022, installer package 17.14.41, installation version 17.14.37710.0 |
| Build Tools location | C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools |
| Windows SDK | 10.0.22621.0 |
| Git | 2.54.0.windows.1 |
| GitHub CLI | 2.102.0 |
| WSL | 2.7.3.0, kernel 6.6.114.1 |
| POC distribution | Ubuntu-24.04, initialized by user; live checks use a normal Linux account |
| Checkout | C:/src/DevDeck |
| Branch | poc/one-engine |

Dependencies were installed following [Swift's Windows instructions](https://www.swift.org/install/windows/).
The Swift installer was verified against the SHA256 in the WinGet package manifest.
GitHub CLI and Ubuntu-24.04 were installed after Q1 acceptance to prepare step 2.
GitHub CLI authentication was verified for the repository owner. The accepted step 1 was
committed as 5dc5704 and pushed to poc/one-engine. Further exchanges use this branch.
The user initialized a normal Linux account. Project configuration selects Ubuntu-24.04;
no WSL default distribution is used.
.NET 10 SDK installation is planned for step 4.

## Step 2 preliminary WSL lifecycle probe

WSL 2.7.3.0 with Ubuntu-24.04 uses systemd. A neutral demo started two Python HTTP servers
on ports 8765 and 8766 under a nohup bash wrapper. The first short launch did not produce a
working service after the client exited, so an immediate background launch is not yet qualified.

A repeat in a persistent demo directory kept the launching session open until both Linux
listeners were present and Windows localhost requests returned HTTP 200. After every wsl.exe
client exited, both ports still returned HTTP 200 at 99 seconds. No WSL client was kept open
during that idle interval. Reading the stored PID and checking kill -0 used one WSL invocation.
The wrapper and two Python processes were then stopped inside Linux; verification found no
live probe processes and no listeners on either port, with zero remaining wsl.exe clients.

These short preliminary probes were insufficient: a longer check under the normal Linux
account later found that Ubuntu had shut down. A subsequent invocation showed a new Linux
boot time, and both servers were gone. nohup and setsid do not prevent WSL idle shutdown.

With explicit user approval, `%USERPROFILE%/.wslconfig` was created with `[general]` and
`instanceIdleTimeout=-1`. This disables automatic distro shutdown globally. Only Ubuntu-24.04
was explicitly restarted; other distributions were not stopped. The setting is documented
by [Microsoft](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#general-wsl-settings)
and supported by the installed WSL 2.7.3 source. Systemd alone does not guarantee persistence.

## Step 2 implementation and verification

DevDeckEngine and DevDeckEngineHost build natively for Windows x64. No Swift engine or UI
runs inside WSL. The host also has a Mac target, but step 2 Mac verification is pending user
execution. DevDeckApp and DevDeckUI remain unchanged. Package.swift now adds the engine,
host, resource and offline-test targets to the Mac graph; the byte-identical claim below
applies only to the accepted step 1 patch.

The JSONL host accepts protocol v2 intents, bounds each line to 1 MiB, correlates intent
events by id and emits monotonic revisions. Invalid input is never copied to diagnostics.
EOF cancels and awaits pending work. Credentials enter through stdin and remain memory-only.
Models use the existing PR ordering, ticket split, statusCode, blocked count, footer and
localization tables. The engine owns action availability and measured layout. Project polls
use StateSettler; PR polling uses RefreshPolicy and retains the last good CardState on failure.

Windows Foundation crashed while expanding a stringsdict plural marker. The Windows adapter
now reads the existing plural dictionaries and selects the count form before formatting.
The Mac plural implementation is preserved. English and Russian counts, including 11 and
21, are covered by offline tests.

The native host's real project checks observe starting followed by running from Windows
localhost health. After host exit, a new host discovers the project as running. Stop removes
the Linux wrapper and both Python servers: ports 8765 and 8766 are free, and no demo processes
remain. These results require the approved WSL idle setting. A separate 184.3-second idle
check sampled Windows process presence every five seconds, observed zero wsl.exe clients
throughout and received HTTP 200 from both ports at the end.

Cancellation and timeout checks run a TERM-ignoring wrapper with a child in a separate Linux
session. Both checks verify no live Linux process remains, not merely the disappearance of
wsl.exe. The runner uses --exec to avoid an extra shell expanding PID variables. Cleanup
collects descendants before sending signals and tags operation descendants in their Linux
environment so a changed process group does not lose ownership. Project PID records also include boot identity
and start time to reject stale or reused PIDs. PID validation and kill -0 share one invocation.
The unused Windows ProcessLiveness implementation has been removed.

DevDeckEngineTests reports **6 passed, 0 failed** on Windows; the Windows core suite remains
**8 passed, 0 failed**. The host black-box check accepts an exact-1-MiB CRLF message, rejects
oversized and malformed messages, emits only valid ordered JSON events, does not echo input
and exits cleanly on EOF. The Mac engine suite skips the Windows
single-invocation liveness check. run-tests.sh now includes the engine tests on an unfiltered
Mac run; those new results must not be confused with the accepted step 1 results below.

The live network helper is compiled and awaits a user-entered credential through hidden
PowerShell input. It prints only counts, rate-limit metadata and check results. It does not
read GitHub CLI tokens. PowerShell execution-policy blocking was handled with a policy limited
to that helper process. No authenticated network result has been claimed yet.

Q2 has a specification mismatch: PullRequestsService uses GraphQL POST, whereas GitHub's
[conditional-request support](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api)
applies to GET. The existing PR query is retained. The live tool separately checks authenticated
PR fetching and REST /user ETag/304 through GitHubClient. This distinction requires explicit
acceptance; no PR response is claimed to return 304.

Recommendation: keep step 3 gated on step 2 acceptance, live Q2 evidence and user-run Mac
checks. Q3 is viable with the approved global idle-policy prerequisite, and is not viable
on the observed default idle policy.

## Implementation

The Windows package branch builds the three core targets and a separate test executable.
For step 1, the original Mac package declaration was compared with the baseline and was unchanged.
DevDeckApp and DevDeckUI sources were not modified.

Windows uses FoundationNetworking when available, in-memory tokens, unsigned code identity,
stderr logging, Foundation geometry and atomic file preferences. Foundation's Windows
UserDefaults has an unavailable Sendable conformance, so the Mac backend is guarded and
Windows uses the file backend instead. The login-shell PATH and LAN probes are excluded.

The Windows command runner selects a WSL distribution, streams both pipes and supports task
cancellation and timeout. Local project runtime files live in WSL, with bash for detached
starts and liveness checks in the owning distribution. These adapters have not yet passed
real WSL lifecycle acceptance at the time of the step 1 record. Step 2 evidence is above.

## Step 1 verification

Command, from a Visual Studio Developer PowerShell with Swift's runtime paths:

```powershell
swift build --product DevDeckWindowsCoreTests -Xswiftc -warnings-as-errors
```

The first successful build completed in 56.93 seconds. A separate clean build completed in
95.63 seconds and emitted 12 SDK warning diagnostics, each rendered twice. These are build
measurements, not application startup measurements. The diagnostic is the wchar_t module
lookup problem described in [Swift issue 91000](https://github.com/swiftlang/swift/issues/91000).
The warning appears despite warnings-as-errors. Diagnostics were not suppressed.

The deprecated native build backend reproduced the SDK warning. A source-level import and
an implicit compiler import of Clang's standard definitions module did not remove the warning
from a clean build; neither experimental workaround is retained in the project.

The separate Windows test executable reports **8 passed, 0 failed**:

- Conditional response cache and ETag propagation using fixture HTTP responses.
- Unauthorized response stays an error and is not retried.
- Standard Windows token stores are isolated and memory-only.
- Windows code identity is unsigned.
- Detached commands select bash and preserve quoted input.
- Existing project health status rules.
- Preference persistence, value types and removal across reopening.
- Failed preference writes retain the previous state.

The failure-write test deliberately emits a fixed stderr diagnostic. During step 1, no live credential was
requested or used. git diff --check passes. Only neutral fixture data was added.

The user ran Mac checks on the step 1 patch applied over f8db218: run-tests.sh reported
**405 passed, 0 failed**, and swift build completed without warnings. The user also verified
that the Mac portion of Package.swift is byte-for-byte identical to main. These checks were
performed by the user on a Mac, not on this Windows machine. Windows ARM64 remains untested.

## Accepted step 1 conditional code by file

Counts are non-empty lines enclosed by conditional compilation, excluding directive lines.
They include preserved Mac branches and comments, so they are not a count of new Windows
logic. The new Windows adapter files are entirely conditional.

| File | Conditional lines |
| --- | --- |
| `Package.swift` | 99 |
| `Sources/DevDeckCore/Cards/DeckLayout.swift` | 1 |
| `Sources/DevDeckCore/Cards/DeckParking.swift` | 1 |
| `Sources/DevDeckCore/Cards/PanelPlacement.swift` | 1 |
| `Sources/DevDeckCore/Configuration/FilePreferencesBackend.swift` | 63 |
| `Sources/DevDeckCore/Configuration/Preferences.swift` | 17 |
| `Sources/DevDeckCore/Networking/APITransport.swift` | 3 |
| `Sources/DevDeckCore/Networking/HTTPClient.swift` | 1 |
| `Sources/DevDeckCore/Process/CommandRunner.swift` | 133 |
| `Sources/DevDeckCore/Process/ProcessLiveness.swift` | 35 |
| `Sources/DevDeckCore/Process/WindowsCommandRunner.swift` | 128 |
| `Sources/DevDeckCore/Security/CodeIdentity.swift` | 42 |
| `Sources/DevDeckCore/Security/TokenStore.swift` | 92 |
| `Sources/DevDeckCore/Support/Log.swift` | 23 |
| `Sources/ProjectKit/LocalProjectService.swift` | 78 |

## Current step 2 conditional code by file

Same counting convention as the step 1 record, including preserved Mac branches.

| File | Conditional lines |
| --- | --- |
| `Package.swift` | 131 |
| `Sources/DevDeckCore/Cards/DeckLayout.swift` | 1 |
| `Sources/DevDeckCore/Cards/DeckParking.swift` | 1 |
| `Sources/DevDeckCore/Cards/PanelPlacement.swift` | 1 |
| `Sources/DevDeckCore/Configuration/FilePreferencesBackend.swift` | 63 |
| `Sources/DevDeckCore/Configuration/Preferences.swift` | 17 |
| `Sources/DevDeckCore/Localisation/Strings.swift` | 23 |
| `Sources/DevDeckCore/Networking/APITransport.swift` | 3 |
| `Sources/DevDeckCore/Networking/HTTPClient.swift` | 1 |
| `Sources/DevDeckCore/Process/CommandRunner.swift` | 133 |
| `Sources/DevDeckCore/Process/DockerEnvironment.swift` | 18 |
| `Sources/DevDeckCore/Process/ProcessLiveness.swift` | 15 |
| `Sources/DevDeckCore/Process/WindowsCommandRunner.swift` | 220 |
| `Sources/DevDeckCore/Security/CodeIdentity.swift` | 42 |
| `Sources/DevDeckCore/Security/TokenStore.swift` | 92 |
| `Sources/DevDeckCore/Support/Log.swift` | 23 |
| `Sources/DevDeckEngineHost/main.swift` | 2 |
| `Sources/ProjectKit/LocalProjectService.swift` | 122 |
| `Tests/EngineTests/main.swift` | 11 |
