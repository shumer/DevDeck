# DevDeck

Desktop panels for the things a developer checks twenty times a day: open pull requests,
review requests, deploys. Frosted cards that sit on the macOS desktop behind your windows,
plus a menu-bar item with the count.

Native macOS, built from a SwiftPM package with no Xcode required.

```
┌──────────────────────────────────────────┐
│ GITHUB · MY PULL REQUESTS     2 BLOCKED  │
│                                          │
│  7 open                                  │
│  ● feat/composer-block     checks failed │
│  ● fix/pb-image-fill  changes requested  │
│  ● chore/bundle-bump           approved  │
│                                          │
│  3 repos · 2 orgs             20:16:39   │
└──────────────────────────────────────────┘
```

## Status

| Card | State | On by default |
|---|---|---|
| GitHub · my pull requests | working | yes |
| GitHub · inbox (notifications) | working | yes |
| GitHub · Actions | working | no |
| Arc XP · one card per project | working | added per project |
| DDEV · one card per project | working | added per project |
| Arc XP · deployed bundle versions | planned — needs an org token | — |

The Actions card watches the repositories your open pull requests are in, up to five, unless
`actionsRepositories` says otherwise.

## Build and run

Needs the Swift 6 toolchain from the Command Line Tools — `xcode-select --install`. **Xcode is
not required**: there is no project file and nothing here opens in it. Docker is only needed
for the Arc cards' local stack.

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
and the bundle in the repository is deleted and recreated on every build — so "Start at login"
only works for the installed copy.

| Command | What it does |
|---|---|
| `./build.sh` | the whole thing: test, build, install to `/Applications`, launch |
| `./build.sh --no-install` | builds `./DevDeck.app` only; open it yourself with `open ./DevDeck.app` |
| `./build.sh --skip-tests` | skips the suite; fine for a quick loop, never in CI |
| `./build.sh --skip-tests --no-install` | both, in that order |
| `swift run DevDeck` | runs from the terminal without bundling — handy for `print` debugging |
| `pkill -f DevDeck` | quits every running copy |

**Settings → General shows the running version** — `DevDeck 0.1 (build 21)` — and which bundle
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

Without a token the app opens its settings window on first launch; paste one there instead.
It is verified against the API before it is stored, and it only ever lives in the login
Keychain.

Settings live in the `com.shumer.devdeck` preferences domain. To start over:
`defaults delete com.shumer.devdeck` (tokens survive that — they are in the Keychain).

### Several accounts

One token rarely covers everything: a fine-grained token is approved per organisation, and
some organisations sit behind SAML SSO. **Menu bar → GitHub accounts…** manages a list —
each account has its own label, its own organisations and its own token in the Keychain.

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

The pickers apply the moment you change them — there is a **Test** button beside them that
opens one page so you can see where it lands. Only the token needs an explicit **Verify
token** press, because it is checked against the API before being stored.

Safari has profiles but no way to choose one from outside the app, and Firefox's `-P` depends
on what is already running; both are offered without a profile picker rather than with one
that would not work.

### Seeing everything

Cards show three rows and a **show N more** line. Clicking it grows the panel to show up to
twelve, pushing the panels below it down; clicking again collapses. It is deliberately not
remembered — expanding is a "let me look at this now" gesture, and a deck that comes back tall
the next morning is a surprise.

### The token

A fine-grained personal access token with read access to **pull requests**, **contents** and
**metadata** covers the pull requests card. The inbox card also needs the account-level
**notifications** permission, and the Actions card needs **actions** (read). Three things
catch people out:

- the **notifications** permission sits under the account section rather than the repository
  section, and without it the inbox card shows
  `Forbidden — Resource not accessible by personal access token`;

- a fine-grained token must be **approved by each organisation** before it can see anything
  there, and until then the API answers with an empty result rather than an error;
- under SAML SSO, a classic token must be **authorised for each organisation** as well.

`scripts/smoke-test.sh` prints how many organisations the token can actually see, which is
the fastest way to tell "no open pull requests" from "cannot see the organisation".

## Arc XP projects

**Settings → Arc projects → Add project.** Each project becomes its own card with the links
you use, the browser they open in, and control of its local Fusion stack.

- **Links** are templates with `{org}` and `{site}` substituted. **The organisation field
  carries the environment**: type `sandbox.ilgiornale` for the sandbox and `ilgiornale` for
  production, and the templates add nothing of their own — PageBuilder becomes
  `https://sandbox.ilgiornale.arcpublishing.com/home/`. PageBuilder, Composer and Deployer are
  confirmed against a real organisation; Site Service and Delivery API are guesses, so press
  **Test** on each and edit the field in place when it is wrong.
- **Sandbox and Prod ship empty**: a published site lives on its own domain and there is
  nothing to derive it from. Paste the URLs in and switch them on.
- **Two rows.** Arc's tooling on top — PageBuilder, Composer, Deployer, all in blue — and the
  environments you can open below it, in the order local, sandbox, production. The local chip
  is green while the stack is up and grey when it is not, sandbox is violet and production
  amber: production is the one worth a beat of hesitation, so it is the one that is not calm.
- **Local stack** buttons run the Arc CLI in the project folder: **Start** is `npx fusion
  daemon` (the CLI's background mode — `fusion start` runs in the foreground and would hold
  the app hostage), **Stop** is `npx fusion stop`, **Restart** is one then the other. All three
  are editable per project.
