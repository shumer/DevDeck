# 0010 - The deck is quieter than it was legible

## Status

Accepted. Amends [0009-card-hierarchy.md](0009-card-hierarchy.md), which stands otherwise.

## Context

0009 fixed the layout: one focal point per card, chips wrapped into a block, real vendor marks,
a control row measured from its own labels. Six cards built that way sat on the desktop for a
few weeks, and the complaint that came back was not about any one card. Each is fine on its own.
The wall of them is tiring to sit beside for a working day.

Three things were doing it, and none of them is a layout problem:

- **Colour was spent on structure rather than on meaning.** Every chip carried its own hue as a
  14% fill and lettered itself in that hue at full strength, so a card with two tools and three
  environments put five saturated pills in one row. Multiplied by six cards, the deck read as a
  paint chart, and the state dot - the one thing colour is actually for here - had to compete
  with it.
- **The palette was fully saturated.** 0009 took the three state colours from the sibling widget
  to the digit, which was right about them agreeing and wrong about the level: that widget shows
  one card, this one shows six.
- **The contrast range was too wide at both ends.** The timestamp sat at 38% white on glass that
  changes with the wallpaper, while the card title - the line you already know by heart - was
  bold caps at 90%, the loudest text on a card whose point is the state.

Two directions were mocked up at true scale before anything was written. The other one moved the
state to a 3-point rail down the card's edge and deleted the hero row, which buys about 30 points
of height per card and re-opens 0009's rejection of colouring the card surface by state. It was
not taken. This one keeps the skeleton and changes only the ink.

## Decision

Keep the layout from 0009. Change the palette, the weights and the amount of ink:

1. **Colour leaves the chips.** One neutral 6% white fill for every chip, and the hue survives
   only in the lettering, mixed 55/45 back towards the text colour (`DeckTheme.chipInk`). Same
   type size, same widths, so nothing rewraps. The only saturated things left on a card are the
   state dot and the one action being offered.
2. **The palette is muted about 20%.** Green 92,219,153 becomes 112,199,153; amber 255,204,71
   becomes 240,194,107; red 255,97,97 becomes 232,132,132; violet and blue likewise.
3. **The range narrows from both ends.** Timestamp 38% to 50%, secondary text 68% to 78%, mono
   details 55% to 66%; card title 90% bold caps at 11 points to 62% semibold at 10.5, state word
   from weight 600 at 80% to weight 500 at 76%, its halo from 20% to 14%.
4. **Outlines come off everything that is not the offer.** Quiet buttons lose their 22% hairline
   and keep a 7% fill, 28 points tall with a 9-point radius; only the prominent action keeps a
   border, at 36% of its tint. Row rules go from 10% to 6%. The status pill stops being a
   bordered capsule in small caps and becomes plain tinted text.
5. **Grouping by space rather than by lines.** Chips move 1 point closer to the meta they belong
   to and the button row moves 3 points further away, so a card reads as two blocks instead of
   five evenly spaced stripes.

## Consequences

- A card is about 8 points taller: the chip line went 20 to 22, the button row 26 to 28, and the
  spacing changes net out to +2. `ProjectCardMetrics` already computes this, so nothing else had
  to be told.
- The quiet button label stays at 10.5 points rather than going to 11 with the rest of the pass.
  Four labels at 11 need 307 points and the row has 303, so every button would shrink in
  proportion and lose the uniform padding the card's width was chosen to give them. 0009 set that
  width to stop `Terminal` touching its own edge, and half a point of type is not worth undoing
  it.
- The pull-request count is no longer green or red. A number that changes colour when something
  is blocked says the same thing the words beside it already say, and it was the largest coloured
  object on the deck.
- `DeckTheme.blend` exists because `SwiftUI.Color.mix(with:by:)` needs macOS 15 and this app runs
  further back than that.
- The state colours are no longer the sibling widget's exact values, which 0009 made a point of.
  That decision was about the two decks agreeing, and they still do: it is the same three hues,
  one step calmer, and the widget showing a single card can afford to be the louder of the two.
