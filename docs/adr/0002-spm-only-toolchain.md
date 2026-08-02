# 0002 — SwiftPM only, no Xcode, no WidgetKit

Status: accepted, 2026-08-02

## Context

The build machine has Swift 6.3 from the Command Line Tools; Xcode is not installed. The SDK
ships SwiftUI, AppKit and WidgetKit, so the frameworks compile — but the tooling around them
does not exist:

- `XCTest` and `swift-testing` are not in the Command Line Tools SDK. `swift test` fails with
  `no such module 'XCTest'`.
- Building an `.appex` widget extension, or any bundle with a nested target, needs Xcode's
  build system.

## Decision

1. One SwiftPM package, no `.xcodeproj`, no generated project.
2. Desktop panels are borderless `NSWindow`s with `NSVisualEffectView` blur hosting SwiftUI
   views — not WidgetKit widgets.
3. The test suite is an executable target (`Tests/DevDeckTests`) with a small framework in
   `Tests/TestHarness`: named tests, async support, assertions that throw, non-zero exit code.
4. `build.sh` assembles `DevDeck.app` by hand — `Info.plist`, executable, ad-hoc signature.
5. Language modes are split: `DevDeckCore`, `GitHubKit` and the tests run in Swift 6 strict
   concurrency; `DevDeckUI` and `DevDeckApp` stay on Swift 5, where main-actor isolation of
   the AppKit and SwiftUI types is inferred rather than enforced.

## Consequences

- No Xcode dependency at all: clone, `./run-tests.sh`, `./build.sh`.
- Panels are more capable than WidgetKit widgets would be — they refresh on our schedule
  rather than the system's ~40-a-day budget, and they can run anything.
- No presence in Notification Center, and no `.app` on the App Store without notarisation.
- The suite has no XCTest niceties: no parameterised tests, no parallelism, no
  `XCTUnwrap`. `expectNotNil` covers the last one.
- If Xcode is installed later, `swift test` can be adopted incrementally — the harness API is
  small and the assertions map one to one.
