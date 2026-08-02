# Roadmap

## Done

- **Foundation** — configuration, card catalog and layout, HTTP transport with conditional
  requests, rate-limit parsing, retry and refresh policies, Keychain token storage.
- **GitHub · my pull requests** — one GraphQL query, health derivation, the card, the panel,
  the menu bar count.

## Next

1. **GitHub · inbox** — `GET /notifications`: review requests, mentions, CI failures, with an
   unread badge in the menu bar and "mark read" from the panel. The transport already handles
   `If-Modified-Since` and `X-Poll-Interval`.
2. **Arc XP · organizations** — see the open questions below. Nothing is built until the
   functionality is agreed.
3. **GitHub · Actions** — workflow success rate and running jobs.
4. **Local Fusion stack** — container state, ports, start/stop. Needs a process-running layer
   that does not exist yet, which is why it is last.

## Open questions — Arc XP

The card was sketched as "organisations and sites, each row showing the live bundle version,
click to open PageBuilder". Before any of it is built, these need answers:

- **Scope.** Is the card a launcher that happens to show a version, or a deploy monitor that
  happens to link out? That decides whether rows are sites (a launcher) or environments
  (a monitor).
- **Environments.** How many environments per site are worth a row — sandbox and production
  only, or every one that exists?
- **Deploys.** Should the card only observe, or also act (promote a bundle, restart a
  deploy)? Acting from a desktop panel is a different risk profile and needs a confirmation
  step.
- **Alerting.** Is a finished or failed deploy worth a notification, the way a critical
  threshold is in IRTrafficWidget?
- **API shape.** The admin endpoints for listing bundles and the current live deploy differ
  between organisations and Fusion versions. One organisation's token and one recorded
  response are enough to pin the model down.
- **Tokens.** One token per organisation. Six organisations means six Keychain entries and a
  settings UI that manages a list rather than a single field.

## Not planned

- WidgetKit widgets in Notification Center. They need Xcode and their own refresh budget; the
  panels already sit on the desktop. Revisit only if Xcode gets installed.
- Windows or Linux. Decided against — see [adr/0001-native-macos-app.md](adr/0001-native-macos-app.md).
