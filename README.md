# DevDeck

Desktop panels for the things a developer checks twenty times a day: open pull requests,
review requests, deploys. Frosted cards that sit on the macOS desktop behind your windows,
plus a menu-bar item with the count.

Native macOS, built from a SwiftPM package with no Xcode required.

Pull requests across every account a token can see - yours and the ones waiting on your
review - worst first:

```
┌────────────────────────────────────────────┐
│  PULL REQUESTS                    23:26:37 │
│ 8 open                          2 BLOCKED  │
│ ▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂ │
│ ● WORK PROJ-142 Add the article feed…   CF │
│ ● WORK PROJ-77  Fix the image fill on…  CR │
│ ● WORK 👁 IW-164 Approvers resource…    RV │
│           show 5 more ⌄                    │
│ 4 repos · 2 orgs                           │
└────────────────────────────────────────────┘
```

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

## Status

| Card | State | On by default |
|---|---|---|
| GitHub · pull requests | working | yes |
| GitHub · inbox (notifications) | working | yes |
| GitHub · Actions | working | no |
| GitLab · merge requests | working | switched on when you add an instance |
| Arc XP · one card per project | working | added per project |
| DDEV · one card per project | working | added per project |
| Project · one card per project | working | added per project |
| Work in flight · every checkout at once | working | no |
| Arc XP · deployed bundle versions | planned - needs an org token | - |

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

The Actions card follows the repositories your open pull requests are in, up to five per
account, unless you name them yourself under **Settings → Cards → Fetching**, where the refresh
interval lives too.

## Build and run

Needs the Swift 6 toolchain from the Command Line Tools - `xcode-select --install`. **Xcode is
not required**: there is no project file and nothing here opens in it. Docker is needed only by
the project cards that run something in containers - Arc's Fusion stack, DDEV, and any plain
project marked as needing it - and the deck says plainly when it is not running.

```bash
git clone git@github.com:shumer/DevDeck.git widgets && cd widgets
./run-tests.sh          # offline suite, ~15s, must be green
./build.sh              # tests, build, bundle, install to /Applications, launch
```

**`./build.sh` installs by default.** In order it: runs the suite and stops if anything fails,
builds the release binary, assembles `DevDeck.app` in the repository, signs it with the Developer
ID it finds in your Keychain (ad-hoc when there is none), then quits any running copy, replaces `/Applications/DevDeck.app` and launches the new one. Nothing
is left for you to drag anywhere.

The copy in `/Applications` is the one that matters. macOS registers a login item **by path**,
and the bundle in the repository is deleted and recreated on every build - so "Start at login"
only works for the installed copy.

| Command | What it does |
|---|---|
| `./build.sh` | the whole thing: test, build, install to `/Applications`, launch |
| `./build.sh --no-install` | builds `./DevDeck.app` only; open it yourself with `open ./DevDeck.app` |
| `./build.sh --skip-tests` | skips the suite; fine for a quick loop, never in CI |
| `./build.sh --skip-tests --no-install` | both, in that order |
| `./run-tests.sh projects docker` | only the test sections whose names contain those words |
| `CODESIGN_IDENTITY=- ./build.sh` | ad-hoc on purpose, even on a machine that has a certificate |
| `swift run DevDeck` | runs from the terminal without bundling - handy for `print` debugging |
| `open -a DevDeck --args --settings project agrica-qdd` | opens Settings on a page, `general`, `deck`, `cards`, `notifications`, or on one item by kind (`github`, `gitlab`, `arc`, `ddev`, `project`) and id |
| `open -a DevDeck --args --update` | checks for a newer release and installs it, the same as the menu line |
| `pkill -f DevDeck` | quits every running copy |

**Settings → General shows the running version** under its heading, `DevDeck 0.14 (build 122)`,
and which bundle it came from in the note at the bottom. The marketing number lives in `VERSION` and is bumped by hand when a release
earns a name; the build number is the commit count, so it moves on every rebuild. That is the
quickest way to tell whether the copy in front of you is the change you just made or the one
that was already running.

