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
| GitLab · merge requests | working | added per instance |
| Arc XP · one card per project | working | added per project |
| DDEV · one card per project | working | added per project |
| Project · one card per project | working | added per project |
| Arc XP · deployed bundle versions | planned - needs an org token | - |

**The card carries both halves of "what do I owe today."** Your own open pull requests, and
the ones somebody has asked you to review - two searches in one GraphQL request, because
GitHub's search cannot OR those qualifiers. A review someone is waiting on sorts just under the
blocked rows, wears an eye and the code `RV`, and leaves the card the moment you review it. Turn
it off with `includesReviewRequests` if you would rather the card stayed only about your work.

**The same card again, for GitLab.** Merge requests you have open and the ones waiting on your
review, in the same layout, the same row order and the same three health words, because the
question is the same one. It is a card of its own rather than more rows on the GitHub card: the
two refresh against different servers and fail independently, and a row that had to say which
host it came from would need a column the GitHub card does not have. One GraphQL request per
instance covers both halves, since GitLab's `currentUser` answers "mine" and "waiting on me"
without a search string. Add an instance under **Settings → GitLab instances**: a host, a token
with `read_api`, and the browser profile it opens in. The host lives on the account because
GitLab is routinely self-hosted, so gitlab.com and a customer's own instance are two accounts on
one card. Nothing appears until you add one.

The Actions card follows the repositories your open pull requests are in, up to five per
account. A fixed list instead of that is a field in `GitHubSettings` with no settings screen
behind it yet.

## Build and run

Needs the Swift 6 toolchain from the Command Line Tools - `xcode-select --install`. **Xcode is
not required**: there is no project file and nothing here opens in it. Docker is needed only by
the project cards that run something in containers - Arc's Fusion stack, DDEV, and any plain
project marked as needing it - and the deck says plainly when it is not running.

```bash
git clone git@github.com:shumer/DesktopWidgets.git widgets && cd widgets
./run-tests.sh          # offline suite, ~15s, must be green
./build.sh              # tests, build, bundle, install to /Applications, launch
```

**`./build.sh` installs by default.** In order it: runs the suite and stops if anything fails,
builds the release binary, assembles `DevDeck.app` in the repository, ad-hoc signs it, then
quits any running copy, replaces `/Applications/DevDeck.app` and launches the new one. Nothing
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
| `swift run DevDeck` | runs from the terminal without bundling - handy for `print` debugging |
| `pkill -f DevDeck` | quits every running copy |

**Settings → General shows the running version** - `DevDeck 0.3 (build 31)` - and which bundle
it came from. The marketing number lives in `VERSION` and is bumped by hand when a release
earns a name; the build number is the commit count, so it moves on every rebuild. That is the
quickest way to tell whether the copy in front of you is the change you just made or the one
that was already running.

**After every rebuild macOS asks for the login keychain once.** Ad-hoc signing gives the app a
new identity each build, so "Always Allow" holds only until the next `./build.sh`. See
[docs/development.md](docs/development.md) for the details and the permanent fix if it ever
becomes worth it.

### First run

```bash
scripts/seed-token.sh        # optional: copies a token from env.local into the Keychain
scripts/smoke-test.sh        # optional: one real API call, prints counts, never the token
```

`seed-token.sh` takes an account and a variable name, because one token per account is the
point - a fine-grained token is approved per organisation, so no single one covers every
employer:

```bash
scripts/seed-token.sh --var SHUMER_GITHUB_TOKEN          # a differently named variable
scripts/seed-token.sh --account work --var WORK_TOKEN    # the second account's own token
```

The account id is the one in **Settings → GitHub accounts**; `default` is the first account and
keeps the un-suffixed Keychain key. The token is checked against the API before it is stored, so
a rejected one never lands in the Keychain to fail invisibly later.

Without a token the app opens its settings window on first launch; paste one there instead.
It is verified against the API before it is stored, and it only ever lives in the login
Keychain.

Settings live in the `com.shumer.devdeck` preferences domain. To start over:
`defaults delete com.shumer.devdeck` (tokens survive that - they are in the Keychain).

### Several accounts

One token rarely covers everything: a fine-grained token is approved per organisation, and
some organisations sit behind SAML SSO. **Settings → GitHub accounts** manages a list - each
account has its own label, its own organisations and its own token in the Keychain.

All accounts feed the same cards. Pull requests visible to two accounts are shown once. When
one account fails, the others still render and the card footer says which one is missing;
a card only fails outright when every account fails. With more than one account configured,
every row carries a chip saying which one it came from.

### Links open as the right identity

