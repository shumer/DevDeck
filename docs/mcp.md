# DevDeck for agents

DevDeck can answer a coding agent on the same computer through the Model Context Protocol: what
needs you, every card, a project's log, and, when you allow it, starting and stopping projects
and marking notifications read. The answers come from the running deck, in its words. Why it is
built this way is [adr/0036](adr/0036-agent-access.md).

## Turning it on

Settings, General, **Agents (MCP)**:

| Setting | What an agent can do |
| --- | --- |
| Off (default) | Nothing. No endpoint is open. |
| Read only | `what_needs_me`, `what_changed`, `wait_for`, `project_time`, `cards`, `project_log`, `detect_project`. |
| Read and control | The above, plus `start_project`, `stop_project`, `restart_project`, `mark_inbox_read`, `add_project`, `update_project`, `open`. |

The change takes effect at once. Below the choice the page shows one row per agent on this
computer and where the deck's server stands with it.

## Registering the server

DevDeck does this itself. Turning the setting on puts `DevDeckMCP` on the server list of every
agent installed on this computer, with the agents' own command-line tools (`claude mcp add`,
`codex mcp add`); turning it off takes it off again (`claude mcp remove`, `codex mcp remove`).
A launch with the setting already on checks each list and repairs an entry that is missing,
which is also how an upgrade that moved the executable is caught. Codex is looked for on the
path and then inside the ChatGPT application on the Mac, which carries the same tool and reads
the same `~/.codex/config.toml`. Nothing else on the computer is changed, and an agent that is
not installed is said to be that, with the line to run by hand once it is. The rows under the
setting say how it went.

The same by hand, for a client the deck does not know or a machine where the tools are not on
the path. Claude Code, on the Mac, for every project on this computer:

```bash
claude mcp add --scope user devdeck -- /Applications/DevDeck.app/Contents/Helpers/DevDeckMCP
```

On Windows:

```powershell
claude mcp add --scope user devdeck -- "$env:LOCALAPPDATA\Programs\DevDeck\DevDeckMCP.exe"
```

`--scope user` is what makes it global. Without it Claude Code registers the server for the
folder the command ran in only, its `local` scope, and in any other project the tools are not
there. The deck is about you rather than about one repository, so user scope is the one that
makes sense; `claude mcp list` shows where it is registered.

Codex, on the Mac:

```bash
codex mcp add devdeck -- /Applications/DevDeck.app/Contents/Helpers/DevDeckMCP
```

On Windows:

```powershell
codex mcp add devdeck -- "$env:LOCALAPPDATA\Programs\DevDeck\DevDeckMCP.exe"
```

Codex keeps its servers in `~/.codex/config.toml`, which is global already, so there is no scope
to choose; `codex mcp list` shows what is registered. The same entry can be written by hand:

```toml
[mcp_servers.devdeck]
command = "/Applications/DevDeck.app/Contents/Helpers/DevDeckMCP"
```

Cursor and other clients take the same executable as a stdio server with no arguments, for
example in `.cursor/mcp.json`:

```json
{ "mcpServers": { "devdeck": { "command": "/Applications/DevDeck.app/Contents/Helpers/DevDeckMCP" } } }
```

## Tools

