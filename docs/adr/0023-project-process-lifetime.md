# 0023 - Keep project processes independent of the engine

Status: implemented in the Windows POC; step 2 acceptance remains pending.

## Context

A detached Linux process does not keep a WSL distribution active by itself.
The original nohup implementation lost its servers under the default idle policy.
A global instanceIdleTimeout=-1 workaround passed an initial idle check, but also
changed the policy for every distribution on the machine.

## Decision

A held project command gets one independent Windows WSL client. CreateProcessW uses
DETACHED_PROCESS and CREATE_NEW_PROCESS_GROUP. STARTUPINFOEX restricts inherited
handles to NUL so the client cannot keep the engine's JSONL pipes open. WSL may use
an additional forwarding process; this still represents one project client session.
The project command runs in the foreground through setsid --wait. Its Linux PID,
boot identity and start time are recorded atomically. The engine closes its Windows
process handle after successful startup without terminating the client.

Stop kills the Linux tree and verifies its process group. The foreground command
ends, which releases the WSL client and allows normal idle shutdown. Failed or
cancelled startup publishes a cancellation marker, cleans Linux processes from an
independent cancellation context and closes its own Windows client.

Windows folders use a detached native process host and a named Job Object without
KILL_ON_JOB_CLOSE. The host inherits a job handle so the name remains available when
the engine exits. PID records contain creation time, checked through a fresh process
handle and job membership. The host owns a hidden console; a short-lived controller
attaches to that console to deliver Ctrl+C without changing the engine's JSONL handles.
Stop falls back to TerminateJobObject and verifies zero active members. Temporary
commands use separate jobs with KILL_ON_JOB_CLOSE for cancellation and timeout cleanup.

Environment PATH is read from machine and user registry values at each launch. The
engine resolves each project's execution location from its configured folder and
keeps project state, polling and actions separate.

## Alternatives

- nohup without a Windows session failed under the observed default idle policy.
- A global idle-policy change worked but affects unrelated distributions.
- A WSL client owned by the engine would couple project lifetime to engine lifetime.
- A service or scheduled task adds persistent machine configuration to this POC.
- Killing only a recorded Windows PID can leave children and occupied ports behind.
- Keeping the project job handle only in the engine loses its name when that engine exits.

## References

- [Windows process creation flags](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags).
- [CreateProcessW handle inheritance](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw).
- [WSL general settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#general-wsl-settings).
- [Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects).
- [Console control events](https://learn.microsoft.com/en-us/windows/console/generateconsolectrlevent).
- [POC report](../poc/one-engine-report.md).