github.com allows one signed-in identity per browser profile, so "open in the default browser"
is wrong half the time when work and personal accounts are both on the deck. Each account has
an **Open links in** setting: a browser, and for Chrome, Edge, Brave, Vivaldi and Chromium a
profile as well, listed by the names you gave them. Clicking a row then lands in the profile
that is signed in as that account.

The pickers apply the moment you change them - there is a **Test** button beside them that
opens one page so you can see where it lands. Only the token needs an explicit **Verify
token** press, because it is checked against the API before being stored.

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

`scripts/smoke-test.sh` prints how many organisations the token can actually see, which is
the fastest way to tell "no open pull requests" from "cannot see the organisation".

## Arc XP projects

**Settings → Arc projects → Add project.** Each project becomes its own card with the links
you use, the browser they open in, and control of its local Fusion stack.

- **Links** are templates with `{org}` and `{site}` substituted. **The organisation field
  carries the environment**: type `sandbox.acme` for the sandbox and `acme` for
  production, and the templates add nothing of their own - PageBuilder becomes
  `https://sandbox.acme.arcpublishing.com/home/`. PageBuilder, Composer and Deployer are
  confirmed against a real organisation; Site Service and Delivery API are guesses, so press
  **Test** on each and edit the field in place when it is wrong.
- **Sandbox and Prod ship empty**: a published site lives on its own domain and there is
  nothing to derive it from. Paste the URLs in and switch them on.
- **Two rows.** Arc's tooling on top - PageBuilder, Composer, Deployer, all in blue - and the
  environments you can open below it, in the order local, sandbox, production. The local chip
  is green while the stack is up and grey when it is not, sandbox is violet and production
  amber: production is the one worth a beat of hesitation, so it is the one that is not calm.
- **Local stack** buttons run the Arc CLI in the project folder: **Start** is `npx fusion
  daemon` (the CLI's background mode - `fusion start` runs in the foreground and would hold
  the app hostage), **Stop** is `npx fusion stop`, **Restart** is one then the other. All three
  are editable per project.
- **Running or not** is answered by asking the engine, not by watching processes: the card
  requests `/release` and shows the engine version it reports. A stack you started by hand in
  a terminal therefore shows as running too - the card reports what is actually serving.
- **The port comes from the project's `.env`.** Fusion defaults to 80, but `PORT` in the
  checkout overrides it, and that file is the only honest source. Leave **Local URL** empty
  and the card follows it; fill it in only for a stack that does not. The chip says
  **Local site** and greys out while the stack is down; the address it opens is in its
  tooltip, along with every other link's.
- **After a start the card waits.** `fusion daemon` returns as soon as the containers exist,
  while the engine needs longer to serve, so the card polls for up to a minute before
  concluding anything - and if nothing ever answers it names the URL it tried.
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

**Settings → DDEV projects → Add project** offers what `ddev list` found, so there is no
folder to go hunting for - DDEV already knows every project on the machine.

- **One `ddev list -j` answers for the whole deck.** Six cards cost the same as one, which is
  why this is a shared environment rather than a probe per project.
- **The framework version comes from `composer.lock`.** DDEV's own `type:` is a setting
  nobody updates after an upgrade - two projects here still said `drupal9` while running
  Drupal 11.4.4 and 10.6.11 - so the footer reads the lock file, which cannot drift that way,
  and falls back to the DDEV type only when there is no lock file at all.
- **PHP and database versions come from `.ddev/config.yaml`.** `ddev list` does not carry
  them and `ddev describe` is a process per project, while the file is right there in the
  checkout - the same trick as Arc's `PORT` and the git branch.
- **Paused is its own state.** DDEV pauses containers without tearing them down, and calling
  that "stopped" would misrepresent what pressing Start is about to do.
- **A broken file sync is called out.** When mutagen is enabled and not `ok`, the card says
  so: edits stop reaching the container and nothing else on screen would hint at why.
- **Two rows of links.** Mailpit and xhgui on top, straight from DDEV - Mailpit on by
  default, xhgui not. Below them the environments: the local site, which DDEV reports, then
  **Test, UAT and Prod**, which ship empty for you to paste addresses into. Local is green,
  test and UAT violet, production amber.
- **Only the local link waits on the container.** It is dimmed while the project is down,
  because a link into a stopped project lands on a connection error that reads as a broken
  app; a deployed site is reachable either way.
- **Power off all DDEV** in the menu runs `ddev poweroff` - every project and the router, for
  when the laptop needs its memory back.

## Plain projects

