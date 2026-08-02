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

| Card | State |
|---|---|
| GitHub · my pull requests | working |
| GitHub · inbox (notifications) | planned |
| GitHub · Actions | planned |
| Arc XP · organizations and bundles | in design — see [docs/roadmap.md](docs/roadmap.md) |
| Local Fusion stack | planned |

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

### The token

A fine-grained personal access token with read access to **pull requests**, **contents** and
**metadata** is enough. Two things catch people out:

- a fine-grained token must be **approved by each organisation** before it can see anything
  there, and until then the API answers with an empty result rather than an error;
- under SAML SSO, a classic token must be **authorised for each organisation** as well.

`scripts/smoke-test.sh` prints how many organisations the token can actually see, which is
the fastest way to tell "no open pull requests" from "cannot see the organisation".

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
