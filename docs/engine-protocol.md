# Engine protocol, version 2

How a shell in another process talks to the engine. The Windows shell starts
`DevDeckEngineHost.exe` and speaks this over its standard input and output; the Mac app links the
engine and calls `DeckRuntime` directly, so it does not use it. Both end up in the same runtime,
which is why both decks say the same things. The decision is
[adr/0033](adr/0033-protocol-on-the-runtime.md); the code is `Sources/DevDeckEngine/Session`.

## The rule

The shell decides nothing: no text, no order, no tone, no visibility, no timing, nothing about
what to save. It draws what an event says, reports what only it can see (displays, sizes, moves,
windows), and sends back the command it was given when something is clicked. It never builds a
command of its own, with one exception: the name typed into a prompt (see Menus).

## Framing

- One JSON object per line, UTF-8, `\n` at the end. A `\r` before it is tolerated.
- At most 1 MiB per line either way. A longer line is dropped and reported on standard error.
- Standard error is for diagnostics only. It never carries a token, a URL with a token, or a
  path the user did not configure.
- Every intent carries `"protocolVersion": 2` and a non-empty `id`. Events an intent causes
  while it is handled carry its `id`. Events sent later, by the engine's own loops or once
  something an intent started has finished, carry none, except `settings.answered`, which always
  carries the id of its request.
- Every event carries `revision`, counting up from 1 for the session. A gap means the shell
  missed something and should ask to start again.
- Keys are sorted and `/` is not escaped, so the same event is the same bytes on every platform.

## Intents: shell to engine

| `intent` | Fields | When |
| --- | --- | --- |
| `session.start` | `systemLanguage`, `displays` | Once, first. Nothing else is accepted before it. |
| `displays.changed` | `displays` | A monitor came, went, moved or changed its work area. |
| `card.measured` | `card`, `size: [w, h]` | After drawing a card, whenever its height changed. |
| `card.moved` | `card`, `frame` | A panel moved and the shell did not move it. |
| `command` | `command` | Something was clicked: the `command` exactly as an event carried it. |
| `logWindow.changed` | `card`, `isOpen` | A log window opened or closed, by any means. |
| `settings` | `request` | The settings window asks or changes something; see Settings. |
| `update.check` | | The update row's Check button. |
| `update.act` | | The update row's one button: install what is on offer, or check. |
| `update.progress` | `fraction` | The installer's download, 0 to 1. |
| `update.installing` | | Downloaded; being unpacked and put in place. |
| `update.failed` | `reason` | The installer gave up, in its own words. |
| `session.stop` | | The shell is going away. Projects keep running. |

A display is `{"id", "frame", "isPrimary"}`. `id` is the monitor's own identity, stable across
unplugging it. `frame` is its work area, taskbar excluded.

`systemLanguage` is what the system prefers, such as `ru-RU`. The deck uses its own language
setting, and the system's only when the setting says to follow it; a language the deck does not
speak falls back to English.

Any intent the engine cannot use is answered with `intent.rejected` and a `reason`:
`notStarted`, `invalidIntent` (not JSON, wrong version, no id), `invalidDisplays`,
`invalidSize`, `invalidFrame`, `invalidCommand`, `invalidCard`, `invalidRequest`,
`invalidFraction`, `unknownIntent`.

### Coordinates

Every rectangle is `[x, y, width, height]` in the shell's own desktop coordinates, y growing
downward, in the units it draws cards in. The engine only ever compares and offsets them, so
any consistent space works. Mixed scaling across monitors is the shell's to make consistent
before it reports (W-7).

## Events: engine to shell

