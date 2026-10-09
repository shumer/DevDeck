# Windows card style

How DevDeck cards look on Windows. Status: chosen, implemented by W-3 and W-4 of
[windows-migration.md](windows-migration.md). The reference mock is
[devdeck-windows-proposal.html](poc/windows-ui/devdeck-windows-proposal.html); open it in a
browser next to this file. What the engine sends for each part is in
[engine-protocol.md](engine-protocol.md).

## 1. Principle: the same deck, Windows materials

A DevDeck card on Windows is recognisably the same card as on the Mac, made of what Windows 11
is made of. It is neither a copy of the Mac look, which reads as a ported app, nor a second
design, which would have to be maintained on its own.

| Shared with the Mac, comes from the engine | Windows only, belongs to the shell |
| --- | --- |
| What a card contains, in which order, with which texts | Material: Acrylic |
| The two card sizes and the deck layout | Corner radius 8, drawn by the system |
| Semantic tones: good, attention, alert, personal, neutral | Fonts: Segoe UI Variable and Cascadia Mono |
| Which brand mark a card carries | Icons from Segoe Fluent Icons |
| Which actions exist, which are enabled | Control shapes: 4 px radius, Fluent states |

The rule from the one-engine design still applies: the shell never decides a text, an order, a
tone, a visibility or a timing. This document only says how to draw what the engine sends.

## 2. Window and material

- **Corners.** Ask the system to round the card window: `DWMWA_WINDOW_CORNER_PREFERENCE` with
  `DWMWCP_ROUND`. The radius is the Windows 11 standard, 8 px, for both card sizes. The shell
  draws no corner of its own, so there are no square artifacts at the edges.
- **Dark frame.** `DWMWA_USE_IMMERSIVE_DARK_MODE` on.
- **Acrylic.** `DWMWA_SYSTEMBACKDROP_TYPE` with `DWMSBT_TRANSIENTWINDOW`, available from Windows 11
  22H2 (build 22621). Verify on the real machine how a borderless WPF window has to be set up for
  the backdrop to show (extended frame, transparent client background); the WPF
  `AllowsTransparency` route does not get a system backdrop.
- **Tint over the backdrop.** A layer of `#28282C` at 66% opacity on top of the Acrylic, so cards
  agree with each other over a busy wallpaper. This is the same job the 30% scrim does on the Mac.
- **Edge.** 1 px stroke, white at 7.5%. A 1 px highlight along the top edge, white at 12% fading
  to transparent at both ends.
- **Shadow.** The system shadow of a rounded window. No custom shadow.
- **Without Acrylic** (transparency effects off): solid `#2B2B2F`. Windows 10 is not supported,
  see [adr/0024](adr/0024-one-engine-two-shells.md).
  Everything else stays the same.

## 3. Sizes

All sizes in device-independent pixels; the shell scales them with the monitor.

| Element | Value |
| --- | --- |
| Card width | 352 |
| Card padding | 14 top and bottom, 16 left and right |
| Gap between cards | 12, applied by the engine's layout |
| Collapsed card height | 44 |
| Header row height | 20 |
| List row height | 30 |
| Chip height | 24 |
| Button height | 32, square icon button 36 wide |
| Icon button in the header | 24 square, 14 icon |
| Control radius | 4 for buttons and chips, 3 for small key chips |

## 4. Typography

Sans: **Segoe UI Variable Text**, falling back to Segoe UI. Mono: **Cascadia Mono**, falling back
to Consolas. Cascadia Mono is under the SIL Open Font License and may be bundled if the machine
does not have it.

| Text | Font | Size | Weight | Colour |
| --- | --- | --- | --- | --- |
| Card eyebrow, upper case, letter spacing 0.07 em | Sans | 11 | Semibold | secondary |
| Time in the header | Mono | 11 | Regular | tertiary |
| Hero number | Sans | 30 | Semibold | primary |
| Hero unit | Sans | 14 | Regular | secondary |
| Hero badge | Sans | 12 | Semibold | its tone |
| Project state | Sans | 22 | Semibold | primary, secondary when stopped |
| pid, command, status code, ticket key | Mono | 11 | Regular | tertiary, key secondary |
| Branch | Mono | 12 | Regular | info |
| List row title | Sans | 13 | Regular | primary |
| Meta line, chips, expander | Sans | 12 | Regular | secondary, chips primary |
| Buttons | Sans | 13 | Semibold | primary or the action's tone |
| Footer | Sans | 12 | Regular | tertiary |

The eyebrow is the DevDeck identity and stays upper case on Windows, as on the Mac.

## 5. Colour tokens

Text on the dark card:

| Token | Value |
| --- | --- |
| primary | white at 95% |
| secondary | white at 66% |
| tertiary | white at 42% |

Tones are the deck's own, exactly as `DeckTheme` defines them on the Mac. The engine sends the
tone; the shell maps it here and nowhere else.

| Engine tone | Colour | Used for |
| --- | --- | --- |
| `good` | `#70C799` | running, ready, Start |
| `attention` | `#F0C26B` | needs attention, review waiting |
| `alert` | `#E88484` | blocked, failed, Stop |
| `personal` | `#A99BE0` | addressed to you: a mention, a review request |
| `neutral` | tertiary text | stopped, disabled, nothing to say |

