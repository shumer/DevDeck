# Windows update verification

The branch is based on main `84b7c26`. Verification date: 2026-10-11.

## What the shell does

`installUpdate` starts an asynchronous download through `IUpdateDownloader`. The HTTP adapter
follows redirects and writes the installer and checksum under
`%LOCALAPPDATA%\DevDeck\Updates\<version>`. It reports byte fractions bounded to 0..1 at most
once every 100 ms, including when sending a previous progress report took time.

No checksum URL means `update.failed` with `installer is not verified` before any download or
launch. The first word of the checksum file's first nonempty line must contain 64 ASCII hex
digits. SHA256 comparison ignores case. A mismatch removes the exe and returns
`checksum mismatch`. The shell does not construct update rows, buttons or progress text.

After a match, it reports `update.installing` and starts the exe with
`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS`. It keeps processing `--quit`.
If this shell is still alive 60 seconds later, it reports `installer did not finish; see <page>`.
The verified exe is retained for inspection and the next attempt overwrites it.

Replay records its outgoing intents in `--trace` and can read a streaming named pipe. The
private local harness forwarded those intents to a DeckSession built from `bedc917`, with a
fake release response, and returned the session's events unchanged. The runtime supplied the
downloading, installing and failure rows. Closing replay cancels an outstanding read and
download; window cleanup runs on the dispatcher.

Swift sources, the protocol, signing, CI and installer code are unchanged.

## Local checks

Windows 11 25H2, build 26200.9457; Swift 6.4 with assertions; .NET SDK 10.0.401;
.NET Desktop Runtime 10.0.12; Inno Setup 6.7.3.

| Check | Result |
|---|---|
| dotnet build Windows/DevDeck.Windows.slnx -warnaserror | Passed, no warnings. |
| DevDeck.Shell.Tests | 111 passed, 0 failed. |
| Build-WindowsInstaller.ps1 | Passed; framework dependent delivery and quiet Inno installer. |
| Windows swift build | Passed; no project warnings. |
| DevDeckWindowsCoreTests | 15 passed, 0 failed. |
| DevDeckEngineTests on 84b7c26 | 26 passed, 0 failed; all 11 transcripts matched byte for byte. |

The final `DevDeck-Setup-0.19.2.exe` is 24,004,578 bytes.

The new shell tests cover parsing with and without a checksum, matching and mismatched fixture
hashes, uppercase checksums, malformed checksum text, quiet installer arguments, an absent
checksum, deletion after a mismatch, bounded and throttled progress, launch failure,
cancellation during the installer wait and the 60 second failure with its release page.
Replay tests cover outgoing failure intents, asynchronous reads and Quit while a pipe stays
open. Network downloads are behind an interface and are not performed by the test suite.

The Swift build, both Swift suites, the .NET build and the shell suite were repeated after
rebasing onto `84b7c26`. No golden file was changed or regenerated.

## Live checks

The local server served the current branch's installer as `DevDeck-Setup-9.0-1.exe` and a
checksum file. The test release used version 9.0 so the engine could offer it; the actual
installer carried VERSION 0.19.2. A 302 redirect led from the asset address to the exe. The
server listened on localhost. All settings and project names were neutral; no token was typed
or logged. Temporary hosts, transcripts and server code stay outside the repository.

| Scenario | Result |
|---|---|
| Valid uppercase SHA256 | Download progress appeared in Settings, then Installing 9.0. The real installer asked the waiting replay to quit; replay exited with code 0. A new installed shell and DevDeckEngineHost started. |
| Installed files | The installed shell DLL matched the delivery's SHA256 after replacement. |
| Card positions | The new installed host opened Sample Windows at [1156,28,352,183] and Sample WSL at [1156,222.223,352,183], matching the saved frames. |
| Settings | The user's existing preferences files kept their hashes. The neutral profile kept both stored placements. |
| Wrong SHA256 | update.failed carried checksum mismatch. The downloaded exe was absent, no installer was launched and replay stayed alive with Try Again. |

The final successful trace contained 95 progress reports. The shortest interval between
sent reports was 102.4 ms. Both live scenarios were repeated with the final shell build.

Screenshots are actual captures of the live replay window with engine supplied models:

- [Downloading](windows-ui/w17-update-downloading.png).
- [Checksum failure](windows-ui/w17-update-failed.png).

## Cross-platform fixture

Main `84b7c26` makes the update platform injectable and pins the settings golden scenario
to Mac. The shell branch contains no Swift change and does not regenerate any transcript.
The live installer checks above used `bedc917`; this fixture fix keeps the production default
at the current platform and does not change the shell's download or installation path.

## Not checked

A published Windows update was not available, so the live download used the local server
instead of a GitHub release. The 60 second installer timeout was tested with a controlled
clock, not by leaving a real installation stalled. The missing .NET runtime and UAC path,
signature verification and Mac checks were not performed.
