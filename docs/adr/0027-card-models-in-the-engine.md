# 0027 - Cards are models the engine builds, and views only draw them

## Status

Accepted, 2026-10-09. Part of [0024](0024-one-engine-two-shells.md), after
[0025](0025-the-deck-runtime-on-the-main-actor.md) moved the deck's state into the engine.

## Context

After the runtime moved, the SwiftUI cards still decided what to show. The pull requests card
picked the pill's words and colour, wrote the footer, chose when a row names its account and
which rows get an eye; the project cards chose Start or Stop, what the state line says while
Docker is down, which chips are dimmed; the modules decided where a dashboard is and which
browser a link opens in. Windows would have had to repeat all of it in C#, and two copies of
those rules would drift, as two copies of one card's layout had already drifted once here.

## Decision

Every card is a model in `DevDeckEngine/Cards`, built by a pure function from the runtime's
state, the account labels, whether the card is folded or expanded, and the time. A model holds:

- every word, already translated;
- a `DeckTone` (good, attention, alert, neutral, personal) wherever there is a colour, a
  `DeckMark` for a brand and a `DeckGlyph` for an icon, meaning rather than picture;
- the visible rows in order, the expander, the footer, the placeholder and the folded row;
- a `DeckCommand` for every click.

A view draws the model. Turning tones, marks and glyphs into colours, vectors and SF Symbols is
the one thing it decides, in one file. Clicks go to `DeckRuntime.perform(_:)`; what only the
platform can do comes back as a `DeckEffect` (open this URL in this browser, reveal this folder,
open a terminal there, open this setting).

Cards that were one card in two places became one model: pull requests and merge requests share
`ReviewListCardModel`, and the three project cards share `DeckProjectCardModel`.

Models are `Codable`, because they are what the protocol will carry to Windows. The protocol's
own models from the proof of concept stay untouched until C-1 replaces them with these.

## Consequences

- What a card says is tested without drawing anything: `CardModelTests` cover each branch that
  used to sit in a view, in English and Russian.
- Moving the decisions found and fixed two bugs: a double click on the GitLab card opened its
  dashboard in a GitHub account's browser, and the folded Work in flight card was titled in
  English in every language. It also found three Docker strings nothing showed.
- A card's height is still computed in `DevDeckUI`, from the model only, until placement moves
  in M-5: it depends on the Mac's fonts, which the engine cannot measure.
- The menu-bar tooltip and the menu still word themselves on the Mac. They move in M-4.

## Alternatives

- **One generic card model for every card**, as the proof of concept had. It fit two cards and
  would have needed a field for every exception of the other six; typed models say what each
  card is.
- **Colours in the model.** A colour is the shell's: the Windows style uses its own palette, and
  a tone is what both shells agree on.
- **Keeping commands as closures built by the modules.** Closures cannot cross the protocol, and
  they were where the browser and dashboard decisions hid.