| Tool | Arguments | Answer |
| --- | --- | --- |
| `what_needs_me` | | The menu's rows, most urgent first: `tier` (`waiting`, `needsFixing`, `stuck`, `goodToKnow`), `title`, `subtitle`, `since`, and the `card`, `url` or inbox `thread` the row is about. |
| `what_changed` | | What is new since the agent last asked `what_needs_me` or `what_changed` in this session: `added` rows, `gone` rows (dealt with since), and `projects` whose state changed, each with `was` and `now`. The first call reports everything as new with `firstCall`. The memory is the server process's, one per agent session; the deck remembers nothing about who asked. |
| `wait_for` | `until`, with `card` or `url`, `timeout` | Polls the deck every few seconds until a project card is `running`, `stopped`, `healthy` or `changed`, or a pull request's checks are no longer running (`checks`), up to `timeout` seconds (default 180, at most 600). Answers with the state it ended on and `satisfied`. A pull request gone from every card counts as settled. |
| `project_time` | | How long each project ran today and over the last seven days, as the deck observed it: `todaySeconds`, `weekSeconds`, and both in words. |
| `cards` | `card` (optional) | Every card on the deck as `{card, model}`, the model being what the shell draws. |
| `project_log` | `card` | The last lines of the project's log and where they come from. |
| `start_project`, `stop_project`, `restart_project` | `card`, `replace` | Runs the card's button, waits up to three minutes for it, and returns the card. `done` is false when it is still going. Fusion runs one local stack at a time, so starting or restarting an Arc project while another Arc card is up is refused with that card's name; with `replace: true` the deck stops that one first, on record as the agent's stop, then starts this one. |
| `mark_inbox_read` | `thread` (optional) | Marks that thread read; without one, everything in the inbox that is not addressed to you. Returns `what_needs_me`'s rows. |
| `detect_project` | `folder` | What DevDeck would make of the folder: `kind` is `arc` for a Fusion checkout (`@arc-fusion/cli` in `package.json`), `ddev` for a DDEV project, `plain` otherwise; for a plain one, what its files say about the start command, the process, Docker and the health URL. Says if the folder is already on the deck, as which card. |
| `add_project` | `folder`, then `kind`, `title`, `organization`, `site`, `start_command`, `stop_command`, `holds_process`, `requires_docker`, `health_url`, `local_site_url`, `links`, all optional | A card for the folder, of the kind the folder is. An Arc checkout needs `organization` (`sandbox.acme` or `acme`) and gets the Fusion CLI's start, stop and health check; a DDEV project is taken from `ddev list`; a plain project is read from its files, and what the agent passes wins. `links` fills the card's slots by label (Test, UAT, Prod; Sandbox, Prod on Arc) or adds new ones, `kind: tool` for something you work in. A folder already on the deck is refused, naming its card. |
| `update_project` | `card`, then the same fields | Changes a card on the deck; fields left out stay, links are matched by label. Removing a card stays in Settings. |
| `open` | `url`, or `card` with `target` | Puts something on the person's screen. A `url` opens in the browser of the account whose host it is, so a GitHub, GitLab or Azure DevOps page opens signed in as the right person; anywhere else, the default browser. With a `card`: `card` (default) brings the deck up on it with its log, `folder` shows its folder, `terminal` opens a terminal there, `site` opens its local site when it is up or its first published one. Needs control: it is the person's screen. |

Every command the server sends carries the client's name from `initialize` (`Claude Code`,
`Codex`, `Cursor`, or whatever the client calls itself). A start or stop an agent pressed is
written down as the agent's: the menu says "Claude Code started Feed" under Good to know until
you press a button on that card yourself or dismiss the row, the card's state line says
"started by Claude Code" while it runs, and the log window's source line says the same.

In Claude Code, inside a repository: "add this project to DevDeck, it starts with `npm run
dev` and answers on port 3000" is enough; the agent passes the folder it is in and the two
values, the deck fills in the rest from the folder's files.

Card ids are what `cards` lists: `project.<id>`, `arc.project.<id>`, `ddev.project.<id>`,
`github.pullRequests` and so on. A command the deck refuses comes back as a tool error in the
deck's words: the setting is read only, the card is not on the deck, or the project was started
outside DevDeck, which the card's own hero says.

## Safety

The endpoint is for the signed-in user only: a socket with mode 0600, checked against the
caller's user id, on the Mac; a pipe with an access list for that user, refusing remote clients,
on Windows. Nothing listens on a network port, and no token ever leaves the deck. An agent's
client asks you before a tool runs; the deck decides whether the command may run at all, by the
rules its buttons follow. Opening links, settings, the deck's layout and quitting are not
something an agent can ask for.
