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

The dry run and installation of its downloaded artifact are pending. Run number, job durations
and artifact sizes will be recorded here after that verification. No local Mac checks were run.
