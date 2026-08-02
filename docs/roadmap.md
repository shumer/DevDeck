# Roadmap

## Done

- **Foundation** — configuration, card catalog and layout, HTTP transport with conditional
  requests, rate-limit parsing, retry and refresh policies, Keychain token storage.
- **GitHub · my pull requests** — one GraphQL query, health derivation, the card, the panel,
  the menu bar count.
- **GitHub · inbox** — unread notifications with reason chips, priority ordering, the unread
  badge in the menu bar, and the server's own poll interval feeding the refresh loop.
- **GitHub · Actions** — success rate over a window, running and failed runs, one request per
  repository with per-repository caching and per-repository failure tolerance.

- **Several GitHub accounts** — one token per account, all feeding the same cards, with
  partial failures shown in the footer instead of blanking the card.

## Next

1. **Mark as read** from the inbox card, so the panel is not read-only.
3. **Arc XP · organizations** — see the open questions below. Nothing is built until the
   functionality is agreed.
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
