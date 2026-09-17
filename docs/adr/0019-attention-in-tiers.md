# 0019 - What needs you is named, in four tiers

## Status

Accepted.

## Context

A colleague sent a screenshot of the menu-bar icon with a red dot and the menu opened on its
first line, greyed out: `1 waiting on you`. They could not tell who was waiting, on what, where,
or what to do. A UX writer and a visual designer reviewed every message the app uses to get
attention, from the code, and agreed on the causes.

- The number named nothing. It added review requests to unread inbox notifications, so one review
  was counted twice, a mention was called "waiting", and a notification kept counting after the
  review was done.
- A disabled menu item is grey, and in a macOS menu grey means "nothing to do here". The most
  urgent line in the menu was the palest, under an update line in full black.
- GitLab was left out of the count entirely, although its banners went out. A GitLab review
  request with a red pipeline was counted as your own blocked work.
- A rejected token looked calm: the failure was a string on a card footer, and a card whose every
  account failed said `Forbidden: Token rejected`. A GitLab card could say `GitHub error 502`.
- Everything that goes wrong on this Mac, a stack that fell over at lunch, a start whose reason the
  next poll wiped, a broken file sync, Docker quitting under running projects, reached neither the
  icon nor the menu.
- `CF` meant failed checks on the GitHub card and a conflict on the GitLab one.

## Decision

**Four tiers, each with its own badge shape.** Waiting on you, a red dot. Needs fixing, a dot in
the bar's ink. Your work is stuck, a ring. Good to know, no badge. The most urgent wins. Shape as
well as colour, so the states read without colour vision and on a tinted bar. Needs fixing sits
above stuck work in the menu, because it is usually one click away and stuck work waits on CI.

**The menu names the things themselves.** One native row per thing under a section header per
tier: a title that says what happened to what, a subtitle with where and who, the age as a badge,
and a click that goes there. Three rows a tier, the rest in a submenu. ⌥ gives Dismiss for what
cannot clear itself and Mark as Read for an inbox row. With nothing to say, "Nothing needs you"
and when the deck last checked.

**One model under all of it.** `AttentionItem` and `AttentionDigest` in Core, one pure builder per
source, and `DeckAttention` joining them. The icon, the tooltip, the menu and the banners are
drawn from the same facts. A thing is counted once: a review and its notification share a row.

**The deck remembers what a card stops saying.** `ProjectWatch` notes that a project was running
and nobody pressed Stop, why a start failed, since when a health check has been silent. Nothing is
reported about the state a launch found. A project that went down with Docker is one "Start
Docker" row. Up but silent is said after two minutes, a network error becomes something to fix
after fifteen, and commits only on this Mac are worth a row after three days, never a badge.

**Errors say who, what and the next step.** `AccountFailure` carries its kind, and a card whose
every account failed carries them whole in `APIError.accounts`.

**Banners follow the same words.** A title that says what happened, a subtitle for where, a body
for which thing and what a click does, the source's own mark, a sound only for a person waiting
on you, and a summary that names the first two and opens the menu.

**One code, one meaning, on both cards.** `MC` merge conflict, `CF` checks or pipeline failed,
`CP` running, `RV` on GitLab too, and a conflict named before a failed check.

## Rejected

- **A number on the icon.** It does not fit an 18-point slot without covering the letters, and
  the count is in the menu and the tooltip where it can say what it counts.
- **A custom view per menu row**, for a two-line layout. It loses the native highlight, keyboard
  navigation, ⌥ alternates and VoiceOver, and has to be matched to the menu's vibrancy by hand.
  Section headers, subtitles and badges are native from macOS 14 and 14.4.
- **Snooze on banners.** Useful, and it needs state that survives a restart and a rule for how it
  interacts with "nothing on the first pass". Left for when somebody asks.
- **Asking GitHub which organisations a token cannot see.** `/user/orgs` answers differently for
  classic and fine-grained tokens. A token refused outright is reported; a silently narrower one
  is still the smoke test's job.

## Consequences

- The pull request query asks for the author, who requested your review and when, and whether the
  branch merges, all within the `repo` scope. Asking for a team's name needs `read:org` and failed
  the whole query for a token without it, which is why a team request is told apart by its type
  name alone.
- The Actions card asks each watched repository for its default branch once, cached with an ETag,
  so a red run on a feature branch is left to its pull request.
- Work in flight runs one more `git log` for a checkout with unpushed work, and none for a clean
  one.
- The Notifications page grew a Failed runs column, a Projects table and New versions.
- A row about a project raises the deck the way a tap of the shortcut does. Somebody who came
  from the menu does not know the shortcut is the way back, and a colleague was left with a
  dimmed screen, so a deck raised this way also goes down on a click outside the cards or Esc.
- `open -a DevDeck --args --menu sample` opens the menu with made-up rows of every tier, for judging
  its layout at real size.
