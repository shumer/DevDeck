# 0009 — A card has one focal point, and it is the state

Status: accepted, 2026-08-06

## Context

Next to a second internal widget app on the same desktop, DevDeck's cards looked flat and
chunky, and the owner said so. The other app puts a 34-point metric at the top of every card, a
sparkline under it, and dense strips of small facts below; DevDeck put four identical buttons
across the bottom, three lines of 11–12.5 point text above them, and a pill in the corner.

Nothing on a DevDeck card was larger than anything else, so nothing read first. Meanwhile the
information the card exists for — is this project up — was set at 12.5 points between two lines
that looked exactly like it, and the four equal buttons were the loudest thing on screen.

Three directions were mocked up in full before anything was written: dense and
information-first, calm and restrained, and the deck as a status board where the card's own
surface carries the state. The first was chosen.

## Decision

1. **The state is the hero.** A 9-point dot and 20-point semibold text — `running`, `local
   stopped`, `Docker is not running` — where a 12.5-point line used to be. Details that used to
   share that line (`pid 48213`, `mutagen paused`, the container count) move to the end of it in
   10.5-point monospace.
2. **The status pill is gone.** It said, in nine-point caps, exactly what the hero says. Its
   place in the header went to the time of the last check, which used to occupy a whole row at
   the bottom of the card as the least important thing on it.
3. **The rule and the footer are gone too**, replaced by rhythm: the meta block under the hero
   carries the branch, then the framework and folder, then the versions or the command.
4. **The chips wrap into one block** with an upright divider between tooling and environments,
   rather than a row each. That divider says what a whole row of height used to say.
5. **The controls stop shouting.** 26 points instead of 30, 10.5-point labels, and a hairline
   border at 22% instead of 45% — except the one action the card is offering, which is half
   again as wide, tinted, bolder and carries the only coloured border in the row. Every button
   gets an SF Symbol beside its label.
6. **Every card names its kind with a drawn mark** — octocat, arc, tile, hexagon, containers,
   hammer — in front of the title. Monochrome: on these cards colour means state, and six
   tinted logos would compete with the thing that has to read first.

## Consequences

- Cards lost about 50 points of height each while gaining a timestamp and a trailing detail.
  Six of them now fit a laptop screen where five did before.
- Wrapping chips mean the number of lines is no longer fixed, so the panel can no longer add up
  a constant. `CardChipFlow` measures the labels in the real font and breaks lines the same way
  the layout does; the two agreeing is what stops a card clipping its own buttons.
- Rejected from the other app: the sparkline and the `1h|3h|6h` segment. No health history is
  kept, so both would be decoration, and a nine-point segmented control on a panel that sits
  behind other windows is a target nobody can hit. Uptime in the hero was rejected for the same
  kind of reason — the moment a stack started is not something the deck knows after a restart,
  and a card must not invent it.
- Rejected from the status-board direction: colouring the card's own surface by state. On a deck
  that sits on the desktop all day it degenerates into six cards competing for attention, and
  the discipline needed to stop that is not worth the gain over a hero line.
- The three project cards now share `ProjectCardMetrics`, `ProjectChipRow` and `CardActionRow`.
  A layout change that touches only one of them is now a bug rather than an option.
