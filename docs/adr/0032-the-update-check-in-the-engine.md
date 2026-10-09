# 0032 - The update check is the engine's, and installing is the shell's

## Status

Accepted, 2026-10-09. Part of [0024](0024-one-engine-two-shells.md). Keeps every rule of
[0016](0016-self-update.md) and [0017](0017-signature-decides.md).

## Context

`Updater` did two jobs. It watched for a newer build (when to ask GitHub, what counts as newer,
announcing a version once, waiting for a card in the middle of a command before installing) and
it installed one (downloading, unpacking, checking the bundle and its signature, swapping it in,
relaunching). The words about it were spread over three places: the menu built the update's row,
the settings page worded its status line, and the app delegate decided whether the banner was
wanted. The first job is the same on Windows; the second is not, since a Windows build is a
different archive put in place a different way.

## Decision

`DeckUpdates` in the engine, made by `DeckRuntime.watchForUpdates(currentVersion:canInstall:http:)`,
owns the watch: the schedule (`UpdateCheck.firstCheckDelay`, then `UpdateCheck.interval`), the
check, the state, the one banner per version as an effect with its words, the wait for a card
that is mid-command, the menu's update row and the settings row. When someone chooses to install,
it hands the shell the update; the shell reports the download, the install and a failure back.

`Updater` on the Mac is the installer: everything after "install this".

## Consequences

- The watch is tested without a network or a bundle, in the suite's Updates sections: once per version, a
  quiet failure in the background and a loud one when asked, the wait for a busy card, progress
  and failure on the row.
- A Windows shell writes only its installer (W-17), with its own archive and signature check.
- The asset `UpdateCheck` picks is still the Mac's zip. Choosing a platform's asset comes with
  the Windows release (W-18).

## Alternatives

- **Leaving the updater whole on the Mac** and writing a second one for Windows. The rules about
  when to ask and when to wait would exist twice, and they are the ones that took two releases to
  get right.
