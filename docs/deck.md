# Using the deck

How the panels behave on the desktop: placing, folding, summoning, the menu, notifications, the
log windows, and the language the deck speaks. What each card shows is in [cards.md](cards.md).

## The panels

The menu-bar item is a stack of cards with the app's initials cut out of the front one, and a
badge that says which kind of attention is wanted. The kinds differ in shape as well as colour,
so they read without colour vision and on a bar tinted by the wallpaper:

| Badge | Tier | What puts it there |
|---|---|---|
| red dot | **Waiting on you** | a review on GitHub or GitLab, a mention, an assignment, a security alert |
| dot in the bar's ink | **Needs fixing** | a token that stopped working, a project on this Mac that stopped on its own, did not start, is up but not answering, or has a broken file sync, Docker quitting under running projects |
| ring | **Your work is stuck** | your pull request or merge request with a conflict, failed checks, a failed pipeline or requested changes; a workflow still failing on a main branch |
| none | **Good to know** | a new version, commits that have been only on this Mac for more than three days, Docker off while a project needs it, Stop pressed on a project DevDeck did not start, a rate limit or a network blip |

The most urgent tier wins. Red is kept for the one thing that costs somebody else time. The
tooltip counts by tier, `DevDeck: 2 waiting on you, 1 to fix`, and VoiceOver reads the same.

**The menu lists the things themselves**, one row each, under a header per tier. A row says what
happened and to what, `Review: Fix cache invalidation on publish`, with where, who and why under
it, `acme/arc-web #482 · anna asked`, and how long ago on the right. Clicking it goes there: the
pull request in the browser of its account, the account's form for a token, the deck raised with
a project's log open, Docker started, a terminal in a checkout. A deck raised from the menu or a
banner goes back down with a click anywhere outside the cards, Esc, or the shortcut. ⌥ turns a project's row into
**Dismiss** and an inbox row into **Mark as Read**. Three rows show per tier, the rest are in a
submenu under them, and a review that is also an inbox notification is one row. With nothing to
say the menu opens on **Nothing needs you** and when the deck last checked. It used to open on a
greyed-out `1 waiting on you`, which named nothing and could not be clicked.

A project that stops is only news if nobody pressed Stop: the deck remembers what it saw and what
you pressed, reports nothing about a project that was already stopped at launch, and folds every
project that went down with Docker into one **Start Docker** row. Silence from a health check is
only said after two minutes, and a network error only becomes something to fix after fifteen.

The menu-bar glyph is drawn in code, because an icon that is drawn can be judged at 15 points by
rendering it at 15 points: `swift run IconPreview out.png` puts all four states on a light and a
dark bar. The application icon is artwork, in `Resources/AppIcon`: an iconset whose every size was
drawn at that size rather than resampled, with the SVG and the geometry it came from beside it,
packed into an `.icns` by `build.sh`. It shows a deck: four dark cards on a pale ground, a green
dot on the ones that are running and an amber one on the card that wants something. Being an agent
app, DevDeck is in Finder and in Login Items rather than in the Dock, and it appears there only
while its settings window is open.

Its menu holds what you do:

