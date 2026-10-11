# 0035. Windows delivery: framework-dependent .NET, a per-user Inno Setup, no signature for the beta

Date: 2026-10-11

## Status

Accepted.

## Context

W-14 measured the delivery (docs/windows-delivery-size.md). The builder's output is 262 MiB
unpacked and 102 MiB zipped, 189 MiB of it the .NET shell with its embedded runtime. The Swift
runtime is 58 MiB and every one of its 19 DLLs is loaded, ICU alone 36 MiB, so there is nothing
to drop there. Trimming the .NET shell is refused by the SDK because the tray uses Windows Forms.
Framework-dependent publishing brings the delivery to 97 MiB unpacked and 34 MiB zipped, at the
price of needing .NET 10 Desktop Runtime on the machine.

An installer was due anyway: the shell keeps a Start Menu shortcut for notifications, a Run
value for starting at sign-in and a folder of notification assets, and nothing removes them.
MSIX would give identity for free but does not install without a trusted signature, and the
shell's notification and autostart paths are built for the unpackaged case.

Code signing costs money and identity checks that take days. The first Windows users are
colleagues who were told what they are installing.

## Decision

- **Framework-dependent .NET.** The shell is published with `--self-contained false`. The
  installer checks for .NET 10 Desktop Runtime and installs it from Microsoft when it is missing.
- **Inno Setup, per-user.** Installs under `%LOCALAPPDATA%\Programs\DevDeck` without
  administrator rights, creates the Start Menu shortcut with the AUMID the shell expects, and
  on uninstall removes the shortcut, the `DevDeck` Run value and
  `%PROGRAMDATA%\DevDeck\NotificationAssets`. It closes a running shell before installing and
  supports a silent mode, which is what the updater will call.
- **No signature for the beta.** The installer and the executables ship unsigned. SmartScreen
  will warn; the install notes say so and say why. Signing is W-16 and waits for a public
  release.

## Consequences

- A download about a third of today's, and a first start that needs the runtime once.
- The uninstaller is the first thing that cleans up after the shell; W-17 (updates) builds on
  the silent install rather than on a package manager.
- The beta's SmartScreen warning is a known cost, accepted for colleagues and not for the public.
