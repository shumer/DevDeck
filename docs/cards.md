# The cards

What each card shows, where its words come from, and what its buttons do. For how the deck as
a whole behaves, see [deck.md](deck.md).

An Arc XP project: whether its local Fusion stack is up, and the links you use:

```
┌────────────────────────────────────────────┐
│ ◔ ARC · ACME NEWS                 23:25:49 │
│ ● stopped                                  │
│ ⎇ fix/PROJ-142-video-badge ↗               │
│ sandbox.acme                               │
│ PageBuilder Composer Deployer │ Local site │
│ Sandbox Prod                               │
│ [ ▶ Start ] [↻ Restart] [Folder] [Terminal]│
└────────────────────────────────────────────┘
```

A DDEV project, which can describe itself - versions, state and URLs all come from DDEV or
the checkout:

```
┌────────────────────────────────────────────┐
│ ▣ DDEV · ACME SHOP                23:41:02 │
│ ● running                   mutagen paused │
│ ⎇ main                                     │
│ drupal 10.6.11 · acme-shop  php 8.4 · mysql│
│ Mailpit │ Local site Test UAT Prod         │
│ [ ⏻ Stop ] [↻ Restart] [Folder] [Terminal] │
└────────────────────────────────────────────┘
```

Anything else - a folder, a command and a URL that proves it worked:

```
┌────────────────────────────────────────────┐
│ ⬡ PROJECT · ACME PORTAL        ≡  23:58:04 │
│ ● running                       pid 48213  │
│ ⎇ feat/PROJ-77-tables ↗                    │
│ docker compose · acme-portal  docker com…  │
│ pgAdmin Traefik │ Local site UAT Prod      │
│ TAIL ACME-PORTAL.LOG                     ⤢ │
│ listening on 3000                          │
│ GET /health 200 4ms                        │
│ [ ⏻ Stop ] [↻ Restart] [Folder] [Terminal] │
└────────────────────────────────────────────┘
```

When Docker is not running, every card that needs it says so instead of offering a Start that
cannot work:

```
┌────────────────────────────────────────────┐
│ ▣ DDEV · ACME SHOP                23:41:02 │
│ ● Docker is not running - start it first   │
│ ⎇ main                                     │
│ drupal 10.6.11 · acme-shop                 │
│ Mailpit │ Local site Test UAT Prod         │
│ [▶ Start Docker] [↻ Restart][Folder][Term.]│
└────────────────────────────────────────────┘
```

## The GitHub, GitLab and Azure DevOps cards

**The card carries both halves of "what do I owe today."** Your own open pull requests, and
the ones somebody has asked you to review - two searches in one GraphQL request, because
GitHub's search cannot OR those qualifiers. A review someone is waiting on sorts just under the
blocked rows, wears an eye and the code `RV`, and leaves the card the moment you review it. There
is no setting to leave them out yet.

**The same card again, for GitLab.** Merge requests you have open and the ones waiting on your
review, in the same layout, the same row order and the same three health words, because the
question is the same one. It is a card of its own rather than more rows on the GitHub card: the
two refresh against different servers and fail independently, and a row that had to say which
host it came from would need a column the GitHub card does not have. One GraphQL request per
instance covers both halves, since GitLab's `currentUser` answers "mine" and "waiting on me"
without a search string. Add one with **+** under the Settings sidebar, then **GitLab Instance**:
an address, a token with `read_api`, and the browser profile it opens in. The host lives on the account because
GitLab is routinely self-hosted, so gitlab.com and a customer's own instance are two accounts on
one card. Nothing appears until you add one.

