# 0018 - The settings window is built like System Settings

## Status

Accepted.

## Context

The settings window had been reworked twice and was still the thing the owner and a colleague
called inconvenient. It was reviewed twice over, by a visual designer and by a UX reviewer, from
screenshots of every page and from the code. Their reports agreed on the cause.

The window was organised by the app's internal kinds, not by what a person comes to do. General
was seven groups and three screens long, with Start at login two scrolls down. Notifications
lived in General and again at the bottom of every account form. The built-in cards could only be
switched from the menu-bar menu, whose item was nonetheless called "All cards and settings".
Every sidebar row wore a green dot meaning "enabled", while green means "running" everywhere
else in the app.

The forms explained themselves in paragraphs that outweighed their controls, and one group could
mix four row shapes with four different left edges. A button's answer went to one status line at
the bottom of the form, so Detect at the top seemed to do nothing and any edit overwrote a token's
verdict with "Saved.". The live health row joined the address now in the field to the answer for
the old one. The form was rebuilt on every resize and when a check came back, which threw away
whatever field had focus. And a card had no path to its own settings.

Three directions were drawn at the real window size: System Settings style, an inspector with
right-aligned labels and no boxes, and a dark window matching the deck. The owner chose the first,
with the fixes both reviews called for regardless of direction.

## Decision

**Four pages, then accounts, then projects.** General, Deck, Cards and Notifications each fit the
window. Accounts of both services share a heading and projects of every kind share another,
alphabetical, with the mark their card wears. A dot appears only when it means something.

**One form builder with four row shapes**, `SettingsForm`, replacing `FormLayout`'s seven:
a setting with a trailing control, a labelled field row, a status row and a link row. Switches
instead of checkboxes. One line of explanation under a group at most; anything longer behind a
help button. Rarely touched fields under a disclosure per thing, remembered for the session.

**A fixed form column.** 544 points at the default 820-point window, left in place when the
window is wider. A form that stretched had to be rebuilt on resize, and rebuilding is what lost
the focused field. The window remembers its size.

**Answers go where the question was asked.** A check updates its own status row in place, a
button's answer is a popover at that button, and nothing says "Saved.". The form is rebuilt only
for a change of shape, after the edit in progress has been ended.

**An answer is shown only next to the address it answered for**, `CheckSummary` in Core under
tests, and a change of address, folder or command starts a new check.

**Settings for This Card** on every card, through `CardModule.settingsTarget`.

## Rejected

- **The inspector style.** Densest, and best for long URLs and commands, but pre-Big Sur in look,
  and it kept checkboxes and paragraph footnotes as the norm.
- **The dark, deck-matched window.** Most of a product's look, but every control drawn by hand,
  light mode ignored, and the most fragile to maintain without Xcode.
- **One "Add Project" that detects the kind.** The UX review proposed it. Arc has no reliable
  marker in a folder, so the three kinds stay three entries in the `+` menu for now.
- **An NSOutlineView sidebar.** The keyboard and VoiceOver work it would bring were added to the
  existing list directly, at a fraction of the change.

## Consequences

- `FormLayout` and the five `*RowView` forms are gone. `CLAUDE.md` names the four row shapes as
  the only ones, so the next form does not grow a fifth.
- Notification switches moved out of the account forms into the Notifications table. The
  preference keys did not change.
- Launch with `--settings <kind> <id>` opens one account's or project's form, which is also how
  the screenshots for this ADR were taken.
- Not done from the reviews: naming an account after its GitHub login on first verification, and
  an Arc form's check of the organisation against the API.
