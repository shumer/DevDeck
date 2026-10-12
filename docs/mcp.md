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
| Read only | `what_needs_me`, `cards`, `project_log`. |
| Read and control | The above, plus `start_project`, `stop_project`, `restart_project`, `mark_inbox_read`. |

The change takes effect at once. Below the choice the page shows the line to register the server.

## Registering the server

Claude Code, on the Mac, for every project on this computer:

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

Cursor and other clients take the same executable as a stdio server with no arguments, for
example in `.cursor/mcp.json`:

```json
{ "mcpServers": { "devdeck": { "command": "/Applications/DevDeck.app/Contents/Helpers/DevDeckMCP" } } }
```

## Tools

| Tool | Arguments | Answer |
| --- | --- | --- |
| `what_needs_me` | | The menu's rows, most urgent first: `tier` (`waiting`, `needsFixing`, `stuck`, `goodToKnow`), `title`, `subtitle`, `since`, and the `card`, `url` or inbox `thread` the row is about. |
| `cards` | `card` (optional) | Every card on the deck as `{card, model}`, the model being what the shell draws. |
| `project_log` | `card` | The last lines of the project's log and where they come from. |
| `start_project`, `stop_project`, `restart_project` | `card` | Runs the card's button, waits up to three minutes for it, and returns the card. `done` is false when it is still going. |
| `mark_inbox_read` | `thread` (optional) | Marks that thread read; without one, everything in the inbox that is not addressed to you. Returns `what_needs_me`'s rows. |

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
