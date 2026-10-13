# 0036. Agent access: one engine, a local endpoint, three settings

Date: 2026-10-12

## Status

Accepted.

## Context

A coding agent in a terminal (Claude Code, Codex, Cursor) is asked "what is waiting on me", "is
the backend up", "start it and show me the errors". To answer it needs a GitHub token, the list of
projects, how each one starts and where its log is. The deck already has all of that, already
words it, and already knows which projects it may stop. The roadmap carried an MCP server as the
way to hand that over, read-only first.

Three questions shaped it. Where the answers come from: a second engine would poll GitHub twice
and read the tokens twice, so it has to be the running deck. Who may ask: an agent can read
everything on the deck, so nobody may by default, and only the person signed in. What it may do:
reading and acting are different promises, and acting has to follow the rules the buttons follow.

## Decision

- **A setting with three values**, `agentAccess` in the preferences: **Off** (the default),
  **Read only**, **Read and control**. It sits on the General page on both platforms, in the
  deck's words, and takes effect at once.
- **The running deck opens a local endpoint** while the setting is not Off and closes it when it
  is: a Unix socket in Application Support on the Mac, mode 0600 and checked against the caller's
  user id on every connection; a named pipe on Windows that refuses remote clients and carries an
  access list naming the current user alone. One line of JSON each way per connection. Nothing
  listens on a network port.
- **The engine answers**, in `DeckAgents`: `hello` (the setting and the version), `attention`
  (the menu's rows), `cards` (the models the shell draws), `log` (a project's tail as its window
  reads it) and `command`. A command is a `DeckCommand` the cards' own buttons send, run through
  the same `perform`, and only of three kinds: a project's start, stop or restart, and marking
  inbox threads read. Opening things, settings, the deck's layout and quitting stay with the
  person. In Read only a command is refused in the deck's words.
  Amended 2026-10-12: two more requests, `detect` (what a folder says about the project in
  it, the settings window's own probe) and, under control only, `addProject` (a card for a
  folder, read the window's way, with what the agent knows on top: title, start and stop
  command, whether it holds its process or needs Docker, health and site URLs). The case is an
  agent working in a repository that is not on the deck yet. Removing a card stays in Settings.
  Later the same day: a folder's kind is detected, so a Fusion checkout becomes an Arc card
  with the CLI's own start and stop and the organisation the agent names, and a DDEV project a
  DDEV card from `ddev list`; links are filled by label; and `updateProject` edits a card the
  same way. The first agent to add an Arc checkout got a plain card whose empty stop would
  have left ten containers running, which is what a kind is for.
- **`DevDeckMCP` is the MCP server**, a small executable shipped with the app (in
  `Contents/Helpers` on the Mac, beside the shell on Windows). An agent starts it over stdio; it
  asks the endpoint one question per tool call and returns the deck's answer. `tools/list` offers
  the project and inbox tools only while the setting allows control.
- **Confirmation is the client's.** Claude Code and Cursor ask the person before a tool runs.
  The deck does not ask a second time; it decides whether the command may run at all.

## Consequences

- An agent sees exactly what the person sees, worded the same way, and a project the deck did
  not start is not stopped by an agent either: the card says why.
- The deck has to be running for the server to answer. That is the point: one engine.
- On Windows a pipe name is global on the machine. The first instance is created with
  `FILE_FLAG_FIRST_PIPE_INSTANCE`, so a name somebody else took first fails the deck's start
  rather than serving their pipe; the server does not verify the pipe's owner from the client
  side, which is left for later.
- Updating on Windows closes an agent's running server so its file can be replaced; the agent
  starts it again on its next call.
- A command waits up to three minutes for the work it started, which is how long a Fusion start
  can take, and says so when it is still going.

## Alternatives

- **A second engine inside the MCP server.** Rejected: two pollers, two readers of the tokens,
  and two decks that disagree.
- **HTTP on localhost.** Rejected for now: any process of any user can reach a port, and a
  browser page can try. A socket and a pipe are owned by a user.
- **Asking on the deck before each command.** Possible later as a fourth setting; the clients
  already ask, and two prompts for one action teach people to click through both.

## Amendment: the engine registers the server

The page used to show a command line to paste into a terminal, first for Claude Code, then a
second one for Codex. Nobody should have to: the setting is the decision. Turning it on now runs
the agents' own tools (`claude mcp add --scope user`, `codex mcp add`) for the server executable
the host names, turning it off runs their `remove`, and a launch with the setting already on
checks each list (`claude mcp get`, `codex mcp get`) and repairs a missing entry, which is also
how a moved executable after an upgrade is caught. The tools are run through the deck's command
runner, in the person's home folder, with the same shell and `PATH` a project's start command
gets. An agent whose tool is not on this computer is reported as not installed, with the line to
run by hand later; a tool that answers with an error is reported with its first line. Which agents
are known is the engine's list (`AgentClient.all`); the shells draw one row per agent from the
`agentClients` answer, which the engine also pushes unasked as the work finishes. Editing the
agents' configuration files directly was rejected: the tools are the supported way in, and their
formats have changed before.

## Amendment: what changed, and open

Two tools were added. `what_changed` answers what is new since the agent last looked: rows that
appeared, rows that went, projects whose state moved. The memory of "last looked" lives in the
MCP server process, which is one agent's session, and not in the deck: the deck has no notion of
who asked, and two agents asking must not spoil each other's answer. `open` puts a page or a
project's place on the person's screen; it takes control, because the screen is the person's,
and a URL opens in the browser of the account whose host it is, the way a row's link would, so an
agent that names a pull request does not open it as the wrong person.

## Amendment: who pressed, waiting, and time

A command carries the client's name, and the watch records a press from an agent as the agent's:
a start the person did not do is the kind of thing worth a row, and it is told apart from one's
own by being said at all. The row lasts until the person presses a button on that card, which is
their own doing again, or dismisses it. `wait_for` lives in the server process and polls the deck;
the deck has no notion of waiting, and an agent that wants to wait is one process watching one
card. The run log is the deck's, kept in preferences across launches, because time per project is
a question about days, not about one session; it is written when a session opens or closes and
once a minute while one is open, so a quit ends a session where the deck last looked.
