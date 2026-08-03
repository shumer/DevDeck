# 0008 — Docker is checked before a card offers to start anything

Status: accepted, 2026-08-03

## Context

With Docker Desktop not running, every project card still showed an enabled **Start**. Pressing
it produced, on this machine:

```
$ ddev list -j
{"level":"fatal","msg":"Docker error: Cannot connect to the Docker daemon at
unix:///Users/…/.docker/run/docker.sock. Is the docker daemon running?"}
```

The DDEV card turned that into `unknown to ddev` and the Arc card into `local stack not
running` — both true sentences that explain nothing and blame the wrong thing. The user's own
words: the Start button is there, but pressing it will not start anything.

## Decision

**Ask Docker, once for the whole deck, before any card talks about a project it cannot start.**

1. **The probe is `docker version --format '{{.Server.Version}}'`**, run on the same
   ten-second loop as `ddev list`. Measured at 0.34 s with the daemon down, so it fits inside
   the existing cadence rather than adding one of its own.
2. **The daemon is asked, not the process table.** Colima, OrbStack, Rancher and a remote
   context all serve `docker` with no Docker Desktop anywhere; looking for a running
   application would call all of them "not running". This is the same rule as everywhere else
   in the deck — ask the thing, not what launched it.
3. **Three answers, not two.** A non-zero exit is "not running"; exit 127 or `command not
   found` is "not installed". They lead to different sentences and different buttons.
4. **`unknown` gates nothing.** Not having asked yet is not evidence, and blocking on it would
   grey out every button for the first poll of every launch.
5. **A running project is never gated**, whatever the probe says. Something is clearly serving
   it.
6. **The Start button becomes Start Docker** where there is an application to open, and opens
   it without stealing focus. `starting` is then held locally for up to three minutes against
   probes that still say no — Docker Desktop takes the better part of a minute, and flipping
   the card back in between is exactly what makes a button look broken.
7. **The wording lives in one place.** `DockerGate` in `DevDeckUI` owns the pill, the state
   line, the colour and the button, so the three card types cannot describe the same condition
   three different ways.

## Consequences

- One extra subprocess every ten seconds while any project card is on screen. Nothing is
  probed when the deck is only GitHub cards, because the local loop does not run at all then.
- Docker being off is not an alert. The menu-bar tooltip mentions it and the icon stays calm:
  a laptop with Docker off is a normal laptop, not a problem.
- A machine on Colima gets a disabled Start and an explanation rather than a button that would
  do nothing. Adding a "start command" setting for such runtimes was considered and left out
  until someone actually has one.
- `requiresDocker` is a per-project field for plain projects, ticked automatically for compose
  folders. Arc and DDEV do not have the field: both are containers all the way down.