| `event` | Fields | What to do |
| --- | --- | --- |
| `deck.changed` | `deck` | Whether panels can be dragged (`isLocked`), their layer (`displayMode`: `desktop` behind windows, `floating` above), and the tray status to show if the engine stops (`stoppedStatus`). |
| `panels.changed` | `panels` | Apply each change in order: `open` a panel at `frame`, `place` it at `frame` (size included), or `close` it. Do not report these moves back. |
| `card.changed` | `card`, `model`, `menu`, `stopped` | Draw the card from `model`; `menu` is its right-click menu; `stopped` is the one row to draw instead if the engine stops. |
| `status.changed` | `status` | The tray icon: `tier` picks the icon (absent means calm), `tooltip` and `accessibilityValue` are its words. |
| `menu.changed` | `menu` | The tray menu, ready to show. |
| `log.changed` | `card`, `log` | The lines of an open log window: `lines`, `source` (what is being read), `detail` (why there is nothing). |
| `notify` | `notifications` | Post one banner each. Clicking one sends its `command`. |
| `effect` | `effect` | Something only the platform can do, below. |
| `settings.answered` | `answer` | The answer to a `settings` intent, with its `id`. |
| `update.changed` | `update` | The settings page's update row: `summary` (`tone`, `state`, `detail`), `button`, `isEnabled`. |
| `intent.rejected` | `reason` | The intent was not used. |

A card is `card.changed` only when its model or its menu differs from the last one sent, and
every model is complete: the shell never merges. A panel for a card is opened by
`panels.changed` before or after the card's first model; the shell keeps both and draws when it
has both.

### Effects

`effect.kind` says which; the other fields are the ones that kind needs.

| `kind` | Fields | |
| --- | --- | --- |
| `openURL` | `url`, `browser` | Open in this browser and profile; an empty `browser` is the system default. |
| `openTerminal` | `folder` | A terminal in this folder, spelled the platform's way. |
| `revealFolder` | `folder` | Show this folder. |
| `launchDocker` | | Start Docker Desktop. The cards already say it is starting. |
| `openLogs` / `closeLogs` | `card` | Open or close the card's log window, then report it with `logWindow.changed`. |
| `openSettings` | `page`, `item`, `card` | Open settings, on a page and item when given, or on a card's page. |
| `present` | `card` | Bring the deck up: the card is already on it with its log open. |
| `openMenu` | | Open the tray menu. |
| `installUpdate` | `update` | Download `update.asset` (`size` bytes), check it and install it, reporting with the `update.*` intents. |
| `quit` | | Stop drawing and exit. The engine has stopped its loops. |

### Notifications

`{"id", "source", "title", "subtitle", "body", "isQuiet", "command"}`. `source` picks the mark the
banner carries: `github`, `gitlab`, `arc`, `ddev`, `project`, `docker`, `devdeck`. `isQuiet` means
no sound. Several at once are already summarised by the engine.

### If the engine stops

When the host exits or its pipe breaks, the engine can no longer say anything, so it has said it
already: every panel is drawn as its card's last `stopped` row, folded and with nothing to press,
and the tray shows the last `stoppedStatus`. Both are in the deck's language. The shell restarts
the host and sends `session.start` again; nothing it drew while waiting is kept.

## Commands

A command is a JSON value the shell treats as opaque, for example
`{"toggleExpanded":{"_0":"github.pullRequests"}}`. It appears on every clickable part of a card
model, on menu items and on notifications, and goes back unchanged in a `command` intent. The
full list is `DeckCommand` in `Sources/DevDeckEngine/Cards/DeckCardParts.swift`.

## Menus