Everything that is neither Arc nor DDEV: a compose stack, a dev server, a Makefile. **Settings
→ Projects → +** asks for a folder and then reads it - a compose file, a `dev` script in
`package.json`, a `up:` target in a Makefile - and fills the commands in for you. The **Detect**
button does the same again later, and nothing is ever guessed over something you typed.

- **One checkbox decides how the command is run.** *The command keeps running* is on for
  `npm run dev` and off for `docker compose up -d`. A command that holds its process is started
  detached with `nohup`, its output goes to a log under `~/Library/Application
  Support/DevDeck/projects`, and its process id is written down beside it; the card's log tray
  shows the end of that file, and the arrow inside it opens the whole thing. A command that returns is simply run and waited for, with its output kept in
  the same log.
- **Stop kills the whole tree** when there is no stop command of your own. `npm run dev` is a
  wrapper, and killing it alone leaves the server it spawned holding the port - which then makes
  the next start fail for a reason nothing on screen would explain.
- **The health URL decides whether it is running**, exactly as the Arc card asks the engine - so
  a stack you started yourself in a terminal reads as running too. Up means 2xx, 3xx, 401 or 403;
  a 404 or a 500 does not count. A local port is a shared resource, and the first version of this
  rule counted any answer at all: a Docker container from another project held 8080, answered the
  configured `/health` with a 404, and the card reported a backend nobody had started as running.
- **Live process, silent URL, is `starting…`** rather than stopped - that is a dev server
  compiling, and it resolves itself within seconds.
- **Test, UAT and Prod ship empty**, next to the local site, the same as everywhere else. Extra
  tooling links may use `{site}` to avoid repeating the port.
- **Needs Docker** puts the card behind the Docker check below. It is ticked for you when the
  folder is a compose project.

The commands run in the project folder through a login shell, so `npm`, `make` and `docker` are
found the same way your terminal finds them.

## Docker

Every local project sits on a container runtime, and a Start pressed without one produces a wall
of shell output the card has nowhere to put. So the deck asks first, once for the whole deck, on
the same ten-second loop: `docker version --format '{{.Server.Version}}'`.

- **The daemon is asked, not the process table.** Colima, OrbStack, Rancher and a remote context
  all serve `docker` with no Docker Desktop anywhere, and looking for a running app would call
  every one of them "not running".
- **A card that needs Docker says so** - the pill reads `docker off`, the state line says why,
  and the Start button becomes **▶ Start Docker**, which opens Docker Desktop (or OrbStack,
  Rancher, Podman Desktop) without stealing focus. The card then says `docker starting…` until
  the daemon answers.
- **A running project is never gated.** Something is clearly serving it, and no probe beats that.
- **Not having asked yet blocks nothing**, so the first second of a launch does not grey out
  every button.
- Where there is no runtime application to open - Colima is a CLI - the card shows a disabled
  Start rather than a button that would do nothing.

### Status codes

Rows end in a two-character code so the width goes to the title. Hovering a row spells it out.

| | | | |
|---|---|---|---|
| `RV` | waiting for **your** review | `CP` | checks running |
| `CF` | checks failed | `DR` | draft |
| `CR` | changes requested | `AP` | approved |
| `T3` | three unresolved threads | `WR` | waiting for review |

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

- **Cards** - show or hide each card; a hidden card is not fetched at all. Projects get their own
  group per kind, below the built-in cards.
- **Tidy panels into columns** - close up gaps without resetting where you put them. It anchors
  on the topmost panel and stacks downwards, starting a new column beside it whenever the next
  card would hang below the screen, so a deck of six cannot push its last card under the bottom
  edge where nothing can grab it. The order it lays out is the deck's own: the built-in cards,
  then Arc projects, then DDEV, then the plain ones, each group alphabetical.
- **Power off all DDEV**, **Open pull requests in browser**, **Refresh now**, **Settings…**, **Quit**

What the deck *is* rather than what you do with it lives in Settings, under General: where the
panels sit, whether they are locked, whether a column packs itself, the summon shortcut and its
dimming, and start-at-login. A menu that mixes the two grows until the thing you came for is
somewhere in the middle of it.

Right-click a panel for the same menu, with **Collapse to one row** for that card on top.

The settings window is three columns: the sections - GitHub accounts, Arc projects, DDEV
projects, Projects, General - then what is in the section, then the form for the one selected. Only one
account or project has a form on screen at a time, which is what keeps two similarly named
projects apart, and the form stretches with the window. Add and remove are the `+` and `−`
under the list. Everything applies as you change it; only a token waits for **Verify token**,
because it is checked against the API before being stored.

