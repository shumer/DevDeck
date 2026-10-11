# Windows release verification

The branch starts at main `8202b7b`. Verification date: 2026-10-11.

## Release behavior

The existing Mac job builds first. The Windows installer job depends on it, installs the
same Swift 6.4 toolchain as tests.yml, installs .NET 10 and Inno Setup, then builds and runs
the Windows core, engine and shell suites before packaging. The Mac executable suite runs
in the first job. The warning filter permits only the exact WinSDK warning for swiftlang/swift#91000.

Published releases and manual runs with attach=true check out the tag with full history.
Both packages use the root VERSION and `git rev-list --count HEAD`. Windows uploads
`DevDeck-Setup-<version>-<build>.exe` and `.exe.sha256`; the checksum file contains a lowercase
SHA256, two spaces and the filename. The Windows installation paragraph is appended after
the Mac job edits the notes. Repeated runs replace the managed paragraphs.

With attach=false, both jobs check out the dispatched branch commit and upload Actions
artifacts only. The existing tag is a label for this check, not its source. This exception was
approved because v0.19.2 predates the Windows shell and installer. Existing release files and
notes are not changed.

The builder discovers Visual Studio using [vswhere](https://github.com/microsoft/vswhere),
with the two previous BuildTools paths as fallbacks. It preserves process PATH and Swift SDK
variables provided by hosted setup actions. tests.yml, the engine, signing and the updater
are unchanged. UpdateCheck still chooses the Mac ZIP. Choosing the Windows installer and
checking its checksum belong to W-17; this workflow requires no engine change.

## Local checks

On Windows 11 25H2 with Swift 6.4, .NET SDK 10.0.401 and Inno Setup 6.7.3:

| Check | Result |
|---|---|
| Build-WindowsShell through Build-WindowsInstaller | Passed using the locally discovered Visual Studio BuildTools. |
| Installer compilation | Passed. Local setup size: 23982771 bytes. |
| Windows swift build | Passed without warnings. |
| DevDeckWindowsCoreTests | 15 passed, 0 failed. |
| DevDeckEngineTests | 26 passed, 0 failed. |
| dotnet build Release -warnaserror | 0 warnings, 0 errors. |
| DevDeck.Shell.Tests | 98 passed, 0 failed. |
| actionlint and PowerShell syntax checks | Passed. |

## Hosted check

[Run 28, attempt 1](https://github.com/shumer/DevDeck/actions/runs/38167269092), ID 38167269092, passed on both
jobs. It tested commit `ebcee2a`, with version 0.19.2 and build 328, using:

```powershell
gh workflow run release.yml --ref win/W-18-release -f tag=v0.19.2 -f attach=false
```

| Job | Duration | Result |
|---|---|---|
| build | 3 minutes 18 seconds | Success. |
| windows-installer | 9 minutes 43 seconds | Success. |

| Downloaded file | Bytes | MiB |
|---|---:|---:|
| DevDeck-0.19.2-328.zip | 3044502 | 2.90 |
| DevDeck-Setup-0.19.2-328.exe | 24014617 | 22.90 |
| DevDeck-Setup-0.19.2-328.exe.sha256 | 95 | 0.00009 |

The Mac runner used Apple Swift 6.3.3 on macOS 26. The Windows runner used Swift 6.4 RELEASE
with assertions, .NET 10 and Inno Setup 6.7.1 from Chocolatey. Visual Studio discovery and the
installer build succeeded on windows-latest without fixed BuildTools paths.

| Hosted suite | Result |
|---|---|
| Mac executable tests | 521 passed, 0 failed. |
| Mac engine tests | 23 passed, 0 failed. |
| Windows core tests | 15 passed, 0 failed. |
| Windows engine tests | 26 passed, 0 failed. |
| Windows shell tests | 98 passed, 0 failed. |

The Credential Manager test passed on the hosted runner. No test was disabled. Both
jobs skipped release uploads and note edits. The existing v0.19.2 release body and asset names,
sizes and update timestamps were unchanged before and after the run.

## Installation of the runner artifact

The downloaded SHA256 matched the installer:

```text
109736daf8b5299fd82ef9923b15a9dfc68c4389d4d62c132449ee8f4dbe28d3  DevDeck-Setup-0.19.2-328.exe
```

The unsigned runner setup was installed on the laptop over a running per-user installation,
using `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS`. It returned exit 0,
closed the previous shell and host, and automatically started exactly one new shell and host.
No restart or elevation was needed because .NET 10 Desktop Runtime was already present.

The live check used an isolated profile with two neutral project cards. The new host returned
both cards with places Windows and WSL · Ubuntu-24.04. Saved placements were unchanged, and
panel frames after installation and restart matched the previous host exactly:

| Card | Frame in primary display DIP |
|---|---|
| Sample Windows | [1156, 28, 352, 183] |
| Sample WSL | [1156, 222.223, 352, 183] |

No project server was started for this check. The temporary WSL folder was removed, and the
installed shell was then started with the normal user settings. No token was entered, exported or logged.

Publishing with attach=true was not exercised, so existing releases were not overwritten.
The missing runtime download and UAC path were not exercised, as in W-15. No local Mac checks
were run; the Mac results above are from GitHub Actions. Windows signing, ARM64 and Windows
updater behavior remain outside this task.
