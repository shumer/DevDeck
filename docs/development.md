# Development

## Toolchain

Swift 6.3 from the Command Line Tools. **Xcode is not installed and not required.**

That single fact shapes the project:

- `XCTest` and `swift-testing` both live in Xcode, so `swift test` cannot run here. The suite
  is an executable target with a tiny framework in `Tests/TestHarness`.
- There is no `.xcodeproj`, no widget extension and no WidgetKit. Panels are borderless
  `NSWindow`s hosting SwiftUI views - see [adr/0002-spm-only-toolchain.md](adr/0002-spm-only-toolchain.md).
- `build.sh` assembles `DevDeck.app` by hand and ad-hoc signs it.

## Commands

```bash
./run-tests.sh                    # offline suite; non-zero exit on failure
scripts/smoke-test.sh             # one real API call using the stored token
./build.sh                        # tests, build, bundle, install to /Applications, launch
./build.sh --no-install           # build the bundle only
./build.sh --skip-tests           # do not do this
swift run DevDeck                 # run from the terminal without bundling
swift run IconPreview out.png     # draw the menu-bar icon at menu-bar size, at 2×
pkill -f DevDeck                  # quit a running instance
```

The DDEV cards need the `ddev` CLI on the PATH a login shell sees; Arc, DDEV and any plain
project marked as needing it want Docker running, and say so on the card when it is not.
Neither is needed to build or to run the suite.

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

## Keychain and ad-hoc signing

The app is ad-hoc signed, so its code signature changes on every build and macOS asks for the
login keychain before letting the new binary read a token it stored earlier.

**"Always Allow" holds until the next `./build.sh`, and no longer** - the rebuilt binary is a
different identity as far as the keychain is concerned. In day-to-day use, where the app is
not being rebuilt, the prompt appears once and then stays quiet.

`scripts/seed-token.sh` writes its item with `-A` (any application may read it), so tokens
seeded that way never prompt at all; the Settings window writes normally-scoped items. If the
prompting gets in the way during a stretch of rebuilding, re-seed the token with the script.

The permanent fix, if it is ever worth the one-time setup, is a self-signed code-signing
certificate in the login keychain and `codesign -s "<name>"` in `build.sh` instead of `-`:
a stable identity means one "Always Allow" forever. Deliberately not done - the prompt is
tolerable and the certificate is a manual Keychain Access step.

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