Drag a panel anywhere; the position is remembered per card - **against the display it is on**,
not as a point on the desktop. Unplug the external monitor and the cards that live on it are
parked on whatever screen is left, keeping their distance from the top; plug it back in and they
go home. Nothing is re-saved while a card is parked, because parking is not a decision you made.
This is why a deck kept on the laptop screen no longer scatters when an external display that
happens to be the main one comes and goes, and why quitting and reopening puts every panel back
exactly where it was rather than a little further down each time. The deck moves a card only when
you asked it to: collapsing one, opening a log, expanding a list. Data arriving never moves
anything. **Keep the column packed**, in Settings and off by default, closes the gaps in a column whenever
a card changes height, at the price of any gap you left in it on purpose.

The menu-bar menu holds what you *do*: which cards are on the deck, Tidy, Refresh now, Power off
all DDEV, Settings and Quit. What the deck *is* lives in Settings under General: where the panels
sit, whether they are locked, whether the column packs itself, the summon shortcut and its
dimming, and start-at-login. While the display a card belongs to is unplugged the
card is parked somewhere visible and still remembers where it lives - but if you tidy or drag it
while it is parked, that is where it now lives, and it stays there. Click a row to open that pull
request, double-click the panel background to open the list on github.com, right-click a
panel for the same menu.

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
   kind of project it is - the octocat, Arc's A, DDEV's mark, Node's hexagon, Docker's whale, a
   hammer for a Makefile. They are the real logos, drawn from the vendors' own SVG path data
   rather than shipped as images: this toolchain has no asset catalog, and a hand-drawn
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
   command on the right.
5. **The links**, in one wrapping row: what you work in, a divider, then the environments -
   local first, then test and UAT in violet, production in amber. They all share one neutral
   fill; the colour is in the lettering, mixed back towards white, so five links in a row read
   as a row rather than as five things shouting.
6. **The controls.** The one action that matters now is half again as wide, tinted, bolder and
   the only one with an outline; the rest recede to a plain fill. All four carry an icon.

**Hold ⌥Space** and the deck comes up over your windows; let go and it drops back. A tap keeps it
up until the next press. Nothing moves and nothing is redrawn: they are the same panels at a
different window level, which is why this costs almost nothing. The screen dims 45% while they are
up, because dark glass over a white editor is unreadable otherwise. Both of those are switches in
the menu-bar menu, and the combination itself is in Settings under General. It needs no
permission: the shortcut is a Carbon hot key, not a global key monitor, so macOS has nothing to
ask you about.

Right-click a panel and **Collapse to one row** folds the card down to 44 points: the mark, the
state dot, the name, one note and the single action that state implies. Every card can do it. On a
project that action is Start or Stop; on a list card, which has no lifecycle, it opens the same
list on the web. It is remembered per card,
so the projects you are not working on today take a row each while the one you are stays whole.
Six collapsed cards come to 324 points against 1218 whole.

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

## Documentation

- [docs/architecture.md](docs/architecture.md) - modules, data flow, where to add a card
- [docs/github-api.md](docs/github-api.md) - the GraphQL query, rate limits, token setup
- [docs/development.md](docs/development.md) - toolchain, scripts, definition of done
- [docs/roadmap.md](docs/roadmap.md) - what is done and what is next
- [docs/adr/](docs/adr/) - twelve decisions and what they cost: why native, why SwiftPM only,
  why cards are configurable, why accounts are plural, how local stacks are driven, why DDEV
  shares one call, how a plain project is started, why Docker is checked first, how a card is
  laid out, why the deck is quieter than it was, why a card has two sizes and only two, and why
  the deck moves a card only when it was asked to, and why GitLab is a card of its own

## Layout

```
Sources/
  DevDeckCore/     configuration, cards, HTTP transport, tokens, policies, command runner,
                   git branch, browser choice, the Docker probe
  GitHubKit/       GraphQL and REST clients, models, per-account fan-out
  ArcKit/          Arc projects, link templates, local Fusion stack, .env port
  DDEVKit/         DDEV projects, ddev list, .ddev/config.yaml, composer.lock version
  ProjectKit/      plain projects: folder probe, detached start, log and pid, health check
  DevDeckUI/       SwiftUI cards, the shared card pieces, the brand marks and their SVG
                   parser, and the visual language
  DevDeckApp/      AppKit shell: panels, menu bar, placement, settings
Tests/
  TestHarness/     tiny test framework and fakes
  DevDeckTests/    the suite (232 tests, offline)
Tools/
  Smoke/           live API check
  IconPreview/     renders the menu-bar icon at the size it is actually seen
```
