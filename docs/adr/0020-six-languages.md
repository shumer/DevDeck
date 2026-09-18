# 0020 - The interface speaks six languages, the terms do not

## Status

Accepted.

## Context

The deck is written in English, and the people using it are not all reading English by choice.
The app has no Xcode project, so the usual route - an asset catalog, `NSLocalizedString` picked
up by `genstrings`, a base localisation per target - is not available: the bundle is assembled by
`build.sh` from a SwiftPM build, and nothing in that chain knows what a `.lproj` folder is unless
it is told.

Six languages were asked for: English, German, Spanish, French, Italian and Russian. The system
language by default, with a forced choice in Settings.

## Decision

**One place reads the tables.** `Strings.swift` in Core holds `AppLanguage`, the chosen bundle
and English under it as a floor. Every call site says `L("key")`, `L("key", argument)` or
`LN("key", count)`, and nothing caches what comes back, because Settings can change the language
while the deck is up. A key with no translation falls through to English, and a key with no
English shows as the key itself: ugly, and unmistakable, which is what a hole should be.

**The tables are `Resources/Localizations/<code>.lproj/Localizable.strings`**, copied into the
bundle by `build.sh`, with `CFBundleLocalizations` listing the six. Counts live in
`Localizable.stringsdict`, one plural rule set per language, because Russian has three forms
where English has two and no amount of string joining gets that right.

**The suite is the proof.** `LocalisationTests` fails when a key is missing from one table or
left over in another, when a plural key has no `few`/`many` in Russian, and when the arguments
of a translation do not match the English one. The test executable has no bundle, so it points
`Strings.use(.english, lookingIn:)` at the repository.

**Product names stay as they are written.** `pull request`, `merge request`, `pipeline`,
`commit`, `Docker`, `DDEV`, `Arc XP`, `GitHub`, `GitLab` are the words people use in every one of
these languages. Logs stay English: they are read by whoever is debugging, and a log in two
languages is a log nobody can grep.

**The layout is measured, not guessed.** A translation can be half again as long as the English:
a settings group sizes its label column to its own longest label, and a card's button row gives
up whole words - the quiet ones first, from the right - and lets the icon carry the button with
the word in its tooltip, rather than shrinking four labels until each is cut in the middle.

## Rejected

- **Machine translation at runtime.** It needs a network, it costs money, and it gets the short
  words wrong in exactly the places that matter: `stuck`, `stopped`, `clear`.
- **A key per sentence fragment**, assembled at runtime. Word order is not the same in six
  languages; whole sentences with positional arguments (`%1$@`, `%2$@`) are.
- **Translating the terms.** `Запрос на слияние` is not what anybody says out loud, and a term
  translated on the card but not in the API's own web page is two names for one thing.
- **Relaunching to change the language.** The tables are swapped under the views and the window
  is rebuilt; a restart for a setting this small would be the app admitting it is not native.

## Consequences

- Every user-facing string is a key. A literal in a view is a bug the suite cannot see, so it is
  caught in review instead.
- `CardCatalog.all`, `CheckSummary.checking` and the other former `static let` constants became
  computed properties: a constant evaluated once would keep the language it was first read in.
- The tables are generated from one source in the scratchpad rather than edited six times by
  hand, and the generator is not part of the repository: what ships is the six tables.
