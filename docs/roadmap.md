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
- **A browser and profile per account**, so a row opens as the identity that owns it, plus
  per-row account chips and click-to-expand cards.

- **Arc XP projects** — one card per project: editable link templates opened in the project's
  own browser, local Fusion stack status from the engine's health URL, and start, stop and
  restart running the Arc CLI in the project folder.
- **Settings with sections** — GitHub accounts, Arc projects and General kept apart in one
  window, and a menu-bar icon that says which app it belongs to.

- **DDEV projects** — one card each, fed by a single `ddev list` for the whole deck, with PHP
  and database versions read from the checkout, paused treated as its own state, and a global
  power off in the menu. Shipped as 0.2.

## Next

1. **Bundle versions on the project card** — live version per environment, which needs an org
   token and the Developer Center endpoints pinned down against a real organisation.
2. **Mark as read** from the inbox card, so the panel is not read-only.
3. **Resizable panels** — dragging the bottom edge instead of the expander, if the three-row
   default plus expansion turns out not to be enough.
4. **Custom links on DDEV cards from the settings screen** — the model carries them, the
   settings row does not offer them yet.

## Not planned

- WidgetKit widgets in Notification Center. They need Xcode and their own refresh budget; the
  panels already sit on the desktop. Revisit only if Xcode gets installed.
- Windows or Linux. Decided against — see [adr/0001-native-macos-app.md](adr/0001-native-macos-app.md).
