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
- **Settings as sections, list and form** — three columns, one item edited at a time, forms
  built by `FormLayout` so they stretch with the window instead of leaving dead space.

- **DDEV projects** — one card each, fed by a single `ddev list` for the whole deck, with PHP
  and database versions read from the checkout, paused treated as its own state, and a global
  power off in the menu. Shipped as 0.2.

- **Plain projects** — a card for anything with a folder and a command: the folder is read for
  a suggestion when the project is added, a command that holds its process is started detached
  with a log and a pid, and the health URL decides whether it is running. Shipped as 0.3.
- **The Docker gate** — one probe for the whole deck, and cards that need containers say
  "Docker is not running" and offer to start it rather than a Start that cannot work.
- **The card redesign** — one focal point per card: the state at 20 points, the pill and the
  footer gone, chips wrapped into one block, quieter controls with icons, the vendors' real
  logos parsed from their own SVGs, a card 352 points wide so `Terminal` fits, and glass that
  is glass again rather than grey paint. Three directions were mocked up first; see
  [adr/0009-card-hierarchy.md](adr/0009-card-hierarchy.md).
- **The deck has a canonical order** — Arc, DDEV, then plain projects, alphabetical within each
  — so tidying lays cards out by a rule rather than by the order they were added in.
- **Panel positions belong to a display**, so a deck kept on the laptop screen survives an
  external monitor coming and going.
- **Pull requests waiting for your review** on the same card as your own, from a second search
  in the same request.
- **The branch on a card is a link** to the repository it came from, read from the checkout's
  own `.git/config`.
- **The plain-project settings form**, in the same language: a header with the name and the
  card switch, commands with their captions above them, switches that explain themselves in one
  line instead of four footnotes, the live health answer in the group that asks about it, and
  environment rows tagged in their chips' colours.

## Next

1. **Bundle versions on the project card** — live version per environment, which needs an org
   token and the Developer Center endpoints pinned down against a real organisation.
2. **Mark as read** from the inbox card, so the panel is not read-only.
3. **Resizable panels** — dragging the bottom edge instead of the expander, if the three-row
   default plus expansion turns out not to be enough.
4. **Adding a link to a project by hand** — Test, UAT and Prod are editable, but there is no
   button for an extra one of your own; the model already carries them.
5. **A fixed repository list for the Actions card** — `GitHubSettings.actionsRepositories`
   exists and nothing in settings writes it.
6. **The same treatment for the Arc, DDEV and account forms** — the plain-project form has the
   header, command rows, toggle rows and coloured tags; the other three still have the label
   gutter and the footnotes.
7. **Tailing a plain project's log in place** — the Logs button opens the file in Console,
   which is fine for reading a failure and poor for watching a build.

## Not planned

- WidgetKit widgets in Notification Center. They need Xcode and their own refresh budget; the
  panels already sit on the desktop. Revisit only if Xcode gets installed.
- Windows or Linux. Decided against — see [adr/0001-native-macos-app.md](adr/0001-native-macos-app.md).