**And once more, for Azure DevOps.** Pull requests you have open in an organization and the ones
waiting on your vote, in the same layout and the same words. Add one with **+**, then **Azure
DevOps Organization**: the organization's name as it appears in `dev.azure.com/{organization}`
(a pasted address is reduced to that word), a personal access token with the **Code (Read)**
scope, and the browser profile its links open in. The card asks who the token belongs to, then
for the pull requests you created and the ones you are a reviewer of, across every project in
the organization. A row leaves the card the moment you vote, approved or not, the way a reviewed
pull request leaves the GitHub card. Health comes from the merge check and the votes: a conflict
or a reviewer waiting for the author blocks a row, a required vote still owed or no approval yet
needs someone, approved and mergeable is ready. Build results and branch policies are not read,
because they are a request per pull request, and the list is what is polled. The one date a
row has is when it was opened: the list says nothing about when it was last touched.

**The inbox can be cleared from the card.** While something in it is addressed to you, its
footer offers **Mark as read, except the 2 for you**: comments, CI notes, subscriptions and your
own pull requests are marked read, including the ones the card has no room for, and mentions,
review requests and assignments stay. Hold ⌥ and it becomes **Mark all as read**; when only one
kind is left, nothing addressed to you or nothing but, it is that from the start, with the count. The same two are in the card's
right-click menu. While it runs the footer says how far it has got, `Marking as read… 120 of
340`, then `Done, 340 marked as read`, or what GitHub refused; a second press does nothing until
it is over, and the regular refresh cannot put back what is still being marked. Marking all stops
at the newest notification the card has shown, so whatever arrives a second later stays unread.
A full page is shown as `50+`: the count is only as far as the card looked. GitHub cannot mark
anything unread again and has no delete; a read notification simply leaves the card. Marking
read needs the notifications permission at its write level, see
[docs/github-api.md](github-api.md).

The Actions card follows the repositories your open pull requests are in, up to five per
account, unless you name them yourself under **Settings → Cards → Fetching**, where the refresh
interval lives too. Its footer says which of the two it is doing, `3 repos from your PRs` or
`3 repos from your list`. With no list and no open pull request it has nothing to watch, and says
exactly that, **no open PRs**, rather than looking like a card nobody set up; its **List your own
repositories** link opens that settings page with the cursor already in the field. With
repositories but nothing run in them for the whole window, it says that too, `No runs in the last
7 days`, and which repositories it looked at.

## Arc XP projects

**Settings, +, Arc XP Project.** Each project becomes its own card with the links
you use, the browser they open in, and control of its local Fusion stack.

- **Links** are templates with `{org}` and `{site}` substituted. **The organisation field
  carries the environment**: type `sandbox.acme` for the sandbox and `acme` for
  production, and the templates add nothing of their own - PageBuilder becomes
  `https://sandbox.acme.arcpublishing.com/home/`. PageBuilder, Composer and Deployer are
  confirmed against a real organisation; Site Service and Delivery API are guesses and ship
  switched off, so open them from the card once and edit the field in place when it is wrong.
  **Add Link** puts your own beside them, and those can be removed again.
- **Sandbox and Prod ship empty**: a published site lives on its own domain and there is
  nothing to derive it from. Paste the URLs in and switch them on.
- **Two rows.** Arc's tooling on top - PageBuilder, Composer, Deployer, all in blue - and the
  environments you can open below it, in the order local, sandbox, production. The local chip
  is green while the stack is up and grey when it is not, sandbox is violet and production
  amber: production is the one worth a beat of hesitation, so it is the one that is not calm.
- **Local stack** buttons run the Arc CLI in the project folder: **Start** is `npx fusion
  daemon` (the CLI's background mode - `fusion start` runs in the foreground and would hold
  the app hostage), **Stop** is `npx fusion stop`, **Restart** is one then the other. Start and
  Stop are editable per project, Stop under **Advanced**. After a stop the card checks for up to
  thirty seconds that the engine really went away, and says so when it is still answering.
- **Running or not** is answered by asking the engine, not by watching processes: the card
  requests `/release` to decide it is up, and shows the engine version from the fusion-engine
  container's image tag, with how many containers are running. A stack you started by hand in
  a terminal therefore shows as running too - the card reports what is actually serving.
