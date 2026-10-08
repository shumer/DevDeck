# One-engine POC report

Date: 2026-10-08. Scope: step 1 on Windows x64.

## Acceptance status

| Question | Result | Evidence or remaining work |
| --- | --- | --- |
| Q1: native Windows core | Accepted with an external toolchain exception | Project code builds without warnings. Remaining warnings originate in the Swift 6.4 WinSDK module, tracked by swiftlang/swift#91000. Windows tests: 8 passed, 0 failed. User-run Mac tests: 405 passed, 0 failed; Mac build has no warnings. |
| Q2: real authenticated GitHub | Not tested | Offline cache and unauthorized-response tests pass. These do not qualify a real provider or account. |
| Q3: real WSL lifecycle | Not tested | Windows adapters are implemented. Real start, restart discovery, whole-tree stop, timeout and cancellation checks await step 2. |
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
| POC distribution | Ubuntu-24.04, installed; user initialization pending |
| Checkout | C:/src/DevDeck |
| Branch | poc/one-engine |

Dependencies were installed following [Swift's Windows instructions](https://www.swift.org/install/windows/).
The Swift installer was verified against the SHA256 in the WinGet package manifest.
GitHub CLI and Ubuntu-24.04 were installed after Q1 acceptance to prepare step 2.
GitHub authentication and Linux user initialization are pending user action. No real WSL
project commands have been tested yet. .NET 10 SDK installation is planned for step 4.

## Implementation

The Windows package branch builds the three core targets and a separate test executable.
The original Mac package declaration was compared with the baseline and is unchanged.
DevDeckApp and DevDeckUI sources were not modified.

Windows uses FoundationNetworking when available, in-memory tokens, unsigned code identity,
stderr logging, Foundation geometry and atomic file preferences. Foundation's Windows
UserDefaults has an unavailable Sendable conformance, so the Mac backend is guarded and
Windows uses the file backend instead. The login-shell PATH and LAN probes are excluded.

The Windows command runner selects a WSL distribution, streams both pipes and supports task
cancellation and timeout. Local project runtime files live in WSL, with bash for detached
starts and liveness checks in the owning distribution. These adapters have not yet passed
real WSL lifecycle acceptance.

## Verification

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

The failure-write test deliberately emits a fixed stderr diagnostic. No live credential was
requested or used. git diff --check passes. Only neutral fixture data was added.

The user ran Mac checks on the step 1 patch applied over f8db218: run-tests.sh reported
**405 passed, 0 failed**, and swift build completed without warnings. The user also verified
that the Mac portion of Package.swift is byte-for-byte identical to main. These checks were
performed by the user on a Mac, not on this Windows machine. Windows ARM64 remains untested.

## Conditional code by file

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
