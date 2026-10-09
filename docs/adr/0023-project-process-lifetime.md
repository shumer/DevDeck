# 0023 - A project process does not depend on the app that started it

## Status

Accepted, 2026-10-09. Proven in the Windows proof of concept; carried into `main` as the WSL and
native Windows launchers of `ProjectKit`. The Mac behaviour of [0007](0007-plain-projects.md) is
unchanged.

## Context

A plain project is started from the deck and has to keep running when the deck quits, crashes or
updates itself. On the Mac `nohup` under a login shell is enough. On Windows it is not, twice over.

A detached Linux process does not keep a WSL distribution alive. With the default idle policy the
distribution stopped soon after the engine exited and took the dev server with it. Setting
`instanceIdleTimeout=-1` fixed that, but for every distribution on the machine, which is not a
setting an app gets to change.

A native Windows process started by the engine is in the engine's process tree and console. Kill
the engine and, depending on how it was started, the project goes too; keep it alive by detaching
and there is no reliable way to stop its children later.

## Decision

`LocalProjectService` keeps everything that is the same on every platform: the health check, the
wait for a start to answer, the order of a restart, the log. How a process is started, found again
and stopped belongs to a `ProjectProcessLauncher`, one per place a project can run.

**Mac** (`ShellProjectLauncher`): `nohup` under the login shell, process id in a file under
Application Support, stop walks the tree from that id. This is [0007](0007-plain-projects.md)
moved, not changed.

**WSL** (`WSLProjectLauncher`): a held command gets a WSL client of its own. `CreateProcessW` with
`DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP`, and a `STARTUPINFOEX` handle list restricted to
`NUL`, so the client cannot keep the engine's pipes open. The command runs in that client's
foreground under `setsid --wait`; while it runs, the distribution has a client and stays up, and
when it ends, normal idle shutdown resumes. Its Linux process id is recorded together with the boot
id and the process start time, written atomically, so a reused id is never taken for the project.
Stop freezes and collects the whole tree, including children that left the process group (found by
a `DEVDECK_PROJECT` variable in their environment), before any of it is signalled. A failed or
cancelled start publishes a cancellation marker and cleans up from a context of its own, so a
cancelled engine task cannot leave a half-started project behind.

Every WSL command passes through login shells, and a profile that loads nvm or conda takes seconds.
So the time limits are sized for that, and "WSL did not answer" is never read as "nothing is
running": Stop and Start report it on the card instead. With a three-second limit, a busy WSL once
made Stop return having done nothing, and the same limit on the start check would have stopped a
project that was only slow to come up.

**A Windows folder** (`NativeWindowsProjectLauncher`): a small detached `DevDeckProcessHost` owns a
named Job Object without `KILL_ON_JOB_CLOSE`, inherits a handle to it so the name outlives the
engine, and owns a hidden console. Stop attaches a short-lived controller to that console to
deliver Ctrl+C, falls back to `TerminateJobObject`, and checks the job has no members left. The
process id record carries the creation time and is checked through a fresh handle and job
membership. PATH is read from the machine and user registry at each launch, so a tool installed
after the engine started is found. Short commands use their own jobs with `KILL_ON_JOB_CLOSE`, so
a timeout or cancellation cleans up everything they started.

Which launcher a project gets follows from its folder and is decided by the engine, never by the
shell.

## Consequences

- The deck can be restarted, updated or killed while projects keep serving, on every platform.
- Nothing global is changed on the machine: no WSL setting, no service, no scheduled task.
- A second Start while the first is still coming up does not launch a second copy on Windows,
  because the service checks the recorded process first.
- The Windows paths need a Windows machine to test, and a WSL distribution for half of them. The
  live scenarios from the proof of concept (engine killed, project still serving, stop leaves no
  process and no port) come back with the engine host and become standing checks; see
  [windows-migration.md](../windows-migration.md).

## Alternatives

- `nohup` without a Windows client: the project died with the distribution's idle shutdown.
- A global idle policy change: works, but changes every distribution on the machine.
- A WSL client owned by the engine: couples the project's life to the engine's.
- A Windows service or scheduled task: persistent machine configuration for a desktop widget.
- Killing only a recorded Windows process id: leaves children and occupied ports behind.
- Holding the Job Object only in the engine: the name disappears when the engine exits.

## References

- [Process creation flags](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags)
- [CreateProcessW and handle inheritance](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)
- [WSL general settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#general-wsl-settings)
- [Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
- [Console control events](https://learn.microsoft.com/en-us/windows/console/generateconsolectrlevent)