- **The port comes from the project's `.env`.** Fusion defaults to 80, but `PORT` in the
  checkout overrides it, and that file is the only honest source. Leave **Local URL** empty
  and the card follows it; fill it in only for a stack that does not. **Check path** is what is
  asked, `/release` by default. The chip says
  **Local site** and greys out while the stack is down; the address it opens is in its
  tooltip, along with every other link's.
- **Start is offered only when it can work.** Before a stopped Arc card enables Start, the deck
  checks the folder, the start command, Node, npx and an installed `@arc-fusion/cli`, in the
  project's own environment and without installing anything; a card that cannot start says
  what is missing, in amber, and keeps Stop for a stack that is serving. The check is asked once
  per folder and command and again when they change or a button is pressed. A custom Node
  command is checked for Node and its script; any other custom command is left to run.
- **After a start the card waits.** `fusion daemon` returns as soon as the containers exist,
  while the engine needs longer to serve, so the card polls every three seconds for up to three
  minutes before concluding anything - and if nothing ever answers it names the URL it tried.
- **The branch is on the card, and clicking it opens the repository.** Both come from the files
  in `.git` - `HEAD` for the branch, `config` for origin - read directly rather than by running
  `git` every ten seconds. So the card shows what the running stack is actually serving,
  including after switching branches in a terminal, and the line that says so is one click from
  the code. It opens the repository rather than the branch on purpose: a branch link has to be
  right about whether the remote has that branch, and a local branch nobody has pushed is the
  normal state of a checkout - the repository is the one page that always exists.
- **Folder** opens the checkout in Finder, **Terminal** opens it in iTerm, Warp or Terminal,
  whichever is installed.

Commands run through a login shell (`zsh -lc`) **with the `PATH` your terminal actually has**.
An app launched from Finder inherits a bare environment, and a login shell alone does not fix
it: it reads `.zprofile` but never `.zshrc`, where nvm and friends live. So the app asks an
interactive shell for its `PATH` once at launch and gives it to every command. Without that,
`ddev` and `docker` work - they are in `/usr/local/bin` - and `npx` reports "command not found"
from a machine that plainly has it.

**Two Arc checkouts cannot both be up.** Fusion names its containers the same in every one of
them, so starting a second stack replaces the first, and two checkouts that serve on the same
port out of their own `.env` answer each other's health checks. A card that gets an answer while
Docker shows none of its own containers now says **stopped** and names the checkout holding the
port, rather than sitting green over a stack that was never started. Different ports per checkout
are worth setting anyway: it is the only way to keep the links on both cards pointing at the
right site. `scripts/check-arc-stack.sh` prints what each card checks and who answered.

## DDEV projects

**Settings, +, DDEV Project…** offers what `ddev list` found, so there is no
folder to go hunting for - DDEV already knows every project on the machine.

- **One `ddev list -j` answers for the whole deck.** Six cards cost the same as one, which is
  why this is a shared environment rather than a probe per project.
- **The framework version comes from `composer.lock`.** DDEV's own `type:` is a setting
  nobody updates after an upgrade - two projects here still said `drupal9` while running
  Drupal 11.4.4 and 10.6.11 - so the footer reads the lock file, which cannot drift that way,
  and falls back to the DDEV type when there is no lock file or it names none of Drupal, TYPO3,
  Laravel or Symfony.
- **PHP and database versions come from `.ddev/config.yaml`.** `ddev list` does not carry
  them and `ddev describe` is a process per project, while the file is right there in the
  checkout - the same trick as Arc's `PORT` and the git branch.
- **Paused is its own state.** DDEV pauses containers without tearing them down, and calling
  that "stopped" would misrepresent what pressing Start is about to do.
- **A broken file sync is called out.** When mutagen is enabled and not `ok`, the card says
  so: edits stop reaching the container and nothing else on screen would hint at why.
- **Two rows of links.** Mailpit and xhgui on top, straight from DDEV - Mailpit on by
  default, xhgui not. Below them the environments: the local site, which DDEV reports, then
  **Test, UAT and Prod**, which ship empty for you to paste addresses into. Local, a
  `*.ddev.site` address like any `localhost` one, is green,
  test and UAT violet, production amber.
