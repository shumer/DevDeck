# DevDeck

Desktop panels for the things a developer checks twenty times a day: open pull requests,
review requests, deploys. Frosted cards that sit on the macOS desktop behind your windows,
plus a menu-bar item with the count.

Native macOS, built from a SwiftPM package with no Xcode required.

```
┌──────────────────────────────────────────┐
│ GITHUB · MY PULL REQUESTS     2 BLOCKED  │
│                                          │
│  7 open                                  │
│  ● feat/composer-block     checks failed │
│  ● fix/pb-image-fill  changes requested  │
│  ● chore/bundle-bump           approved  │
│                                          │
│  3 repos · 2 orgs             20:16:39   │
└──────────────────────────────────────────┘
```

## Status

| Card | State | On by default |
|---|---|---|
| GitHub · my pull requests | working | yes |
| GitHub · inbox (notifications) | working | yes |
| GitHub · Actions | working | no |
| Arc XP · organizations and bundles | in design — see [docs/roadmap.md](docs/roadmap.md) | no |
| Local Fusion stack | planned | no |

The Actions card watches the repositories your open pull requests are in, up to five, unless
`actionsRepositories` says otherwise.

## Quick start

```bash
git clone <this repo> && cd widgets
scripts/seed-token.sh                 # copies a token from env.local into the Keychain
./run-tests.sh                        # offline suite, must be green
scripts/smoke-test.sh                 # one real API call, prints counts
./build.sh                            # builds DevDeck.app and installs it to /Applications
```

Without a token the app opens its settings window on first launch; paste a token there
instead of running `seed-token.sh`. The token is verified against the API before it is
stored, and it only ever lives in the login Keychain.

### Several accounts

One token rarely covers everything: a fine-grained token is approved per organisation, and
some organisations sit behind SAML SSO. **Menu bar → GitHub accounts…** manages a list —
each account has its own label, its own organisations and its own token in the Keychain.

All accounts feed the same cards. Pull requests visible to two accounts are shown once. When
one account fails, the others still render and the card footer says which one is missing;
a card only fails outright when every account fails. With more than one account configured,
every row carries a chip saying which one it came from.

### Links open as the right identity

github.com allows one signed-in identity per browser profile, so "open in the default browser"
is wrong half the time when work and personal accounts are both on the deck. Each account has
an **Open links in** setting: a browser, and for Chrome, Edge, Brave, Vivaldi and Chromium a
profile as well, listed by the names you gave them. Clicking a row then lands in the profile
that is signed in as that account.

The pickers apply the moment you change them — there is a **Test** button beside them that
opens one page so you can see where it lands. Only the token needs an explicit **Verify
token** press, because it is checked against the API before being stored.

Safari has profiles but no way to choose one from outside the app, and Firefox's `-P` depends
on what is already running; both are offered without a profile picker rather than with one
that would not work.

### Seeing everything

Cards show three rows and a **show N more** line. Clicking it grows the panel to show up to
twelve, pushing the panels below it down; clicking again collapses. It is deliberately not
remembered — expanding is a "let me look at this now" gesture, and a deck that comes back tall
the next morning is a surprise.

### The token

A fine-grained personal access token with read access to **pull requests**, **contents** and
**metadata** covers the pull requests card. The inbox card also needs the account-level
**notifications** permission, and the Actions card needs **actions** (read). Three things
catch people out:

- the **notifications** permission sits under the account section rather than the repository
  section, and without it the inbox card shows
  `Forbidden — Resource not accessible by personal access token`;

- a fine-grained token must be **approved by each organisation** before it can see anything
  there, and until then the API answers with an empty result rather than an error;
- under SAML SSO, a classic token must be **authorised for each organisation** as well.

`scripts/smoke-test.sh` prints how many organisations the token can actually see, which is
the fastest way to tell "no open pull requests" from "cannot see the organisation".

### Status codes

Rows end in a two-character code so the width goes to the title. Hovering a row spells it out.

| | | | |
|---|---|---|---|
| `CF` | checks failed | `CP` | checks running |
| `CR` | changes requested | `DR` | draft |
| `AP` | approved | `WR` | waiting for review |
| `T3` | three unresolved threads | | |

The coloured dot says the same thing at a glance: red is blocked, amber needs someone, green
is done.

## Using it

Everything lives in the menu-bar menu:

- **Cards** — show or hide each card; a hidden card is not fetched at all.
- **Keep on desktop / Float above windows** — panels behind your windows, or above them.
- **Lock position** — stop dragging once the layout is right.
- **Tidy panels into a column** — close up gaps without resetting where you put them.
- **Start at login**, **Refresh now**, **Settings…**

Drag a panel anywhere; the position is remembered per card. Click a row to open that pull
request, double-click the panel background to open the list on github.com, right-click a
panel for the same menu.

## Documentation

- [docs/architecture.md](docs/architecture.md) — modules, data flow, where to add a card
- [docs/github-api.md](docs/github-api.md) — the GraphQL query, rate limits, token setup
- [docs/development.md](docs/development.md) — toolchain, scripts, definition of done
- [docs/roadmap.md](docs/roadmap.md) — what is next and the open questions on Arc XP
- [docs/adr/](docs/adr/) — why native, why SwiftPM only, why cards are configurable

## Layout

```
Sources/
  DevDeckCore/     configuration, cards, HTTP transport, tokens, refresh policy
  GitHubKit/       GraphQL client, models, pull request service
  DevDeckUI/       SwiftUI cards and the shared visual language
  DevDeckApp/      AppKit shell: panels, menu bar, placement, settings
Tests/
  TestHarness/     tiny test framework and fakes
  DevDeckTests/    the suite (48 tests, offline)
Tools/Smoke/       live API check
```
