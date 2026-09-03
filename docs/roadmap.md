# Roadmap

## Done

- **Foundation** - configuration, card catalog and layout, HTTP transport with conditional
  requests, rate-limit parsing, retry and refresh policies, Keychain token storage.
- **GitHub · my pull requests** - one GraphQL query, health derivation, the card, the panel,
  the menu bar count.
- **GitHub · inbox** - unread notifications with reason chips, priority ordering, the unread
  badge in the menu bar, and the server's own poll interval feeding the refresh loop.
- **GitHub · Actions** - success rate over a window, running and failed runs, one request per
  repository with per-repository caching and per-repository failure tolerance.

- **Several GitHub accounts** - one token per account, all feeding the same cards, with
  partial failures shown in the footer instead of blanking the card.
- **A browser and profile per account**, so a row opens as the identity that owns it, plus
  per-row account chips and click-to-expand cards.

- **Arc XP projects** - one card per project: editable link templates opened in the project's
  own browser, local Fusion stack status from the engine's health URL, and start, stop and
  restart running the Arc CLI in the project folder.
- **Settings with sections** - GitHub accounts, Arc projects and General kept apart in one
  window, and a menu-bar icon that says which app it belongs to.
- **Settings as one list and a form** - grouped by kind with General pinned at the top, one item
  edited at a time, forms
  built by `FormLayout` so they stretch with the window instead of leaving dead space.

- **DDEV projects** - one card each, fed by a single `ddev list` for the whole deck, with PHP
  and database versions read from the checkout, paused treated as its own state, and a global
  power off in the menu. Shipped as 0.2.

- **Plain projects** - a card for anything with a folder and a command: the folder is read for
  a suggestion when the project is added, a command that holds its process is started detached
  with a log and a pid, and the health URL decides whether it is running. Shipped as 0.3.
- **The Docker gate** - one probe for the whole deck, and cards that need containers say
  "Docker is not running" and offer to start it rather than a Start that cannot work.
- **The card redesign** - one focal point per card: the state at 17 points, the pill and the
  footer gone, chips wrapped into one block, quieter controls with icons, the vendors' real
  logos parsed from their own SVGs, a card 352 points wide so `Terminal` fits, and glass that
  is glass again rather than grey paint. Three directions were mocked up first; see
  [adr/0009-card-hierarchy.md](adr/0009-card-hierarchy.md).
- **Commands find version-managed tools** - the `PATH` is resolved from an interactive shell
  once per launch, so `npx` and `pnpm` work from a card and not only from a terminal.
- **Buttons act on the first click**, and a stop that did not take effect says so instead of
  being repainted green by the next poll.
- **The phone and the work in flight** - the running site as a QR code addressed to this Mac on
  the wifi, offered only while the project is up; and one card for every checkout at once, showing
  what is uncommitted, unpushed or behind. Shipped as 0.8.
- **The deck's own housekeeping** - the refresh interval and the Actions repository list are
  controls rather than model fields, a right-click on a panel is about that card, project kinds
  are submenus, powering off every DDEV project asks first, the four settings forms all open the
  same way, a project can carry a link of its own, an inbox row can be marked read, and the deck
  can be saved as a named arrangement and put back. Shipped as 0.7.
- **The Keychain stops asking** - tokens are stored with an access list that a rebuild does not
  invalidate, so an update no longer costs one password prompt per token.
- **A release builds itself** - publishing a release on GitHub runs the suite, builds the bundle
  and attaches it to the tag, and every push runs the tests. Shipped as 0.6.
- **Notifications** - a banner when somebody asks for your review, and optionally when something
  of yours is blocked, carrying the service's own mark, switched on per account and per kind, with
  nothing announced twice or on the first pass after a launch.
- **GitLab merge requests** - a card of its own, yours and the ones waiting on your review, from
  one GraphQL request per instance, with the host on the account because GitLab is routinely
  self-hosted. See [adr/0013-gitlab.md](adr/0013-gitlab.md).
- **Both icons, drawn in code** - an application icon at last, one card carrying the hero row,
  rendered at all ten sizes by `AppIconExport` and packed by `build.sh`; and a menu-bar icon with
  three states instead of a red glyph that meant three different things at once. Shipped as 0.5.
- **The menu is for doing, Settings is for deciding** - placement, locking, packing, summoning
  and start-at-login moved out of the menu-bar menu into Settings under General. Shipped as 0.4,
  together with the log tray, the collapsed card, summoning and the placement fixes.
- **The deck stops moving cards nobody asked it to move** - restarting reproduces a layout
  exactly, and closing up a column is a switch rather than a habit. See
  [adr/0012-automatic-movement.md](adr/0012-automatic-movement.md).
- **Summoning** - hold the shortcut and the panels rise over everything, let go and they drop
  back, with the screen dimmed while they are up and the combination set in Settings.
- **A card has two sizes** - whole, or one 44-point row with the mark, the state dot, the name
  and the one action the state implies, kept per card. See [adr/0011-two-sizes.md](adr/0011-two-sizes.md).
- **The log tray** - the last six lines a project is writing, on the card itself, for Arc, DDEV
  and plain projects alike, read only while the tray is open.
- **A running command narrates itself** - its newest line sits on the card while it works, and a
  start that failed keeps the reason it printed even when the command exited zero.
- **The deck has a canonical order** - Arc, DDEV, then plain projects, alphabetical within each
  - so tidying lays cards out by a rule rather than by the order they were added in.
- **Panel positions belong to a display**, so a deck kept on the laptop screen survives an
  external monitor coming and going.
- **Arranging the deck away from home sticks** - tidying or dragging while the display a card
  belongs to is unplugged is saved against the screen it is actually on, instead of being undone
  by the next screen change.
- **Pull requests waiting for your review** on the same card as your own, from a second search
  in the same request.
- **The branch on a card is a link** to the repository it came from, read from the checkout's
  own `.git/config`.
- **The deck is quieter** - colour left the chips, the palette came down about 20%, the dim text
  came up and the bright text came down, and every outline that was not the offered action came
  off. Two directions were drawn at true scale first; see [adr/0010-card-palette.md](adr/0010-card-palette.md).
- **The plain-project settings form**, in the same language: a header with the name and the
  card switch, commands with their captions above them, switches that explain themselves in one
  line instead of four footnotes, the live health answer in the group that asks about it, and
  environment rows tagged in their chips' colours.

## Next

1. **Bundle versions on the project card** - live version per environment, which needs an org
   token and the Developer Center endpoints pinned down against a real organisation.
2. **Resizable panels** - dragging the bottom edge instead of the expander, if the three-row
   default plus expansion turns out not to be enough.
3. **A tunnel, when the wifi is not enough** - `ddev share` for DDEV projects, and ngrok or
   Tailscale for the rest. The QR code covers the same network; this covers the customer on a
   call.
4. **A code identity that survives a rebuild** - a self-signed certificate would let the Keychain
   items go back to naming this app rather than none, and a Developer ID would also end
   Gatekeeper for anybody downloading a release.

## Not planned

- WidgetKit widgets in Notification Center. They need Xcode and their own refresh budget; the
  panels already sit on the desktop. Revisit only if Xcode gets installed.
- Windows or Linux. Decided against - see [adr/0001-native-macos-app.md](adr/0001-native-macos-app.md).