- **Only the local link waits on the container.** It is dimmed while the project is down,
  because a link into a stopped project lands on a connection error that reads as a broken
  app; a deployed site is reachable either way.
- **The phone button needs one line of setup.** A `*.ddev.site` name resolves to 127.0.0.1 on
  every device, and the router picks the project by name, so this computer's address alone
  reaches nothing. The card offers the QR code once the checkout says how it can be reached,
  the two ways DDEV documents: `ddev config --host-webserver-port=8080 --bind-all-interfaces`
  gives the phone `http://<this computer>:8080`, straight to the web container; or an
  `additional_fqdns` entry that carries this computer's address, `shop.192.168.1.20.nip.io`,
  with the router listening on every interface. Plain http, because no phone trusts the
  development certificate. A name carrying some other address is not offered: the computer has
  moved networks since.
- **Start, Stop and Restart** are `ddev start`, `ddev stop` and `ddev restart`; a project
  `ddev list` does not know is `unknown`, in red.
- **Power off all DDEV** in the menu runs `ddev poweroff` - every project and the router, for
  when the laptop needs its memory back.

## Plain projects

Everything that is neither Arc nor DDEV: a compose stack, a dev server, a Makefile, a
Next and Nest monorepo. **Settings, +, Project from a Folder…** asks for a folder and then reads
it, in this order: a compose file, a `dev` script in `package.json`, an `up`, `start` or `dev`
target in a Makefile, a `start` script. It fills the commands in for you once, when the project is
added. **Detect** asks again later and replaces the start and stop commands and both switches,
but keeps a caption or Check URL you already filled in.

- **One switch decides how the command is run.** *Long-running command* is on for
  `npm run dev` and off for `docker compose up -d`. A command that holds its process is started
  detached with `nohup`, its output goes to a log under `~/Library/Application
  Support/DevDeck/projects`, and its process id is written down beside it; the card's log
  button opens the end of that file in a window, and the button in its footer opens the whole
  thing. A command that returns is simply run and waited for, with its output kept in the same
  log.
- **Stop kills the whole tree** when there is no stop command of your own. `npm run dev` is a
  wrapper, and killing it alone leaves the server it spawned holding the port - which then makes
  the next start fail for a reason nothing on screen would explain. It asks with TERM first,
  waits five seconds, and insists with KILL on whatever is left: `dotnet run` and a server
  mid-shutdown sit on TERM. The process record is forgotten only once the tree is gone, so a
  stop that did not take leaves a project DevDeck can still stop, not one that reads as started
  outside it.
- **Stop never touches what DevDeck did not start.** A project started in a terminal answers its
  health URL and reads as running, but DevDeck holds no process for it. The card says `started
  outside DevDeck` where the pid would be, Restart is off, and Stop runs nothing: the menu says
  DevDeck can't stop it and to stop it where it was started. A command that returns, such as
  `docker compose up -d`, with no stop command says `no stop command` the same way. Nothing is
  ever stopped by its port.
- **The health URL decides whether it is running**, exactly as the Arc card asks the engine - so
  a stack you started yourself in a terminal reads as running too. Without one, running means the
  process it started is still alive. Up means 2xx, 3xx, 401 or 403;
  a 404 or a 500 does not count. A local port is a shared resource, and the first version of this
  rule counted any answer at all: a Docker container from another project held 8080, answered the
  configured `/health` with a 404, and the card reported a backend nobody had started as running.
- **Live process, silent URL, is `starting…`** rather than stopped - that is a dev server
  compiling, and it resolves itself within seconds.
- **Test, UAT and Prod ship empty**, next to the local site, the same as everywhere else.
- **Needs Docker** (under **Advanced**) puts the card behind the Docker check below. It is ticked for you when the
  folder is a compose project, and also when the `dev` script reaches Docker through another
  script of its own: `bun run dev` being `bun run db:up && turbo run dev` is a stack that cannot
  start without a daemon, and a card that does not know it offers a Start that cannot work.