**A rebuild does not ask for the Keychain.** With a Developer ID in your Keychain every build has
the same identity, so the tokens stay readable; without one, the tokens are stored so that any
build can read them. [The Keychain](#the-keychain-and-the-password-prompt) below says what each
costs.

### First run

```bash
scripts/seed-token.sh        # optional: copies a token from ~/Projects/CodeStore/AIData/env.local into the Keychain
scripts/smoke-test.sh        # optional: real GitHub and GitLab calls, prints counts, never a token
```

`seed-token.sh` takes an account and a variable name, because one token per account is the
point - a fine-grained token is approved per organisation, so no single one covers every
employer:

```bash
scripts/seed-token.sh --var SHUMER_GITHUB_TOKEN          # a differently named variable
scripts/seed-token.sh --account account-2 --var WORK_TOKEN    # another account's own token
```

It protects the item the way the app would: open while the app's tokens are open, and trusting
only `/Applications/DevDeck.app` once a signed copy has bound them.

The account id is not shown in Settings. `default` is the account the app starts with and keeps
the un-suffixed Keychain key; accounts added later are `account`, `account-2` and so on, and
`defaults read com.shumer.devdeck` lists them. The token is checked against the API before it is stored, so
a rejected one never lands in the Keychain to fail invisibly later.

While no GitHub account has a token, the app opens its settings window at launch; paste one
there instead. The first GitHub account and the first GitLab instance also read
`DEVDECK_GITHUB_TOKEN` or `GITHUB_TOKEN`, and `DEVDECK_GITLAB_TOKEN` or `GITLAB_TOKEN`, from the
environment when the Keychain has nothing for them.

Settings live in the `com.shumer.devdeck` preferences domain. To start over:
`defaults delete com.shumer.devdeck` (tokens survive that - they are in the Keychain).

### Several accounts

One token rarely covers everything: a fine-grained token is approved per organisation, and
some organisations sit behind SAML SSO. **Accounts** in the Settings sidebar holds the list
(**+**, then **GitHub Account**): each account has its own name, its own token in the Keychain
and, under **Advanced**, the organisations it is limited to.

All accounts feed the same cards. Pull requests visible to two accounts are shown once. When
one account fails, the others still render and the card footer says which one is missing;
a card only fails outright when every account fails. With more than one account switched on,
every row carries a chip saying which one it came from.

### Links open as the right identity

github.com allows one signed-in identity per browser profile, so "open in the default browser"
is wrong half the time when work and personal accounts are both on the deck. Each account has
an **Open links in** setting: a browser, and for Chrome, Edge, Brave, Vivaldi and Chromium a
profile as well, listed by the names you gave them. Clicking a row then lands in the profile
that is signed in as that account.

The pickers apply the moment you change them - there is a **Test** button beside them that
opens one page so you can see where it lands. Only the token needs an explicit **Save Token**
(or Return), because it is checked against the API before being stored.

Safari has profiles but no way to choose one from outside the app, and Firefox's `-P` depends
on what is already running; both are offered without a profile picker rather than with one
that would not work.

### Seeing everything

Cards show three rows and a **show N more** line. Clicking it grows the panel to show up to
twelve, pushing the panels below it down; clicking again collapses. It is deliberately not
remembered - expanding is a "let me look at this now" gesture, and a deck that comes back tall
the next morning is a surprise.

### The token

A fine-grained personal access token with read access to **pull requests**, **contents** and
**metadata** covers the pull requests card. The inbox card also needs the account-level
**notifications** permission, and the Actions card needs **actions** (read). Three things
catch people out:

- the **notifications** permission sits under the account section rather than the repository
  section, and without it the inbox card shows
  `Forbidden - Resource not accessible by personal access token`;

- a fine-grained token must be **approved by each organisation** before it can see anything
  there, and until then the API answers with an empty result rather than an error;
- under SAML SSO, a classic token must be **authorised for each organisation** as well.

`scripts/smoke-test.sh` checks the `default` account's token and prints how many repositories
and organisations its open pull requests span; zero organisations where you know there are pull
requests is the fastest way to tell "no open pull requests" from "cannot see the organisation".
It also checks every enabled GitLab instance, with the token each one has in the Keychain.

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
  Support/DevDeck/projects`, and its process id is written down beside it; the card's log tray
  shows the end of that file, and the arrow inside it opens the whole thing. A command that returns is simply run and waited for, with its output kept in
  the same log.
- **Stop kills the whole tree** when there is no stop command of your own. `npm run dev` is a
  wrapper, and killing it alone leaves the server it spawned holding the port - which then makes
  the next start fail for a reason nothing on screen would explain.
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
│ ● ledwall-feed  main          2 unpushed   │
│ ○ giornale-web  main          1 changed    │
│ 9 checkouts watched                        │
└────────────────────────────────────────────┘
```

Unpushed work and branches with no remote lead, because they are the only things on the card
that a dead disk takes with it.
A clean checkout level with its remote is not a row: listing those is how a card becomes a wall
of green nobody reads. It needs no token and no network, since `git status --porcelain=v2
--branch` answers all four questions in one command per checkout, and clicking a row opens that
folder in a terminal. Off by default; turn it on in the menu or under **Settings → Cards**.

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

GitHub rows end in a two-character code so the width goes to the title. Hovering a row spells it out.

| | | | |
|---|---|---|---|
| `RV` | waiting for **your** review | `CP` | checks running |
| `CF` | checks failed | `DR` | draft |
| `CR` | changes requested | `AP` | approved |
| `T3` | three unresolved threads, up to `T9` | `WR` | waiting for review |

GitLab rows have their own: `CF` conflicts, `CI` pipeline failed, `DR` draft, `··` pipeline
running, `2ap` two approvals left, `3th` three unresolved threads, `ok` ready to merge. Only
GitHub's blocked rows light the menu-bar badge.

The coloured dot says the same thing at a glance: red is blocked, amber needs someone, green
is done.

## Using it

The menu-bar item is a stack of cards with the app's initials cut out of the front one. It has
three states, and the difference between the last two is the point: nothing, a badge in the bar's
own ink when a pull request of yours is blocked, and a red badge when a **person** is waiting on
you - a review request, or something actionable in the inbox. Red is kept for the one thing that
costs somebody else time, and it is 4.5 points of badge rather than the whole glyph, which used
to go red for any of the three and so meant "something" and nothing about what. The first line of
the menu says which it is in words, and the numbers are in the tooltip rather than in the menu
bar, where a bare count belongs to no app in particular.

Both icons are drawn in code rather than shipped as images, because there is no asset catalog and
no Xcode to build one, and because an icon that is drawn can be judged at 32 points by rendering
it at 32 points. `swift run IconPreview out.png` renders the menu-bar icon at menu-bar size on a
light and a dark bar; `build.sh` renders the application icon at all ten sizes through
`AppIconExport` and packs them with `iconutil`. The application icon is one card showing what a
card is for: the state dot with its halo, the state word beside it, and the quiet rows under it.
Being an agent app, it appears in Finder and in Login Items rather than in the Dock.

Its menu holds what you do:

- **Update to …**, as the first line and only when a newer release exists; see
  [Updating](#updating). Under it, when the badge is lit, the reason in words.
- **Cards** - show or hide each card; a hidden card is not fetched at all. Projects get a submenu
  per kind below the built-in cards, with how many are shown in its title, and **Power off all
  DDEV** follows when there is a DDEV project.
- **Open pull requests in browser**.
- **Tidy panels into columns** - close up gaps without resetting where you put them. It anchors
  on the topmost panel and stacks downwards, starting a new column beside it whenever the next
  card would hang below the screen, so a deck of six cannot push its last card under the bottom
  edge where nothing can grab it. The order it lays out is the deck's own: the built-in cards,
  then Arc projects, then DDEV, then the plain ones, each group alphabetical.
- **Arrangements** - save the deck as it stands under a name, and put it back later. An
  arrangement is which cards are on the deck, which are folded to one row, and where each one
  sits; the tick shows which one you are in, compared rather than remembered, so it cannot claim
  an arrangement you have since dragged your way out of. Alt-click one to forget it.
- **Lock positions** - a checkmark; while it is on, a stray drag moves nothing.
- **Tidy panels into columns**, **Refresh now**, **Settings…** and **Quit DevDeck**.

What the deck *is* rather than what you do with it lives in Settings: start at login under
**General**, and where the panels sit, the lock, closing gaps, the summon shortcut and its dimming
under **Deck**. A menu that mixes the two grows until the thing you came for is
somewhere in the middle of it. The one exception is the lock, which is also a checkmark in both
menus: it gets toggled in the middle of arranging cards, and a trip to a settings window for that
is the one interruption the deck should not cost.

Right-click a panel and the menu is about that card: fold it to a row, show or hide its log,
take it off the deck, open **Settings for This Card…**, which lands on that card's own form, and
under a separator the deck-wide few: Lock positions, Tidy and Refresh now.

Cut, copy and paste work in the settings window. That is not as obvious as it sounds for an
agent app: with no Dock icon there is no menu bar of its own, ⌘V is routed through the main menu,
and with no Edit menu there was nothing to route it to, so pasting a token was impossible.

The settings window looks and behaves like System Settings: a sidebar, and a form for whatever is
selected in it. At the top of the sidebar are four pages. **General** is start at login, updates
and the version. **Deck** is where the cards sit, the lock, closing gaps and the summon shortcut.
**Cards** switches the cards that are not an account or a project on and off, with the refresh
interval and the Actions repositories. **Notifications** is the master switch and one table of
what each account may interrupt you about. Under them come **Accounts**, GitHub and GitLab
together, and **Projects** of every kind, alphabetical, each with the mark its card wears and a
dot only while it is running or starting. Search narrows the list, the arrow keys move through it
and Delete removes the selected thing after asking; ⌘F goes to the search field. The window
remembers its size.

Every form has **Show on deck** in its header. A plain project's form is in the order you fill
it in: folder and start command, then the health check with its live answer, then the links on
the card; name, caption, stop command, Docker and browser are under **Advanced**. An Arc form
starts with the local stack, then the organisation and site ID, then the links, where you add
and remove your own; name, stop command and browser are under **Advanced**. A DDEV form is the
folder and name, which tools the card shows, the links and the browser. The answer to **Detect**
or **Test** appears next to the button, and a check reruns by itself when the address changes.
An account's form is its token, one line saying whether it is stored and whether it works, a
field for a new one where Return or **Save Token** saves it, and a button to create one; then its
name and browser, for GitLab its address, and for GitHub the organisations under **Advanced**.
Everything else applies as you change it.

Drag a panel anywhere; the position is remembered per card - **against the display it is on**,
not as a point on the desktop. Unplug the external monitor and the cards that live on it are
parked on whatever screen is left, keeping their distance from the top; plug it back in and they
go home. Nothing is re-saved while a card is parked, because parking is not a decision you made.
This is why a deck kept on the laptop screen no longer scatters when an external display that
happens to be the main one comes and goes, and why quitting and reopening puts every panel back
exactly where it was rather than a little further down each time. The deck moves a card only when
you asked it to: collapsing one, opening a log, expanding a list. Data arriving never moves
anything. **Close gaps automatically**, under Settings → Deck and off by default, closes the gaps in a column whenever
a card changes height, at the price of any gap you left in it on purpose.

**Being told.** One switch, **Allow notifications** on the Notifications page of Settings, off
until you turn it on, because asking for notification permission before an app has done anything
for you is what people say no to and never revisit. *What* you are told about is set per account
on the same page, in one table with **Review requests** and **My work blocked** for every GitHub
account and GitLab instance: a banner when somebody asks for your review, and one when something
of yours there is blocked. So a customer's instance can stay quiet while your
own does not, per token, per kind.

The banner carries the service's own mark rather than the app's icon, so who is asking is
answered before the words are read. Nothing is announced on the first answer after a launch,
since that is the state you left things in, and nothing is announced twice, even across restarts.
Three at once become one line rather than three banners. A click opens the pull or merge request
in the browser profile of the account that owns it, and **Send Test Notification** posts one immediately so
the whole chain can be checked without waiting for somebody to ask for a review.

While the display a card belongs to is unplugged, tidying or dragging the parked card makes that
its new home.

Click a row to open that pull request, and double-click a list card's background to open the same
list on the web.

Buttons work on the first click even though the deck sits behind your windows and is never the
frontmost app - which is not what AppKit does by default, and is why they used to need pressing
twice.

A long command narrates itself. Starting an Arc stack takes about a minute, and while it runs
the card shows the line the command has just printed instead of nothing at all. If the stack
never comes up, the card keeps the reason the command gave - a port already taken, most often -
rather than reporting the silence that followed.

Anything clickable lights up under the pointer and turns the cursor into a hand. Because the
panels sit behind other windows, that tracking starts once the deck itself has been clicked -
so buttons and links also carry a resting fill rather than relying on hover to look pressable.

### How a card is put together

Every project card is the same six things, in the same order, so one glance answers the same
question on all of them:

1. **A mark and the title**, with the time of the last check on the right. The mark says what
   kind of project it is - the octocat, GitLab's tanuki, Arc's A, DDEV's mark, Node's hexagon,
   Next's disc, Nest's cat, Bun, Docker's whale, a hammer for a Makefile and a box for anything
   else. The vendors' marks are the real logos, drawn from their own SVG path data rather than
   shipped as images: this toolchain has no asset catalog, and a hand-drawn
   impression of the octocat at fifteen points looks exactly like what it is.
2. **The state, at 17 points** - one vocabulary on every card: `running`, `stopped`,
   `starting…`, `paused`, `unknown`, `not configured`, and `Docker is not running` when that is
   what is really in the way. This is the card's focal point, but a quiet one: the words are
   white at 76% and the colour lives in the dot beside them, which glows when it means something
   and goes plain grey when a project is simply stopped. Colour returns to the words only when
   something wants attention. A detail like `pid 48213`, `mutagen paused` or `not in ddev list`
   sits at the end of the same line.
3. **The branch**, on a line of its own, because branch names are longer than anything beside
   them - and it is a link: the checkout knows its origin, so clicking it opens the repository
   on GitHub in the project's own browser. An arrow at the end of the line says so; a checkout
   with no remote simply has no arrow.
4. **What names this checkout**: the framework and folder on the left, versions or the start
   command on the right. For an Arc project the version is the Fusion release actually running,
   read from the engine container's image tag rather than from the site's `/release` endpoint:
   that endpoint is answered by whatever is published on the site's port, which locally is
   `fusion-cli-api` reporting its own version. It is not `FUSION_RELEASE` from `.env` either,
   which says what the stack will run after the next build rather than what is serving requests
   now.
5. **The links**, in one wrapping row: what you work in, a divider, then the environments -
   local first, then test and UAT in violet, production in amber. An Arc project also gets
   **Local PageBuilder** beside **Local site**: the editor as served by the stack you are
   running, on the port the checkout's own `.env` says. The **PageBuilder** chip on the other
   side of the divider is the hosted one, which edits something else entirely, and the two are
   named so the pair reads as a pair. They all share one neutral
   fill; the colour is in the lettering, mixed back towards white, so five links in a row read
   as a row rather than as five things shouting.
6. **The controls.** The one action that matters now is half again as wide, tinted, bolder and
   the only one with an outline; the rest recede to a plain fill. All four carry an icon.

**Hold ⌥Space** and the deck comes up over your windows; let go and it drops back. A tap keeps it
up until the next press. Nothing moves and nothing is redrawn: they are the same panels at a
different window level, which is why this costs almost nothing. The screen dims 45% while they are
up, because dark glass over a white editor is unreadable otherwise. Both switches and the
combination itself are in Settings, Deck, under Shortcut, with a **Default** button that puts
⌥Space back. It needs no
permission: the shortcut is a Carbon hot key, not a global key monitor, so macOS has nothing to
ask you about.

Right-click a panel and **Collapse to one row** folds the card down to 44 points: the mark, the
state dot, the name and its controls as small squares. On a project those are the action the state
implies, a restart when there is one worth offering, a terminal, and the site while something is
serving it; on a list card, which has no lifecycle, one square opens the same list on the web and
the row keeps its count instead. It is remembered per card,
so the projects you are not working on today take a row each while the one you are stays whole.
Six collapsed cards come to 324 points against 1218 whole.

The **QR button** beside it puts the running site on your phone: the site is already being
served, it is only being asked for by a name that means "this device", so the address is swapped
for this Mac's own on the wifi and drawn as a code to point a camera at. It appears only while
the project is actually up, because a code pointing at a port nothing is listening on is a worse
answer than no button. No account, no tunnel, nothing published to the internet. The phone has to
be on the same network, and a dev server bound to localhost only will still refuse: that is what
`--host` is for.

The small button beside the clock opens the **log tray**: the last six lines the project is
writing, in place, on any of the three project cards. Arc reads the containers carrying the
project's compose label, DDEV reads `ddev logs -s web`, and a plain project reads the log its
detached start already writes. It refreshes only while it is open, and the arrow inside it opens
the whole file when six lines are not enough. It is not a terminal: no following, no scrolling,
no colour beyond stripping the escapes the tools paint with.

The state pill, the horizontal rule and the footer are gone: the pill said what the state line
says, and the timestamp took a whole row to be the least important thing on the card. Cards
came down from 249 to about 200 points and hold more than they did.

The palette is deliberately a step below fully saturated, and the contrast range is narrower at
both ends than it was: dim text came up, the title came down, and the only outline left on a card
belongs to the action being offered. One card looks better loud. Six of them on a desktop all day
do not. See [docs/adr/0010-card-palette.md](docs/adr/0010-card-palette.md).

## The Keychain and the password prompt

Tokens live in the login Keychain and nowhere else. How each item is protected follows from how
the app is signed, and the code finds that out for itself at launch:

- **Signed with an identity that survives a rebuild**, a Developer ID or a certificate you made
  in Keychain Access, the Keychain does what it does by default: the item is bound to this
  application, and any other process gets a password prompt. Updates do not prompt, because the
  identity is the same.
- **Ad-hoc signed**, a build made on a machine with no certificate, the items are written with
  an access list that names no application. A Keychain item is normally bound to
  the exact binary that wrote it, and an ad-hoc signature is different for every build, so the
  alternative is one password prompt per token per update. The trade is worth stating plainly:
  any process running as you can then read those tokens without a prompt.

Releases are signed with a Developer ID, and `./build.sh` uses the one in your Keychain when there
is one, so on the author's machine and on every machine that installed a release the tokens are
bound. The first launch after the signature changes rewrites the stored items once, one prompt
each, and remembers the mode. It never goes the other way by itself: a copy without an identity,
`swift run` or a build with `CODESIGN_IDENTITY=-`, leaves bound tokens bound and asks for the
password on each read rather than opening them to every process, and a token it saves is bound
to that copy rather than open, so the signed app asks for it once. Without a Developer ID, a
certificate made in Keychain Access (Certificate Assistant, Create a Certificate, type Code
Signing) and `CODESIGN_IDENTITY="its name" ./build.sh` binds your own tokens the same way. See
[adr/0017-signature-decides.md](docs/adr/0017-signature-decides.md).

## Releases

Publishing a release on GitHub builds the app and attaches it: `.github/workflows/release.yml`
runs the suite, builds the bundle and uploads `DevDeck-<version>-<build>.zip` to the tag, so the
tag and the download cannot disagree about what is in it. Nothing is built on an ordinary push,
because a build nobody asked for is a build nobody checks. `.github/workflows/tests.yml` runs the
suite on every push to main and on every pull request and fails on a compiler warning, which is the one place
nobody is in a hurry.

**Releases are signed with a Developer ID, hardened, notarised by Apple and stapled on the
runner**, from 0.12 on. macOS opens the download as it is: unzip, drag into Applications, open.
It takes five repository secrets, `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`,
`NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` and `NOTARY_KEY_P8`; [docs/development.md](docs/development.md)
says where each comes from. `DEVELOPER_ID_P12` and `NOTARY_KEY_P8` decide the path, so with those
two set a missing or wrong other secret fails the release rather than quietly shipping ad-hoc. Notarisation is Apple's queue and takes minutes, occasionally most of
an hour.

Without those two the workflow builds the ad-hoc release it always did, and macOS quarantines
that download. The notes then carry two routes: Finder (unzip, drag into Applications,
right-click and Open, which needs no permissions), and a line for a terminal that may read
Downloads:

```
pkill -f "DevDeck.app/Contents/MacOS/DevDeck"; ditto -x -k ~/Downloads/DevDeck-<version>-<build>.zip /Applications && xattr -dr com.apple.quarantine /Applications/DevDeck.app && open /Applications/DevDeck.app
```

The workflow writes the install section itself, naming the file it actually built and saying
which of the two builds it is, so a version number is never typed by hand into the notes.

To cut a release: bump `VERSION`, commit, then create the release on GitHub with a tag like
`v0.14`. The build number in the bundle is the commit count, so it moves on its own. A manual
run of the workflow against an existing tag builds that tag's commit and replaces its asset.

### Updating

From 0.11 on the app keeps itself current, by asking rather than by doing. Thirty seconds after
launch and every six hours it reads the latest release on GitHub; when that is newer than the
running copy, the menu-bar menu opens with **Update to …** as its first line and one banner says so,
once per version and only if notifications are on. Nothing is downloaded until you ask:
that line, the banner, **Update Now** in Settings, or `open -a DevDeck --args --update`. Then:
download, `ditto`, a check that what unpacked is DevDeck at the promised version and, from a
signed copy, signed by the same identity as the running one, the old copy to the Trash, the new
one in its place, and a relaunch a second later with every panel where it was. Option-click the
line to read the notes first. A copy signed with a certificate of your own therefore does not
update itself to a release, which is signed with the Developer ID.

What the app downloads itself carries no quarantine, so an update never needs the right-click
dance a first install does. No install starts while a card is mid-command, however it was asked
for, because replacing the bundle under a running `fusion start` is how a stack is left half up:
the menu line says what it waits for, and an install already asked for goes ahead by itself once
the command is done. Settings,
General has the switch and a **Check Now** button with the last answer beside it. See
[adr/0016-self-update.md](docs/adr/0016-self-update.md).

## Documentation

- [docs/architecture.md](docs/architecture.md) - modules, data flow, where to add a card
- [docs/github-api.md](docs/github-api.md) - the GraphQL query, rate limits, token setup
- [docs/development.md](docs/development.md) - toolchain, scripts, definition of done
- [docs/roadmap.md](docs/roadmap.md) - what is done and what is next
- [docs/adr/](docs/adr/) - eighteen decisions and what they cost: why native, why SwiftPM only,
  why cards are configurable, why accounts are plural, how local stacks are driven, why DDEV
  shares one call, how a plain project is started, why Docker is checked first, how a card is
  laid out, why the deck is quieter than it was, why a card has two sizes, why the deck moves a
  card only when asked, why GitLab is a card of its own, how a monorepo is read, why the
  application layer is in pieces, how the app updates itself, why the signature decides how
  tokens are kept, and why the settings window is built like System Settings

## Layout

```
Sources/
  DevDeckCore/     configuration, cards, HTTP transport, tokens and code identity, policies,
                   command runner, git branch, browser choice, the Docker probe, log tail,
                   the refresh cycle, the update check
  KeychainACL/     the C shim for the one deprecated Keychain call Swift cannot silence
  GitHubKit/       GraphQL and REST clients, models, per-account fan-out
  GitLabKit/       GitLab accounts per host, the merge requests query, models
  ArcKit/          Arc projects, link templates, local Fusion stack, .env port
  DDEVKit/         DDEV projects, ddev list, .ddev/config.yaml, composer.lock version
  ProjectKit/      plain projects: folder probe, detached start, log and pid, health check
  DevDeckUI/       SwiftUI cards, the shared card pieces, the brand marks and their SVG
                   parser, and the visual language
  DevDeckApp/      AppKit shell: the controller and its loops, the panel coordinator, the
                   menu, arrangements, the summon key, the updater, the settings window
    Modules/       one file per kind of card: its view, size, catalog entries and settings
Tests/
  TestHarness/     tiny test framework and fakes
  DevDeckTests/    the suite (348 tests, offline)
Tools/
  Smoke/           live API check
  IconPreview/     renders the menu-bar icon at the size it is actually seen
  AppIconExport/   renders the application icon at all ten sizes for build.sh
  GlyphPreview/    renders every card mark at the size a card draws it
scripts/           seed-token.sh, smoke-test.sh
docs/              architecture, development, GitHub API, roadmap, adr/
```
