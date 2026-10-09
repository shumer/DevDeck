# 0031 - The settings window's operations are the engine's, and its forms stay the Mac's

## Status

Accepted, 2026-10-09. Part of [0024](0024-one-engine-two-shells.md). Leaves the settings layout of
[0018](0018-settings-like-system-settings.md) as it is.

## Context

The settings sections did their work themselves. They wrote the account and project stores and
the token store directly, ran their own checks with services built on the spot (a project's
health with default dependencies rather than the deck's, a DDEV environment of their own), ran
Detect, decided what "test the link" opens and when a token counts as working, and assembled the
sidebar's rows. Some of it disagreed with itself: a GitLab token check never said that a token was
needed, and the same project could get one answer in the settings and another on its card.

Moving the forms too would mean describing every field, label and fold for a Windows shell
whose settings window has not been designed yet.

## Decision

The runtime owns what the window does: the sidebar list (`settingsList()`), adding, saving and
removing accounts and projects, Detect, the health, stack and token checks, and link tests. A
save says whether the edit asks its status line a new question; a token check stores a typed
token only once it works, and both services now say "a token is needed" when there is none
anywhere. Checks run through the runtime's own services, with its runner and files.

The forms, their words and the four pages (General, Deck, Cards, Notifications) stay in
`DevDeckApp`. Folders are chosen and removals confirmed there too, being dialogs. They move when
W-10 has a design for the Windows settings, which will say what a form description has to hold.

## Consequences

- The settings window and the cards ask the same questions the same way.
- What the settings decide is tested without a window, in `SettingsModelTests`.
- The Windows settings window will reuse every operation and write only its forms.

## Alternatives

- **A full form description in the engine now**, field by field. It would be designed against
  the Mac's forms alone, and redesigned once the Windows mock exists.
- **Leaving the sections as they were** until W-10. The checks would keep disagreeing with the
  cards, and Windows would start from operations nobody had tested.
