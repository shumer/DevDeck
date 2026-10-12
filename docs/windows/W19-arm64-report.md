# Windows ARM64 verification

The branch starts at main `23e95cec8d1b664b1f0aec5628d55e461747a270`.
Verification date: 2026-10-12.

## Machine and tools

The machine is a Microsoft Surface Laptop, 7th Edition with an ARM64 processor. It runs
Windows 11 Home 25H2, build 26200.9457.

| Tool | Version |
|---|---|
| Git for Windows | 2.51.0, `core.autocrlf=false` |
| Swift | 6.2.4 RELEASE with assertions, target `aarch64-unknown-windows-msvc` |
| .NET SDK | 10.0.401 ARM64, runtime 10.0.12 |
| Visual Studio | Community 2022 17.14.41, MSVC v143 ARM64 and Windows SDK 10.0.22621.0 |
| Inno Setup | 6.7.3 |
| PowerShell | 7.6.5 |
| Docker Desktop | 4.47.0, client and Linux engine 28.4.0 ARM64 |
| WSL | 2.7.14.0, Ubuntu 24.04.3 ARM64 |
| DDEV in WSL | 1.24.10 ARM64 |
| Node.js in WSL | 24.21.0 LTS ARM64, npm 11.19.0 |

Swift 6.4.0 ARM64 and 6.3.3 ARM64 crashed during process startup in `mimalloc.dll` on this
machine. The nearest usable official ARM64 toolchain is Swift 6.2.4. It also requires
`MIMALLOC_DISABLE_REDIRECT=1` on this Windows build. These are host toolchain limitations, not
repository changes.

## Build and test results

The clean baseline was taken from a tracked-source snapshot at `C:\src\DevDeck` before changes.

| Check | Result |
|---|---|
| `swift build --jobs 1` | Passed on ARM64 with no compiler warnings. |
| `DevDeckWindowsCoreTests` baseline | 17 passed, 0 failed. |
| `DevDeckEngineTests` baseline | 40 passed, 0 failed; every golden transcript matched. |
| .NET Release build with `-warnaserror` | Passed with 0 warnings and 0 errors. |
| `DevDeck.Shell.Tests` baseline | 113 passed, 0 failed. |
| Updated `DevDeckWindowsCoreTests` | 19 passed, 0 failed; logged `compiled=arm64, Windows=ARM64` and selected the ARM64 update asset. |
| Updated `DevDeckEngineTests` | 40 passed, 0 failed; every golden transcript still matched. |
| Hosted macOS release tests | Passed in release dry run 38227908499; `UpdateTests.swift` was compiled and the complete test step succeeded. |
| Hosted Windows x64 release build | Passed: 19 Windows Core, 40 Engine and 113 shell tests; installer produced. |
| Hosted Windows ARM64 release build | Passed natively on `windows-11-arm`: 19 Windows Core, 40 Engine and 113 shell tests; installer produced. |
| Workflow validation | PyYAML and actionlint 1.7.12 passed. |

Before Developer Mode was enabled, SwiftPM completed builds but emitted Win32 error 1314 while
creating its `.build\debug` and `.build\release` convenience symbolic links. After Developer Mode
was enabled, a native Windows symbolic-link probe succeeded without elevation. The committed
warning gate remains strict and the hosted ARM64 release build passed it; only the documented
WinSDK `wchar_t` warning was present.

## Delivery

`Build-WindowsShell.ps1 -Architecture arm64` selected the installed ARM64 Swift target, used
`win-arm64`, and wrote `dist\windows-arm64`. SwiftPM names its product directory
`aarch64-unknown-windows-msvc\release` with Swift 6.2.4. The builder accepts that layout and the
Swift 6.4 `out\Products\Release-windows-*` layout, while requiring the directory to match the
requested target architecture.

| Artifact | Files | Bytes | MiB |
|---|---:|---:|---:|
| ARM64 delivery | 27 | 105,992,566 | 101.082 |
| `DevDeck-0.20-windows-arm64-setup.exe` | 1 | 24,001,494 | 22.890 |

All delivered executables report PE machine `0xAA64`: `DevDeck.Shell.exe`,
`DevDeckEngineHost.exe`, `DevDeckProcessHost.exe`, and `DevDeckMCP.exe`.

Delivered runtime DLLs are `_FoundationICU.dll`, `BlocksRuntime.dll`, `dispatch.dll`,
`Foundation.dll`, `FoundationEssentials.dll`, `FoundationInternationalization.dll`,
`FoundationNetworking.dll`, `MSVCP140.dll`, `swift_Concurrency.dll`, `swift_RegexParser.dll`,
`swift_StringProcessing.dll`, `swiftCore.dll`, `swiftCRT.dll`, `swiftDispatch.dll`,
`swiftWinSDK.dll`, and `VCRUNTIME140.dll`. The framework dependent shell also carries
`Microsoft.Windows.SDK.NET.dll`, `QRCoder.dll`, `WinRT.Runtime.dll`, and `DevDeck.Shell.dll`.

