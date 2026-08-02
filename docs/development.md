# Development

## Toolchain

Swift 6.3 from the Command Line Tools. **Xcode is not installed and not required.**

That single fact shapes the project:

- `XCTest` and `swift-testing` both live in Xcode, so `swift test` cannot run here. The suite
  is an executable target with a tiny framework in `Tests/TestHarness`.
- There is no `.xcodeproj`, no widget extension and no WidgetKit. Panels are borderless
  `NSWindow`s hosting SwiftUI views — see [adr/0002-spm-only-toolchain.md](adr/0002-spm-only-toolchain.md).
- `build.sh` assembles `DevDeck.app` by hand and ad-hoc signs it.

## Commands

```bash
./run-tests.sh              # offline suite; non-zero exit on failure
scripts/smoke-test.sh       # one real API call using the stored token
./build.sh                  # tests, build, bundle, install to /Applications, launch
./build.sh --no-install     # build the bundle only
./build.sh --skip-tests     # do not do this
swift run DevDeck           # run from the terminal without bundling
pkill -f DevDeck            # quit a running instance
```

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
  `UserDefaults`. Use `FakeHTTPClient`, `InMemoryTokenStore`, `InMemoryPreferences`.
- **No real waiting.** Inject `RecordingSleeper` and `MutableDateProvider` instead of
  sleeping or reading the clock.
- Live behaviour belongs in `Tools/Smoke`, not in the suite.

## Keychain and ad-hoc signing

The app is ad-hoc signed, so its code signature changes on every build and macOS may prompt
before letting the new binary read the Keychain item. `scripts/seed-token.sh` writes the item
with `-A` (any application may read it) to avoid a prompt after every rebuild. The app's own
Settings window writes a normally-scoped item instead. If you get a prompt loop, re-run
`scripts/seed-token.sh`.

## Definition of done

Every change lands with all four, or it is not done:

1. **Code** builds clean: `swift build` with no warnings introduced.
2. **Tests** cover the new behaviour and `./run-tests.sh` is green.
3. **Docs** updated — `README.md` if the user-visible behaviour changed, the relevant file in
   `docs/`, and a new ADR when a decision was made rather than a detail implemented.
4. **Roadmap** updated if the change moves or adds work.

Comments explain *why*, not *what*. If a line needs a comment to say what it does, rename
something instead.