- **What needs you**, the rows above, with a new version under Good to know; see
  [Updating](releases.md#updating).
- **Cards** - show or hide each card; a hidden card is not fetched at all. Projects get a submenu
  per kind below the built-in cards, with how many are shown in its title, and **Power off all
  DDEV** follows when there is a DDEV project.
- **Open pull requests in browser**.
- **Tidy panels into columns** - close up gaps without resetting where you put them, one display
  at a time: a card you keep on the monitor stays on the monitor. On each display it anchors on
  the topmost panel and stacks downwards, starting a new column beside it whenever the next card
  would hang below the screen, so a deck of six cannot push its last card under the bottom edge
  where nothing can grab it. The order it lays out is the deck's own: the built-in cards,
  then Arc projects, then DDEV, then the plain ones, each group alphabetical.
- **Arrangements** - save the deck as it stands under a name, and put it back later. An
  arrangement is which cards are on the deck, which are folded to one row, and where each one
  sits; the tick shows which one you are in, compared rather than remembered, so it cannot claim
  an arrangement you have since dragged your way out of. Alt-click one to forget it.
- **Lock positions** - a checkmark; while it is on, a stray drag moves nothing.
- **Refresh now**, **Settings…** and **Quit DevDeck**.

What the deck *is* rather than what you do with it lives in Settings: start at login and the
interface language under **General**, and where the panels sit, the lock, closing gaps, the
summon shortcut and its dimming under **Deck**. A menu that mixes the two grows until the thing you came for is
somewhere in the middle of it. The one exception is the lock, which is also a checkmark in both
menus: it gets toggled in the middle of arranging cards, and a trip to a settings window for that
is the one interruption the deck should not cost.

Right-click a panel and the menu is about that card: fold it to a row, open or close its log,
take it off the deck, open **Settings for This Card…**, which lands on that card's own form, and
under a separator the deck-wide few: Lock positions, Tidy and Refresh now.

Cut, copy and paste work in the settings window. That is not as obvious as it sounds for an
agent app: with no Dock icon there is no menu bar of its own, ⌘V is routed through the main menu,
and with no Edit menu there was nothing to route it to, so pasting a token was impossible.

The settings window looks and behaves like System Settings, down to its measurements: a full
height translucent sidebar whose rows follow the Mac's own sidebar icon size, the standard title
bar, and a form for whatever is selected in the sidebar. Its width is fixed, since the form has
one column, and its height is yours to change. It minimises to the Dock like any other window,
carrying the app's icon, and ⌘W closes it. At the top of the sidebar are four pages. **General** is start at login, the
interface language, updates and the version. **Deck** is where the cards sit, the lock, closing gaps and the summon shortcut.
**Cards** switches the cards that are not an account or a project on and off, with the refresh
interval and the Actions repositories. **Notifications** is the master switch and two tables:
what each account and what each project may interrupt you about. Under them come **Accounts**, GitHub and GitLab
together, and **Projects** of every kind, alphabetical, each with the mark its card wears and a
dot only while it is running or starting. Search narrows the list, the arrow keys move through it
and Delete removes the selected thing after asking; ⌘F goes to the search field. The window
remembers its size.

Every form has **Show on deck** in its header. A plain project's form is in the order you fill
it in: folder and start command, then the health check with its live answer, then the links on
the card; name, caption, stop command, Docker and browser are under **Advanced**. An Arc form
starts with the local stack, then the organisation and site ID, then the links, where you add
and remove your own; name, stop command and browser are under **Advanced**. A DDEV form is the
folder and name, which tools the card shows, the links and the browser. The answer to **Detect**
or **Test** appears next to the button, and a check reruns by itself when the address changes.
An account's form is its token, one line saying whether it is stored and whether it works, a
field for a new one where Return or **Save Token** saves it, and a button to create one; then its
name and browser, for GitLab its address, and for GitHub the organisations under **Advanced**.
Everything else applies as you change it.

A project card shows the last command of its start chain, `dotnet run --launch-profile http` rather
than the `source` and `cd` that lead up to it, and no text on a card can push the card out of its
panel.

Drag a panel anywhere; the position is remembered per card - **against the display it is on**,
not as a point on the desktop. Unplug the monitor the deck lives on and the cards are parked on
the screen that is left, folded to one row each and stacked in a single column at the side the
deck stood on, in the order it reads in; plug it back in and every card goes home and stands up
again, exactly where it was. Nothing is re-saved while a card is parked, because parking is not a
decision you made, and neither is the shove macOS gives windows when a display disappears: the
deck waits for the screens to settle before it believes a move was yours. This is why a deck kept
on the laptop screen no longer scatters when an external display that happens to be the main one
comes and goes, and why quitting and reopening puts every panel back exactly where it was rather
than a little further down each time. The deck moves a card only when
you asked it to: collapsing one, expanding a list. Data arriving never moves anything, and
neither does a log any more: it opens in a window of its own. **Close gaps automatically**, under Settings → Deck and off by default, closes the gaps in a column whenever
a card changes height, at the price of any gap you left in it on purpose.

**Being told.** One switch, **Allow notifications** on the Notifications page of Settings, off
until you turn it on, because asking for notification permission before an app has done anything
for you is what people say no to and never revisit. *What* you are told about is set on the same
page. Per account: **Review requests**, **My work stuck**, and for GitHub **Failed runs**, a
workflow failing on a main branch, which needs the Actions card on. Per project: **Went down**,
stopped without anyone pressing Stop or stopped answering, and **Start failed**. And **New
versions of DevDeck**. So a customer's instance can stay quiet while your own does not, per token,
per kind. A token that stops working is always said, once.

A banner's title says what happened, `anna asked for your review`, its subtitle where,
`acme/portal #142 · Work`, and its body which thing and what a click does. It carries the source's
own mark, the octocat, the tanuki, Arc's A, DDEV or Docker, so who is asking is answered before the
words are read. Only a person waiting on you makes a sound. Nothing is announced on the first
answer after a launch, since that is the state you left things in, and nothing is announced twice,
even across restarts. Three at once become one banner that counts them by kind and names the first
two, and a click on it opens the menu that lists them all. A start that failed while you watched
it is not announced, and neither is a stop that did not take: you are looking at that card.
**Send Test Notification** posts one immediately so the whole chain can be checked.

While the display a card belongs to is unplugged, tidying or dragging the parked card makes that
its new home. Its context menu says it is folded because its display is away, in place of the
fold item, since that is not a choice on offer while it is parked.

Click a row to open that pull request, and double-click a list card's background to open the same
list on the web.

Buttons work on the first click even though the deck sits behind your windows and is never the
frontmost app - which is not what AppKit does by default, and is why they used to need pressing
twice.

A long command narrates itself. Starting an Arc stack takes about a minute, and while it runs
the card shows the line the command has just printed instead of nothing at all. If the stack
never comes up, the card keeps the reason the command gave - a port already taken, most often -
rather than reporting the silence that followed.

Anything clickable lights up under the pointer and turns the cursor into a hand. Because the
panels sit behind other windows, that tracking starts once the deck itself has been clicked -
so buttons and links also carry a resting fill rather than relying on hover to look pressable.

## How a card is put together

Every project card is the same six things, in the same order, so one glance answers the same
question on all of them:

1. **A mark and the title**, with the time of the last check on the right. The mark says what
   kind of project it is - the octocat, GitLab's tanuki, Arc's A, DDEV's mark, Node's hexagon,
   Next's disc, Nest's cat, Bun, Docker's whale, a hammer for a Makefile and a box for anything
   else. The vendors' marks are the real logos, drawn from their own SVG path data rather than
   shipped as images: this toolchain has no asset catalog, and a hand-drawn
   impression of the octocat at fifteen points looks exactly like what it is.
2. **The state, at 17 points** - one vocabulary on every card: `running`, `stopped`,
   `starting…`, `paused`, `unknown`, `not configured`, and `Docker is not running` when that is
   what is really in the way. This is the card's focal point, but a quiet one: the words are
   white at 76% and the colour lives in the dot beside them, which glows when it means something
   and goes plain grey when a project is simply stopped. Colour returns to the words only when
   something wants attention. A detail like `pid 48213`, `mutagen paused` or `not in ddev list`
   sits at the end of the same line.
3. **The branch**, on a line of its own, because branch names are longer than anything beside
   them - and it is a link: the checkout knows its origin, so clicking it opens the repository
   on GitHub in the project's own browser. An arrow at the end of the line says so; a checkout
   with no remote simply has no arrow.
4. **What names this checkout**: the framework and folder on the left, versions or the start
   command on the right. For an Arc project the version is the Fusion release actually running,
   read from the engine container's image tag rather than from the site's `/release` endpoint:
   that endpoint is answered by whatever is published on the site's port, which locally is
   `fusion-cli-api` reporting its own version. It is not `FUSION_RELEASE` from `.env` either,
   which says what the stack will run after the next build rather than what is serving requests
   now.
5. **The links**, in one wrapping row: what you work in, a divider, then the environments -
   local first, then test and UAT in violet, production in amber. An Arc project also gets
   **Local PageBuilder** beside **Local site**: the editor as served by the stack you are
   running, on the port the checkout's own `.env` says. The **PageBuilder** chip on the other
   side of the divider is the hosted one, which edits something else entirely, and the two are
   named so the pair reads as a pair. They all share one neutral
   fill; the colour is in the lettering, mixed back towards white, so five links in a row read
   as a row rather than as five things shouting.
6. **The controls.** The one action that matters now is half again as wide, tinted, bolder and
   the only one with an outline; the rest recede to a plain fill. All four carry an icon.

**Hold ⌥Space** and the deck comes up over your windows; let go and it drops back. A tap keeps it
up until the next press. Nothing moves and nothing is redrawn: they are the same panels at a
different window level, which is why this costs almost nothing. The screen dims 45% while they are
up, because dark glass over a white editor is unreadable otherwise. Both switches and the
combination itself are in Settings, Deck, under Shortcut, with a **Default** button that puts
⌥Space back. It needs no
permission: the shortcut is a Carbon hot key, not a global key monitor, so macOS has nothing to
ask you about.

Right-click a panel and **Collapse to one row** folds the card down to 44 points: the mark, the
state dot, the name and its controls as small squares. On a project those are the action the state
implies, a restart when there is one worth offering, a terminal, and the site while something is
serving it; on a list card, which has no lifecycle, one square opens the same list on the web and
the row keeps its count instead. It is remembered per card,
so the projects you are not working on today take a row each while the one you are stays whole.
Six collapsed cards come to 324 points against 1218 whole.

The **QR button** beside it puts the running site on your phone: the site is already being
served, it is only being asked for by a name that means "this device", so the address is swapped
for this Mac's own on the wifi and drawn as a code to point a camera at. It appears only while
the project is actually up, because a code pointing at a port nothing is listening on is a worse
answer than no button. No account, no tunnel, nothing published to the internet. The phone has to
be on the same network, and a dev server bound to localhost only will still refuse: that is what
`--host` is for. The card checks before it promises: it asks the address itself, from this
computer, and offers the code only when something answers there. A server bound to localhost,
or a container inside a WSL that keeps its ports to itself, answers on `localhost` and on nothing
else, and then there is no button rather than a code to nowhere. A DDEV project is reached by
name rather than by address, so its card offers the code only once the checkout is set up for a
phone; the DDEV section says how.

The small button beside the clock opens the **log in a window of its own**: dark, monospaced,
as big as you drag it, on any of the three project cards. Arc reads the containers carrying the
project's compose label, DDEV reads `ddev logs -s web`, and a plain project reads the log its
detached start already writes. The window re-reads every couple of seconds while you can see it
and nothing at all when it is behind something or minimised. The text is selectable and ⌘F
searches it; the footer says where the lines come from, keeps a **Follow** switch that stops
pulling you to the bottom the moment you scroll up, and opens the whole file when the last few
hundred lines are not enough. One window per project, each remembering its own size and place.

The state pill, the horizontal rule and the footer are gone: the pill said what the state line
says, and the timestamp took a whole row to be the least important thing on the card. Cards
came down from 249 to about 200 points and hold more than they did.

The palette is deliberately a step below fully saturated, and the contrast range is narrower at
both ends than it was: dim text came up, the title came down, and the only outline left on a card
belongs to the action being offered. One card looks better loud. Six of them on a desktop all day
do not. See [docs/adr/0010-card-palette.md](adr/0010-card-palette.md).

## Language

The interface speaks English, German, Spanish, French, Italian and Russian. It follows the
language of the Mac, and **Settings → General → Language** forces one of the six; the change is
immediate, with no restart.

What is not translated is deliberate: `pull request`, `merge request`, `pipeline`, `commit`,
`Docker`, `DDEV`, `Arc XP` are the words people say in every one of these languages, and the logs
stay in English, because a log in two languages is a log nobody can grep. Your own names - a
project's title, an account's label, a link's chip - are what you typed, whatever the interface
is set to.

A translation is often longer than the English, so the layout gives way rather than the words: a
group of settings widens its label column to its longest label, and a card's button row drops
whole words before it cuts any of them, leaving the icon with the word in its tooltip. See
[adr/0020-six-languages.md](adr/0020-six-languages.md).
