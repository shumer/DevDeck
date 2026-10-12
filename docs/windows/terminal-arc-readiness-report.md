# Terminal selection and Arc launch checks

Base: main `be9f77b`. Branch: `win/terminal-arc-readiness`. Verification: 2026-10-12.
Windows 11 25H2, build 26200; Swift 6.4 with assertions; .NET SDK 10.0.401.

## Changes

General shows terminal applications and Windows Terminal profiles. The host discovers installed
applications and profile GUIDs; the engine supplies every title, row, option, selected value
and saving request. Changing application clears the profile. The choice is stored separately
from the common preferences wire model and carried in `openTerminal`. WSL folders always keep
their own distribution and Linux directory. Interactive selection does not change background
project runners or any PowerShell execution policy.

Arc launch readiness is enabled by the Windows host. It checks the configured folder and start
command, Node, npx and a local or global installed Fusion binary. It does not install packages
or run the start command as a probe. Custom Node commands check their script; other custom shell
code is identified as checked at run time. Missing requirements disable Start and Restart in
the engine's model. An actual Start or Restart repeats the check and probes Docker in the same
project runner before executing the lifecycle command. Editing the start command asks the
settings form to check again. A healthy stack retains Stop.

Discovery uses the registered Windows user folder. An App Execution Alias is detected through
GetFileAttributesW because Swift Foundation reports that wt.exe alias as absent. An offline
attribute fixture covers a reparse point, an absent file and a directory. Direct PowerShell
resolves its installed executable even when the existing process PATH does not include it.

The W-17 branch, updater, installer and CI are unchanged. Mac launch behavior is unchanged;
the shared settings form also requests a new check after an Arc start command changes.

## Verification

| Check | Result |
| --- | --- |
| Windows swift build | Passed, no warnings. |
| DevDeckWindowsCoreTests | 17 passed, 0 failed. |
| DevDeckEngineTests | 37 passed, 0 failed. |
| Existing golden transcripts | All 11 matched byte for byte; none regenerated. |
| dotnet build -warnaserror | Passed, no warnings. |
| DevDeck.Shell.Tests | 113 passed, 0 failed. |
| Shell operators in Arc environment values | A regression first failed on an ampersand. Redirection and compound commands are now left untouched during preflight; the test passes. |
| Build-WindowsShell.ps1 | Passed to dist/terminal-readiness. |
| Windows missing Fusion CLI | Check Now returned Not ready to start with the install instruction. No enabled Start; a direct Start intent was also blocked. |
| WSL missing Fusion CLI | Same result in Ubuntu-24.04, with an isolated global npm prefix. |
| Installed WSL CLI | The existing neutral WSL Fusion fixture passed launch requirements; its stopped health endpoint remained reported as Stopped. |
| Custom Node command | Passed without requiring Fusion. Start reached running through the new host; Stop reached stopped. |
| Terminal choice | The real host discovered Windows Terminal, Command Prompt and Windows PowerShell, saved the Command Prompt profile GUID and carried it in the effect. |
| Real terminal launch | The published shell's effect handler opened a cmd.exe tab and a WSL tab. The new WSL client command line was wsl.exe -d Ubuntu-24.04 --cd /var/tmp/devdeck-terminal-readiness. |
| Language | The same host returned the translated terminal group after changing language to Russian. |

The live host used an isolated neutral preferences file and a separate sample account id with
no token. Recorded replays exclude the terminal launch effects. No real token was typed or
logged. Temporary harnesses, traces and projects remain outside the repository.

## Limits

Mac checks were not run here. The full Arc Fusion stack was not started in this pass; the
installed WSL CLI was checked and the neutral Docker Node fixture covered Start and Stop.
The terminal launch used the Command Prompt profile. PowerShell plans and quoting are covered
by offline tests. Preview and canary Terminal discovery locations were not checked live.
The live WSL folder was also visible in its prompt while bringing Settings to the foreground.
Terminal windows are not included in the repository screenshots. A CI run has not been requested.

## Screenshots

Actual captures of the published shell running recorded neutral settings events:

- [English General](ui/terminal-settings-en.png).
- [Russian General](ui/terminal-settings-ru.png).

The Russian capture starts a new session in Russian so all startup models use that language.
The live language change check separately confirmed that the terminal group changes immediately.
