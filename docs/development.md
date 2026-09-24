# Development

## Toolchain

Swift 6.3 from the Command Line Tools. **Xcode is not installed and not required.**

That single fact shapes the project:

- `XCTest` and `swift-testing` both live in Xcode, so `swift test` cannot run here. The suite
  is an executable target with a tiny framework in `Tests/TestHarness`.
- There is no `.xcodeproj`, no widget extension and no WidgetKit. Panels are borderless
  `NSWindow`s hosting SwiftUI views - see [adr/0002-spm-only-toolchain.md](adr/0002-spm-only-toolchain.md).
- `build.sh` assembles `DevDeck.app` by hand and signs it: with a Developer ID when the Keychain
  has one, ad-hoc otherwise.
- **The binary is stamped with the SDK it was really built against**, through
  `-platform_version macos 14.0 <sdk>`. SwiftPM writes the deployment target into that field
  instead, and macOS reads it to decide which era of window chrome to draw: without the flag the
  settings window gets title-bar buttons two points smaller than every other window's. The
  deployment target stays at macOS 14. The release workflow therefore runs on `macos-26`; the test
  workflow stays on `macos-15`, which keeps the code honest about building on the older SDK.

## Commands

```bash
./run-tests.sh                    # offline suite; non-zero exit on failure
./run-tests.sh projects docker    # only the sections whose names contain these words
scripts/smoke-test.sh             # real GitHub and GitLab calls using the stored tokens
./build.sh                        # tests, build, bundle, install to /Applications, launch
./build.sh --no-install           # build the bundle only
./build.sh --skip-tests           # do not do this
swift run DevDeck                 # run from the terminal without bundling
swift run IconPreview out.png     # draw the menu-bar icon at menu-bar size, at 2×
swift run GlyphPreview out.png    # draw every card mark at 15 points and blown up
iconutil -c icns Resources/AppIcon/DevDeck.iconset -o /tmp/DevDeck.icns   # what build.sh packs
open -a DevDeck --args --menu sample   # the installed app's menu, with a row of every tier
open -a DevDeck --args --logs         # a log window, without a hand on the mouse
open -a DevDeck --args --logs project.agrica-qdd   # that project's log window
pkill -f DevDeck                  # quit a running instance
scripts/check-arc-stack.sh        # what an Arc card checks, from a terminal, for a card that
                                  # says "running" when the stack is not
```

The DDEV cards need the `ddev` CLI on the PATH a login shell sees; Arc, DDEV and any plain
project marked as needing it want Docker running, and say so on the card when it is not.
Neither is needed to build or to run the suite.

## Building with the Command Line Tools alone

The tools' default SDK symlink moves with their updates, and from the macOS 27 SDK on SwiftUI's
`@State` resolves to a macro whose plugin only Xcode ships: `plugin for module
'SwiftUIMacros' not found`, on every card. The code therefore writes that storage out by hand,
a stored `State(initialValue:)` and a computed property over it, which compiles against every
SDK and is exactly what the attribute expands to. Do not reintroduce `@State`; see CLAUDE.md.

The default build system also prints a run of `ld: warning: search path ... not found` lines
about a directory the Command Line Tools do not have. They are the toolchain's, not this
package's, and the CI warning check runs under Xcode where they do not appear.

## Tests

`Tests/DevDeckTests` is a plain executable. Add a `func runXTests(_ run: TestRun) async` and
call it from `main.swift`. Assertions throw, so a test stops at its first bad expectation:

```swift
await run.test("a 304 is answered from the cache") {
    let client = FakeHTTPClient([.success(.json("[]", headers: ["ETag": "\"v1\""])), .success(.status(304))])
    let transport = APITransport(client: client, sleeper: RecordingSleeper())
    ...
    try expectEqual(response.wasNotModified, true)
}
```

Rules:

- **Offline and deterministic.** No test may touch the network, the Keychain or
  `UserDefaults`. Use `FakeHTTPClient`, `InMemoryTokenStore`, `InMemoryPreferences`,
  `StubCommandRunner`.
- **No real waiting.** Inject `RecordingSleeper`, `AdvancingSleeper` and `MutableDateProvider`
  instead of sleeping or reading the clock.
- Live API behaviour belongs in `Tools/Smoke`, not in the suite.
- **One deliberate exception:** `CommandRunnerTests` runs real processes - `echo`, `cat`,
  `sleep` - and writes temporary files. Every bug it covers was invisible to a stub: a blocked
  main thread, a command waiting on stdin, a timeout that never fired, a deadlocked pipe. It
  stays local, takes about a second, and touches nothing outside `NSTemporaryDirectory()`.
  Tests that read `.env`, `.git/HEAD`, `.ddev/config.yaml` or `composer.lock` write those
  files into a temporary folder for the same reason.