- **Running or not** is answered by asking the engine, not by watching processes: the card
  requests `/release` and shows the engine version it reports. A stack you started by hand in
  a terminal therefore shows as running too — the card reports what is actually serving.
- **The port comes from the project's `.env`.** Fusion defaults to 80, but `PORT` in the
  checkout overrides it, and that file is the only honest source. Leave **Local URL** empty
  and the card follows it; fill it in only for a stack that does not. The chip says
  **Local site** and greys out while the stack is down; the address it opens is in its
  tooltip, along with every other link's.
- **After a start the card waits.** `fusion daemon` returns as soon as the containers exist,
  while the engine needs longer to serve, so the card polls for up to a minute before
  concluding anything — and if nothing ever answers it names the URL it tried.
- **The branch is on the card.** Whatever `.git/HEAD` says, read directly rather than by
  running `git` every ten seconds — so you can see what the running stack is actually serving,
  including after switching branches in a terminal.
- **Folder** opens the checkout in Finder, **Terminal** opens it in iTerm, Warp or Terminal,
  whichever is installed.

Commands run through a login shell (`zsh -lc`) on purpose. An app launched from Finder
inherits a bare `PATH` with no Homebrew and no nvm, so a plain `npx` would not be found and
the buttons would appear to do nothing.

## DDEV projects

**Settings → DDEV projects → Add project** offers what `ddev list` found, so there is no
folder to go hunting for — DDEV already knows every project on the machine.

- **One `ddev list -j` answers for the whole deck.** Six cards cost the same as one, which is
  why this is a shared environment rather than a probe per project.
- **The framework version comes from `composer.lock`.** DDEV's own `type:` is a setting
  nobody updates after an upgrade — two projects here still said `drupal9` while running
  Drupal 11.4.4 and 10.6.11 — so the footer reads the lock file, which cannot drift that way,
  and falls back to the DDEV type only when there is no lock file at all.
- **PHP and database versions come from `.ddev/config.yaml`.** `ddev list` does not carry
  them and `ddev describe` is a process per project, while the file is right there in the
  checkout — the same trick as Arc's `PORT` and the git branch.
- **Paused is its own state.** DDEV pauses containers without tearing them down, and calling
  that "stopped" would misrepresent what pressing Start is about to do.
- **A broken file sync is called out.** When mutagen is enabled and not `ok`, the card says
  so: edits stop reaching the container and nothing else on screen would hint at why.
- **Site, Mailpit and xhgui** come straight from DDEV; Mailpit is on by default, xhgui is not.
  Links are dimmed rather than hidden while the project is down, because a link into a stopped
  project lands on a connection error that reads as a broken app.
- **Power off all DDEV** in the menu runs `ddev poweroff` — every project and the router, for
  when the laptop needs its memory back.

### Status codes

Rows end in a two-character code so the width goes to the title. Hovering a row spells it out.

| | | | |
|---|---|---|---|
| `CF` | checks failed | `CP` | checks running |
| `CR` | changes requested | `DR` | draft |
| `AP` | approved | `WR` | waiting for review |
| `T3` | three unresolved threads | | |

The coloured dot says the same thing at a glance: red is blocked, amber needs someone, green
is done.

## Using it

The menu-bar item is a stack of cards with the app's initials cut out of the front one, and it
turns red when something needs you — the numbers are in its tooltip rather than in the menu
bar, where a bare count belongs to no app in particular. It is drawn in code
(`DeckIcon`), and `swift run IconPreview out.png` renders it at menu-bar size, on a light and
a dark bar, for when it needs adjusting.

Everything else lives in its menu:

- **Cards** — show or hide each card; a hidden card is not fetched at all. Arc projects get
  their own group below the built-in cards.
- **Keep on desktop / Float above windows** — panels behind your windows, or above them.
- **Lock position** — stop dragging once the layout is right.
- **Tidy panels into a column** — close up gaps without resetting where you put them.
- **Start at login**, **Refresh now**, **Settings…** — one window with GitHub accounts, Arc
  projects and General kept in separate sections.

Drag a panel anywhere; the position is remembered per card. Click a row to open that pull
request, double-click the panel background to open the list on github.com, right-click a
panel for the same menu.

Anything clickable lights up under the pointer and turns the cursor into a hand. Because the
panels sit behind other windows, that tracking starts once the deck itself has been clicked —
so buttons and links also carry a resting fill rather than relying on hover to look pressable.

## Documentation

- [docs/architecture.md](docs/architecture.md) — modules, data flow, where to add a card
- [docs/github-api.md](docs/github-api.md) — the GraphQL query, rate limits, token setup
- [docs/development.md](docs/development.md) — toolchain, scripts, definition of done
- [docs/roadmap.md](docs/roadmap.md) — what is next and the open questions on Arc XP
- [docs/adr/](docs/adr/) — why native, why SwiftPM only, why cards are configurable

## Layout

```
Sources/
  DevDeckCore/     configuration, cards, HTTP transport, tokens, policies, command runner
  GitHubKit/       GraphQL and REST clients, models, per-account fan-out
  ArcKit/          Arc projects, link templates, local Fusion stack
  DevDeckUI/       SwiftUI cards and the shared visual language
  DevDeckApp/      AppKit shell: panels, menu bar, placement, settings
Tests/
  TestHarness/     tiny test framework and fakes
  DevDeckTests/    the suite (114 tests, offline)
Tools/Smoke/       live API check
```