- **A workspace is read through to its apps.** A monorepo root has no framework and names no
  port; the apps under `workspaces` do. The probe walks them in one order - front ends first,
  the API last - so the health URL comes out as the site you would open rather than the backend
  behind it, and the caption says `bun · next + nest` rather than `npm`. A port written into the
  script wins, then `.env`, then the framework's own default.
- **The mark says what it is.** Node's hexagon, Docker's whale, a hammer for a Makefile, and now
  Next's disc, Nest's cat and Bun. It is read from the start command and the caption, so a card
  whose mark comes out wrong is fixed by writing the framework's name in the caption.

The commands run in the project folder through a login shell, so `npm`, `make` and `docker` are
found the same way your terminal finds them.

## Work in flight

One card for every checkout the deck knows about, whatever kind of project it belongs to:
what is uncommitted, what is unpushed, what has fallen behind, and what has no remote at all.
It is the one card that shows something no other card can. A project card answers "is it
running"; this answers "what did I leave in the middle of", which is the question that costs an
hour on a Monday morning.

```
┌────────────────────────────────────────────┐
│ WORK IN FLIGHT                    09:14:22 │
│ 3 in flight                    2 UNPUSHED  │
│ ● acme-portal   feat/PROJ-77  4 changed ·… │
│ ● newsroom-feed main          2 unpushed   │
│ ○ daily-web     main          1 changed    │
│ 9 checkouts watched                        │
└────────────────────────────────────────────┘
```

Unpushed work and branches with no remote lead, because they are the only things on the card
that a dead disk takes with it.
A clean checkout level with its remote is not a row: listing those is how a card becomes a wall
of green nobody reads. It needs no token and no network, since `git status --porcelain=v2
--branch` answers all four questions in one command per checkout, and clicking a row opens that
folder in a terminal. Off by default; turn it on in the menu or under **Settings → Cards**. With
it on, commits that have been only on this Mac for more than three days show under Good to know in
the menu-bar menu, dated by the oldest of them.

## Docker

Every local project sits on a container runtime, and a Start pressed without one produces a wall
of shell output the card has nowhere to put. So the deck asks first, once for the whole deck, on
the same ten-second loop, which runs only while a project card is on the deck:
`docker version --format '{{.Server.Version}}'`.

- **The daemon is asked, not the process table.** Colima, OrbStack, Rancher and a remote context
  all serve `docker` with no Docker Desktop anywhere, and looking for a running app would call
  every one of them "not running".
- **A card that needs Docker says so** on its state line, *Docker is not running, start it
  first*, and the Start button becomes **Start Docker**, which opens Docker Desktop (or OrbStack,
  Rancher, Podman Desktop) without stealing focus. The card then says `starting Docker…` until
  the daemon answers, for up to three minutes.
- **A running project is never gated.** Something is clearly serving it, and no probe beats that.
- **Not having asked yet blocks nothing**, so the first second of a launch does not grey out
  every button.
- Where there is no runtime application to open - Colima is a CLI - the card shows a disabled
  Start rather than a button that would do nothing.

### Status codes

Rows end in a two-character code so the width goes to the title, the same codes on the GitHub,
the GitLab and the Azure DevOps card. Hovering a row spells it out.

| | | | |
|---|---|---|---|
| `RV` | waiting for **your** review | `CP` | checks or pipeline running |
| `MC` | merge conflict | `DR` | draft |
| `CF` | checks or pipeline failed | `AP` | approved, or ready to merge |
| `CR` | changes requested (GitHub) | `WR` | waiting for review (GitHub) |
| `T3` | three unresolved threads, up to `T9` | `A2` | two approvals left (GitLab), two required votes left (Azure DevOps) |

A conflict is named before a failed check, because until it is resolved the checks ran on code
that will not be merged.

The coloured dot says the same thing at a glance: red is blocked, amber needs someone, green
is done.
