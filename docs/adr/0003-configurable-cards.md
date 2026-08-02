# 0003 — Cards are data, and every card can be switched off

Status: accepted, 2026-08-02

## Context

The deck will grow to five or six cards across GitHub, Arc XP and the local stack. Nobody
wants all of them at once: what matters differs by day and by person, and a panel that is
always on screen but never read is worse than no panel.

Hiding also has to be cheap in the other direction — a hidden card must not keep polling an
API against a shared rate-limit budget.

## Decision

- Every card is described once in `CardCatalog`: identifier, title, subtitle, whether it is
  implemented, whether it is on by default.
- User preference lives in `CardLayout`: an ordered list of `(identifier, isEnabled)`,
  persisted as JSON in `UserDefaults`.
- The two are merged on every read. New cards in the catalog are appended with their default
  visibility; identifiers no longer in the catalog are dropped; duplicates collapse to the
  first entry.
- `visibleCards()` filters out anything not implemented, so a half-built card can ship
  disabled behind a flag of one line.
- `DeckController` is told which cards are active and fetches nothing for the rest.

## Consequences

- Adding a card is a descriptor plus a branch in `CardHostView`; no migration, no settings
  screen change.
- Card identifiers are persisted strings and can never be renamed. Removing a card is safe.
- A corrupt or unreadable layout falls back to the catalog defaults rather than leaving the
  user with an empty desktop.
- Ordering is stored but not yet editable from the UI — the menu toggles visibility only.
  Reordering is a settings-window feature when there are enough cards to need it.