The x64 baseline in `docs/windows-delivery-size.md` is 261.966 MiB and includes a much larger
single-file shell. The current framework dependent ARM64 output is 160.884 MiB smaller; this is a
publishing-layout difference as well as an architecture difference, so it is not an architecture
only size comparison.

## Live checks

| Scenario | Result |
|---|---|
| ARM64 delivery contents and PE headers | Passed. All required products, VERSION and runtime files are present; all EXEs are native ARM64. |
| Native shell and engine startup | Passed with an isolated `LOCALAPPDATA`. The shell started its delivery-local engine and both quit through `--quit`. |
| Cards, settings, tray, log, notification, Summon and light/dark theme | Partly checked. The native processes started, and a neutral ARM64 renderer capture was produced. Interactive UI coverage was not completed because the automation surface did not expose the shell's non-activating windows. |
| Windows, WSL, DDEV and Arc project Start, health, log and Stop | Not completed. Docker, DDEV and Node ARM64 prerequisites are present. |
| ARM64 installer build | Passed. Inno Setup compiled the architecture-specific runtime URL, registry key and filename. |
| ARM64 installer install, update and uninstall | Not completed. Machine-wide ARM64 Desktop Runtime 10.0.12 is now installed; the remaining installer lifecycle checks still require an isolated install/update/uninstall pass. |
| x64 installer refusal | Passed for the new rule. An x64 build of the same Inno script exited before creating its isolated target directory on ARM64. |
| Published v0.20 x64 installer refusal | Not run. v0.20 uses `ArchitecturesAllowed=x64compatible`, which Inno documents as allowing x64 emulation on ARM64. Running it would install instead of proving the expected refusal. W-19 changes the x64 rule to `x64compatible and not arm64`. |
| ARM64 update asset | Passed in native Windows Core tests. Explicit x64 and ARM64 selection is also covered in `UpdateTests.swift`; the hosted macOS release test step passed. |
| Full local update download and relaunch | Not completed; no ARM64 release asset exists yet. |
| MCP through Claude Code | Not completed. No token was entered or logged. |
| x64 delivery under emulation | Not completed; no unpacked x64 delivery was available locally. |

The neutral card capture was rendered by the ARM64 shell test binary from the existing golden
model. It contains no account, token or real project data:

![ARM64 neutral cards](ui/w19-cards.png)

Settings and installer screenshots are still pending with the interactive checks above.

## CI and release behavior

GitHub documents `windows-11-arm` as a standard hosted ARM64 runner. The pinned
`compnerd/gha-setup-swift` action supports `build_arch: arm64` and the official Swift 6.4 ARM64
download layout. Tests and release now share `.github/actions/windows-build`. The release workflow
keeps the existing x64 filename and adds
`DevDeck-<version>-<build>-windows-arm64-setup.exe` with its SHA256 file.

[Release dry run 38227908499](https://github.com/shumer/DevDeck/actions/runs/38227908499) passed on
commit `0b26ee1b0f5b1bc28b56e770ed2c45a3e0430efc` with `attach=false`. The macOS build, tests,
notarisation and package completed in 4 minutes 53 seconds. The native ARM64 Windows job completed
in 8 minutes 52 seconds and logged `compiled=arm64, Windows=ARM64`; the x64 job completed in
9 minutes 44 seconds and logged `compiled=x86_64, Windows=AMD64`. The dry run retained these
artifacts without modifying release v0.20:

| Artifact | Contents | Artifact bytes |
|---|---|---:|
| `mac-app` | Notarised macOS package | 3,665,862 |
| `windows-arm64-installer` | `DevDeck-0.20-349-windows-arm64-setup.exe` and SHA256 | 23,809,246 |
| `windows-installer` | `DevDeck-0.20-349-windows-setup.exe` and SHA256 | 24,484,737 |

The ARM64 installer itself is 24,308,945 bytes; the x64 installer is 24,984,256 bytes. GitHub
reported only action-runtime deprecation notices for Node.js 20 and a macOS runner capacity notice;
neither affected the builds.

## Source scope and limits

The only production file changed under `Sources` is
`Sources/DevDeckCore/Update/UpdateCheck.swift`. Shell product code did not change. Build scripts,
the installer definition, tests, workflows and Windows documentation carry the remaining changes.

Mac tests were not run locally, but the complete macOS release test step passed in the hosted dry
run. The remaining interactive items above need a separate Windows follow-up.