The tray menu and a card's menu are lists of entries: `{"item": {"_0": item}}`,
`{"header": {"_0": text}}`, `{"separator": {}}` and `{"submenu": {"_0": item, "_1": [entries]}}`.
An item has `title`, `isEnabled`, `isOn`, `isIndented`, `keyEquivalent`, and optionally
`subtitle`, `badge`, `help` (the tooltip), `image` (`calm`, `more`, or `attention` with the
source's mark), `command`, and:

- `alternate`: another title and command shown while Alt is held;
- `confirmation`: ask first, in these words, and send the command only on confirm;
- `prompt`: ask for a name in these words, then send the command with the typed name as its
  `name`, as in `{"saveArrangement":{"name":"Desk"}}`. This is the one command the shell fills
  in.

## Card models

`model` holds one key named after the kind of card: `reviewList` (pull requests, merge requests),
`inbox`, `actions`, `workInFlight`, `project` (Arc, DDEV and plain projects). Their fields are the
Swift structs of the same names in `Sources/DevDeckEngine/Cards`; the golden transcripts in
`Tests/EngineTests/Golden` show every one of them filled in, in English and Russian.

Every card has `collapsed`, the one-row form, and `isCollapsed`, which of the two to draw.

### What the Windows style reads

[windows-style.md](windows-style.md) section 10, field by field:

| Style needs | Field |
| --- | --- |
| Semantic icons | `glyph` on actions and icons (`DeckGlyph`), `mark` on cards (`DeckMark`) |
| Tones | `tone` (`DeckTone`): `good`, `attention`, `alert`, `personal`, `neutral` |
| Where a project runs | `project.meta.place`: `Windows`, `WSL · Ubuntu-24.04`, absent on the Mac |
| Branch with its link | `project.meta.branch`, `project.meta.repository` (a command, absent when not a link) |
| Command summary | `project.meta.trailing` |
| Header toggles | `project.header`: `logIsOn`, `log`, `phoneURL` (absent when nothing is served) |
| Health strip | `reviewList.content.shares`: a tone and a count per segment |
| Why Stop cannot reach a project | `project.hero.note` and the disabled actions |

## Settings

The settings window sends `{"intent": "settings", "request": ...}` and gets one
`settings.answered` with the same `id`. Requests may overlap; each answer comes when it is ready,
so a slow check does not hold up the list. The full list is `DeckSettingsRequest` and
`DeckSettingsAnswer` in `Sources/DevDeckEngine/Settings/DeckSettingsWire.swift`.

| Request | Answer |
| --- | --- |
| `list` | `list`: the sidebar, accounts and projects, each with its words, mark and tone |
| `preferences`, `setPreferences` | `preferences`: the deck-wide settings as they now are |
| `localProject`, `arcProject`, `ddevProject`, `githubAccount`, `gitlabAccount` by `id` | the record a form edits, as stored |
| `add...` | `added` with the new id |
| `save...` | `saved`, with `checkAgain` when the form's status line has a new question |
| `remove...`, `restructureArcProject` | `done` |
| `detect` | `detection`: a suggestion for the form, and the note under the button |
| `checkLocalProject`, `checkArcStack` | `check`: the form's status line for the record as sent |
| `test...Link` | `note`: words when there is nothing to open; otherwise the page opens as an `openURL` effect |
| `ddevCandidates`, `ddevFolderNote` | `ddevCandidates`, `note` |
| `checkGitHubToken`, `checkGitLabToken` | `token`: `works` or `refused`, in words |

A token travels once, typed, inside a check request. One that works is stored by the engine in
the system's credential store and never sent back; an empty one checks the stored token. A check
answer belongs to the record in the request: a form that changed since asks again.

A request that changes the deck (anything that adds, saves or removes, a token check, new
preferences) is followed by what it changed: panels, cards, the menu, the deck's lock, every
card in a new language.

The summon shortcut is not in the preferences yet: the Mac stores a Mac key code, and the
Windows shortcut is decided with W-9.

## The host

`DevDeckEngineHost` builds one runtime and one session and pipes standard input and output
through it. It takes no arguments. On Windows everything the deck remembers is the engine's:
preferences, accounts and projects in `%LOCALAPPDATA%\DevDeck\preferences.json`, tokens in
Credential Manager, a project in a Windows folder started through `DevDeckProcessHost` and one in
a WSL folder (`\\wsl.localhost\<distribution>\...`) through that distribution's own client.
When standard input closes it stops its loops and exits; the projects keep running (ADR 0023).

Not wired yet, each with its task in [windows-migration.md](windows-migration.md): starting Docker
Desktop and the address a phone can reach (W-11, W-12), and an installer to hand updates to
(W-17), so the update row says there is nothing to replace.

## Testing

`swift run DevDeckEngineTests` replays `session-en` and `session-ru`, written as a shell would
write them, and compares every event byte for byte with `Tests/EngineTests/Golden`. The same
files pass on Windows. A change that alters the protocol regenerates them on purpose (see
[development.md](development.md#golden-transcripts)) and the diff is read.
