# 0005 — Ask the engine, not the process table

Status: accepted, 2026-08-02

## Context

An Arc project card has to answer two things: is the local Fusion stack up, and can I start or
stop it from here. Both look simple and both have a wrong obvious answer.

"Is it up" could be read from `docker ps`, from a `pgrep`, or from whether this app started it.
All three are wrong in the same way: the stack is often started by hand in a terminal, and a
card that says "stopped" while the site is serving is worse than no card.

"Start it" looks like `npx fusion start`, which the Arc docs list first. That command runs in
the foreground.

## Decision

1. **Status comes from the engine's own health URL** — `http://localhost/release`, which the
   Arc documentation points at, and which reports the running engine version as a bonus. Both
   the base URL and the path are per-project settings.
2. **Start is `npx fusion daemon`**, the CLI's documented background mode. `stop`, `rebuild`
   and `down` map to their own commands, and every one of them is editable per project.
   Restart is stop followed by start, sequentially — starting before the ports are released
   fails in a way that looks like a broken stack.
3. **Commands run through `zsh -lc`** in the project folder, on a background queue, with
   `/dev/null` as stdin. Each part earns its place:
   - a login shell, because an app launched from Finder has no Homebrew and no nvm on `PATH`
     and a plain `npx` is not found;
   - a background queue, because the caller is the main actor and blocking it freezes the
     whole app for as long as the command runs — which looks exactly like a dead button;
   - no stdin, because `npx` asks "Ok to proceed?" when a package is missing and a command
     waiting for an answer nobody can give never returns;
   - both pipes drained concurrently, because reading one to the end first deadlocks as soon
     as the other fills its buffer, and build output fills it easily.
4. **A command owns the card's status while it runs.** The 10-second status poll skips a
   project that is mid-command, and a failed command leaves its last error line on the card
   instead of silently reverting to "stopped".

## Consequences

- The card is honest about stacks this app did not start, which is the common case.
- Container counts are best effort: Compose names its project after the directory, so they are
  counted by that label and simply omitted when the naming differs.
- Arbitrary shell commands are stored in preferences and executed. They are the user's own,
  typed into their own settings window — the same trust level as a shell alias — but this is
  the one place in the app where that is true, and it should stay that way.
- Local stack state polls on its own 10-second loop rather than the API refresh cadence: a
  stack that just came up should appear within seconds, and the check costs one local request.