## Adding a string

There are no literals on screen. A new word is a key in all six tables under
`Resources/Localizations/<code>.lproj/Localizable.strings`, read with `L`, `L(_:_:)` or, when it
carries a number, `LN` with an entry in each `Localizable.stringsdict`. Keys read `area.thing`
(`settings.deck.lock`, `attention.tier.stuck`, `card.action.restart`), English is the table the
others are measured against, and `LocalisationTests` fails on a key that is missing from one
table, left over in another, or whose arguments do not line up with the English.

The suite also sweeps the sources for every `L("…")` and `LN("…")`, so a key that no table has
and a word no code says both fail the same test. Write the key as a literal at each call site -
`count == 1 ? L("a.one", x) : L("a.many", x)`, never `L(count == 1 ? "a.one" : "a.many", x)` -
or the sweep cannot see it.

Sentences take positional arguments, `%1$@` and `%2$@`, because the order is not the same in six
languages. Terms stay as they are written - `pull request`, `pipeline`, `Docker` - and so do the
logs. A string that a translation makes longer must not be laid out against a fixed width: see
[architecture.md#words](architecture.md#words).

To see the app in another language without changing the setting:

```bash
defaults write com.shumer.devdeck language -string ru   # en, de, es, fr, it, ru or system
```

## Signing

A local build is signed with the Developer ID it finds in the Keychain, or with whatever
`CODESIGN_IDENTITY` names, and is ad-hoc only when there is neither or when
`CODESIGN_IDENTITY=-` asks for it. The code reads which it got: an ad-hoc build writes tokens with an open access list, a signed
one lets the Keychain bind them to the app and the updater check what it downloads. See
[adr/0017-signature-decides.md](adr/0017-signature-decides.md).

**Your own machine, today.** In Keychain Access: Certificate Assistant, Create a Certificate,
name it `DevDeck Local`, type Code Signing. Then:

```bash
CODESIGN_IDENTITY="DevDeck Local" ./build.sh
```

The first launch rewrites the stored tokens once, one password prompt each, and after that
neither updates nor rebuilds prompt again, because the identity is the same.

**Never the other way by itself.** Once tokens are bound to an identity, a copy without one,
`swift run DevDeck` or an ad-hoc build, leaves them bound and asks for the password on each
read rather than opening them to every process. If a prompt is dismissed during a rewrite,
the mode is not recorded and the next launch tries again.

**Releases, once the Developer ID exists.** The workflow signs, notarises and staples on the
runner, never here: `notarytool` ships with Xcode, which the runner has. It needs five
repository secrets. Without `DEVELOPER_ID_P12` or `NOTARY_KEY_P8` it builds the ad-hoc release it
always did; with those two set, a missing or wrong other secret fails the release.

| secret | what it is |
|---|---|
| `DEVELOPER_ID_P12` | the Developer ID Application certificate with its private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | the password given to that export |
| `NOTARY_KEY_ID` | the App Store Connect API key's id |
| `NOTARY_ISSUER_ID` | the issuer id shown next to it |
| `NOTARY_KEY_P8` | the `.p8` file of that key, `base64 -i AuthKey_XXXX.p8` |

Where they come from: the certificate under developer.apple.com, Certificates, plus, Developer
ID Application, fed a request made in Keychain Access (Certificate Assistant, Request a
Certificate from a Certificate Authority, saved to disk); only the account holder can create
one. The API key under App Store Connect, Users and Access, Integrations, App Store Connect
API, Team Keys, role Developer; the `.p8` downloads once. Set them with `gh secret set NAME`
and the value on standard input, so nothing lands in a shell history, then run the release
workflow by hand against an existing tag to see the signed path work before the next release.

## Definition of done

`./run-tests.sh` and `swift build` are run **before every commit**, whatever the change looks
like. Then all four of these are true, or the change is not done:

1. **Code** builds clean: `swift build` with no warnings introduced.
2. **Tests** cover the new behaviour, and a fixed bug has a test that fails without the fix.
3. **Docs** updated - `README.md` if user-visible behaviour changed, the relevant file in
   `docs/`, and a new ADR when a decision was made rather than a detail implemented.
4. **Roadmap** updated if the change moves or adds work.

The full checklist, and why it is worded as strictly as it is, is at the top of `CLAUDE.md`.

Comments explain *why*, not *what*. If a line needs a comment to say what it does, rename
something instead.