Two colours are not tones, because they never change with state: branches and links are
`#7FAEDD`, environment chips are `#A99BE0`. The part says which it is.

Tinted surfaces use the tone at low opacity: badge and tinted button background at 12%, tinted
button stroke at 27%.

Controls:

| State | Fill | Stroke |
| --- | --- | --- |
| rest | white at 6% | white at 9%, bottom edge 5% |
| hover | white at 9% | unchanged |
| pressed | white at 4% | unchanged, text at 80% |
| disabled | transparent | white at 9%, text tertiary |
| keyboard focus | unchanged | Fluent focus visual: 2 px white outer ring, 1 px dark inner ring |

## 6. Components

Measurements follow the reference mock; where this table and the mock disagree, the mock wins and
this file gets corrected.

**Header.** Brand mark 16, 8 gap, eyebrow, flexible space, header toggles (log, phone) as 24 px
icon buttons, time. The eyebrow is truncated in the middle before anything else gives way.

**List card hero.** Number and unit on one baseline, badge on the right. Under it a 3 px health
bar made of segments with 2 px gaps, one segment per state the engine reports, in that state's
tone.

**List rows.** 7 px dot in the row's tone, optional key chip (mono, 3 px radius, control fill),
optional glyph (review eye in attention), title with an ellipsis, status code on the right. Rows are
separated by a 1 px line of white at 5%. The whole row is the click target, with the control
hover fill.

**Expander and footer.** Centred `Show N more` with a chevron, then the footer line.

**Project hero.** 9 px dot in the state's tone, state text, and on the right the aside the engine
sends (pid, container count) in mono.

**Branch row.** Branch icon 13, branch name in mono info, and an open icon 11 in tertiary when
the engine marks the branch as a link.

**Meta row.** Leading text in secondary, trailing command summary in mono tertiary, truncated in
the middle.

**Chips.** Link chips with an optional 12 px icon; a disabled chip has no fill and tertiary text.
The **place chip** says where the project runs (`WSL · Ubuntu-24.04`, `Windows`), with a dashed
stroke and no fill, because it is information and not a link. Its text comes from the engine.

**Actions.** One primary action that takes the remaining width and carries its tone (Start is
good, Stop is alert), Restart with text, then square icon buttons for folder and terminal. There is no
busy button: a project in the middle of a command says so in its hero, with the line the command
just printed in the meta row, and the engine disables the buttons that cannot be pressed, as on
the Mac.

**Collapsed card.** One 44 px row: mark, dot, name, and the single action the engine offers as a
28 px square icon button.

**Engine stopped.** The engine supplies the failure models; the shell draws them like any other
card. Nothing in the shell writes its own error text.

## 7. Icons

The engine sends semantic glyph ids, never platform icon names. The Windows shell maps them to
**Segoe Fluent Icons**. Take the code points
from Microsoft's published list for that font and keep the mapping in one table in the shell.

| Glyph id | Segoe Fluent Icons glyph |
| --- | --- |
| `start` | Play |
| `stop` | PowerButton |
| `restart` | Refresh |
| `folder` | Folder |
| `terminal` | CommandPrompt |
| `log` | List |
| `phone` | QR code, or Phone if the font has no QR glyph |
| `open` | OpenInNewWindow |
| `review` | View |
| `expand` | ChevronDown |
| `collapse` | ChevronUp |
| `branch` | no good Fluent glyph: use the vector from the reference mock |

## 8. Brand marks

The Mac already draws the marks from vector paths in `Sources/DevDeckUI/BrandMark.swift`:
`github`, `gitlab`, `node`, `docker`, `next`, `nest`, `bun`, `ddev`. Export those paths once to a
shared resource and draw them from it on Windows, so both platforms show the same marks. `arc`,
`make` and `project` are drawn as SwiftUI shapes in `CardGlyph.swift`; export them as paths in
the same step. The engine names the mark; the shell never chooses one.

## 9. Light theme

Not in the first version. The Mac deck is always dark, and the Windows deck starts the same way.
A light theme is a separate decision with its own tone values checked for contrast, after the
dark one has shipped.

## 10. Contract changes this needs

All of it is in the card models since C-1; the field for each is in
[engine-protocol.md](engine-protocol.md#what-the-windows-style-reads):

- semantic glyph ids instead of SF Symbol names: `DeckGlyph`, `DeckMark`;
- the place label for a project (`WSL · Ubuntu-24.04`, `Windows`), localised: `meta.place`;
- the branch, and whether it links to the repository: `meta.branch`, `meta.repository`;
- the trailing command summary for the meta row: `meta.trailing`;
- the header toggles (log, phone) and whether each is on: `header`;
- the health bar segments for list cards: `content.shares`.

They are in the golden transcripts, which pass byte for byte on the Mac and on Windows.

## 11. Acceptance

- Side-by-side screenshots of the three reference cards against the mock at 100%, 150% and 200%
  scaling, on neutral data.
- System rounded corners, no square artifacts; Acrylic on Windows 11, solid fallback with
  transparency effects off.
- Keyboard focus visible on every control.
- Hover, pressed and disabled states for buttons, shown in one screenshot each.
- The C# review rule holds: no text, order, tone, visibility or timing decided in the shell.
