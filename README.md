# DevDeck

Desktop panels for the things a developer checks twenty times a day: open pull requests,
review requests, deploys. Frosted cards that sit on the desktop behind your windows, plus a
menu-bar item with the count.

Native macOS, built from a SwiftPM package with no Xcode required. The same engine runs on
Windows 11 under a WPF shell, in beta: see [Windows](#windows) below.

Pull requests across every account a token can see - yours and the ones waiting on your
review - worst first:

```
┌────────────────────────────────────────────┐
│  PULL REQUESTS                    23:26:37 │
│ 8 open                          2 BLOCKED  │
│ ▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂ │
│ ● WORK PROJ-142 Add the article feed…   CF │
│ ● WORK PROJ-77  Fix the image fill on…  CR │
│ ● WORK 👁 PROJ-164 Approvers resource…  RV │
│           show 5 more ⌄                    │
│ 4 repos · 2 orgs                           │
└────────────────────────────────────────────┘
```

## What is on the deck


| Card | State | On by default |
|---|---|---|
| GitHub · pull requests | working | yes |
| GitHub · inbox (notifications) | working | yes |
| GitHub · Actions | working | no |
| GitLab · merge requests | working | switched on when you add an instance |
| Azure DevOps · pull requests | working | switched on when you add an organization |
| Arc XP · one card per project | working | added per project |
| DDEV · one card per project | working | added per project |
| Project · one card per project | working | added per project |
| Work in flight · every checkout at once | working | no |

Every card is one thing you would otherwise go and check: the deck polls it, words it, and
decides what needs you. The cards are described in [docs/cards.md](docs/cards.md).

## What it does

- **Pull requests, reviews, the inbox and CI** across every GitHub account, GitLab instance and
  Azure DevOps organization a token can see, worst first, with one request per account per refresh.
- **Local projects as cards**: Arc XP Fusion stacks, DDEV sites and any folder with a start
  command, with Start, Stop and Restart, the log in a window, the branch, the links you use, and
  a QR code to open the site on your phone.
- **A menu that says what needs you**, in four tiers: somebody waiting on you, something to fix
  on this computer, your own stuck work, and what is good to know. Banners for the first two.
- **A deck that stays where you put it**: frosted panels behind your windows, folded to one row
  when a project is not today's, summoned over everything with a key, saved arrangements per
  display.
- **Six languages**, chosen in Settings or following the system.
- **Self-updating** from GitHub releases, asking before it installs.
- **An MCP server** so a coding agent on the same computer can ask the deck what needs you and
  what changed since it last looked and, when allowed, run a project's buttons, open a page as
  the right account or add a card for the folder it works in.

## Install

### macOS

macOS 14 or later. Download `DevDeck-<version>-<build>-macos.zip` from the
[latest release](https://github.com/shumer/DevDeck/releases/latest), unzip it, drag
`DevDeck.app` into Applications and open it. The build is signed with a Developer ID and
notarised, so macOS opens it as it is; from then on the app updates itself when you ask. Add a
GitHub token in Settings, one per account, and the cards fill in. Tokens, accounts and the
Keychain are in [docs/accounts.md](docs/accounts.md).

### Windows

Windows 11 22H2 or later, in beta. Download `DevDeck-<version>-<build>-windows-setup.exe` from
the same release and run it: it installs for your user without administrator rights, fetches
.NET 10 Desktop Runtime from Microsoft if it is missing, and updates itself afterwards. The
build is not signed, so SmartScreen warns on first run: **More info**, then **Run anyway**.
Projects in WSL distributions and in Windows folders both work, with Docker Desktop or Docker
inside WSL. The same engine draws both decks; what differs is in
[Windows/README.md](Windows/README.md).

### From source

```bash
git clone git@github.com:shumer/DevDeck.git widgets && cd widgets
./run-tests.sh          # offline suite, must be green
./build.sh              # tests, build, bundle, install to /Applications, launch
```

Needs the Swift 6 toolchain from the Command Line Tools and nothing else; Xcode is not
required. Every command, flag and script is in [docs/development.md](docs/development.md).

## For agents

A coding agent on the same computer can ask the deck what needs you, read every card and a
project's log, and, when you allow it, start, stop and restart projects, mark notifications
read, and add a card for the folder it is working in, with the start command and the address
it knows. It goes through the Model Context Protocol: `DevDeckMCP` ships inside the app, and the
answers come from the running deck in its own words, so the agent needs no token of its own.

Settings, General, **Agents (MCP)** has three choices: Off (the default), Read only, and Read and
control. Turning it on registers the server with Claude Code and Codex on this computer, and
turning it off removes it; the page says how that went. The endpoint
is a socket only you can open, nothing listens on a network port, and a command follows the
rules the card's buttons follow: a project started outside DevDeck is not stopped by an agent
either. [docs/mcp.md](docs/mcp.md) lists the tools and how to add the server to other clients;
[adr/0036](docs/adr/0036-agent-access.md) says why it is built this way.

## Documentation

- [docs/cards.md](docs/cards.md) - every card: what it shows, where the words come from, what the buttons do
- [docs/deck.md](docs/deck.md) - the deck itself: placing, folding, summoning, the menu, notifications, log windows, languages
- [docs/accounts.md](docs/accounts.md) - tokens, several accounts, which identity a link opens as, the Keychain
- [docs/releases.md](docs/releases.md) - how a release is cut and how the app updates itself
- [docs/mcp.md](docs/mcp.md) - the MCP server: settings, tools, registering it with an agent
- [docs/development.md](docs/development.md) - toolchain, every command, tests, signing, the repository's layout, definition of done
- [docs/architecture.md](docs/architecture.md) - modules, data flow, where to add a card
- [docs/github-api.md](docs/github-api.md) - the GraphQL query, rate limits, token setup
- [docs/roadmap.md](docs/roadmap.md) - what is done and what is next
- [Windows/README.md](Windows/README.md) - the Windows shell: build, install, updates, what differs
- [docs/engine-protocol.md](docs/engine-protocol.md) - protocol v2 between the engine and a shell in another process
- [docs/windows-migration.md](docs/windows-migration.md) - the port's plan, its state and its decisions
- [docs/windows-style.md](docs/windows-style.md) - how a card is drawn on Windows
- [docs/adr/](docs/adr/) - the decisions and what they cost, one file each

## License

DevDeck is free to use, personally and at work, and the source is here to be read. It is not
open source: you may build it and propose changes back, but distributing it, publishing a fork
or shipping a changed version needs the author's written permission. The exact terms are in
[LICENSE](LICENSE).

Changes are welcome as pull requests. [CONTRIBUTING.md](CONTRIBUTING.md) has the checks every change
passes before it is committed, the invariants the code keeps and the style it is written in.
