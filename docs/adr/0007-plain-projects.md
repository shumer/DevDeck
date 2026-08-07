# 0007 — A plain project is a folder, a command and a URL

Status: accepted, 2026-08-03

## Context

Most projects on this machine are neither Arc nor DDEV. Three real ones set the shape:

- a compose stack fronted by a Makefile, started with `docker compose up -d`, which returns;
- a Vite app started with `npm run dev`, which holds its terminal until it is killed;
- a repository with two Node subprojects, each started separately.

The card they want is the one Arc and DDEV already have — links, state, branch, buttons — and
the only genuinely new problem is the second bullet. A command that never returns cannot be run
the way `ddev start` is: the runner waits for the process to exit and drains its pipes, so a
dev server would block the call forever, and a card would sit on "starting…" while the site was
already up.

Three ways out were considered.

**A — start it in the background, with a log and a pid.** Works for both kinds of command.
Costs a file to write and a process that outlives the app.

**B — open a terminal and run it there.** Nothing is orphaned and the output is in front of
you, but Stop from the card becomes impossible and every project needs a terminal window.

**C — support only commands that detach themselves.** Simple, and excludes two of the three
projects above.

## Decision

**A.** One project type, one checkbox — *the command keeps running* — and everything downstream
of it is the same.

1. **A holding command is started detached.** `nohup /bin/zsh -lc '<command>' >> log 2>&1 &`,
   with `echo $! > pid`. The redirection is what lets the caller return at all: a background
   child holding the runner's pipes keeps the read open until it exits. `nohup` is what lets it
   survive the app quitting.
2. **A returning command is simply run and waited for**, with its output appended to the same
   log, so the Logs button means one thing regardless.
3. **Stop kills the tree, not the pid.** `npm run dev` is a wrapper; killing it alone leaves the
   server it spawned holding the port, and the next start then fails for a reason nothing on
   screen explains. A recursive `pgrep -P` walk kills the descendants first. A stop command of
   the user's own always wins over this.
4. **The health URL decides "running"** — the same rule as Arc's engine probe and DDEV's `ddev
   list`, and the reason a stack started by hand in a terminal still reads correctly. Up means
   2xx, 3xx, 401 or 403; a 404 or a 500 does not.

   That last part was learned the hard way. The rule first said "any answer counts", on the
   reasoning that a dev server which serves nothing at `/` is still serving. But a local port is
   a shared resource: a Docker container belonging to another project held 8080, answered the
   configured `/health` with a 404, and the card reported a backend nobody had started as
   running. A 404 is a server saying it does not know this path — which is the answer of
   somebody else's server. 401 and 403 still count, because those are this project's own server
   asking you to sign in.
5. **A live process and a silent URL is `starting`**, not `stopped`. That is a dev server
   compiling, and it resolves itself in seconds.
6. **The folder is read for a suggestion once**, when the project is added — a compose file, a
   `dev` script, a Makefile target — and again only when the Detect button is pressed. A guess
   never overwrites a field the user typed.

## Consequences

- A started project outlives the app. That is the price of A, and it is bounded by the pid file
  and the health URL: the card picks a running project back up on the next launch, because it
  never trusted its own memory in the first place.
- The log lives under `~/Library/Application Support/DevDeck/projects` rather than in the
  checkout. Writing a log file into someone's repository is a change to their working tree.
- The port guessed from `package.json` can be wrong, and shows up immediately as a card stuck on
  "starting…". The field is in settings, one line under the command that caused it.
- Rejected with B: watching the output live. The Logs button opens a file in Console, which is
  fine for reading a failure and poor for watching a build — noted on the roadmap.
