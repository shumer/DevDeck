import DevDeckCore
import Foundation
import TestHarness

private let catalog: [CardDescriptor] = [
    CardDescriptor(id: .githubPullRequests, title: "PRs", subtitle: "", isImplemented: true, isEnabledByDefault: true),
    CardDescriptor(id: .githubInbox, title: "Inbox", subtitle: "", isImplemented: false, isEnabledByDefault: true),
    CardDescriptor(id: .arcOrganizations, title: "Arc", subtitle: "", isImplemented: false, isEnabledByDefault: false),
]

func runConfigurationTests(_ run: TestRun) async {
    run.section("Cards — layout")

    await run.test("defaults come from the catalog") {
        let layout = CardLayout.default
        try expectEqual(layout.settings.count, CardCatalog.all.count)
        try expect(layout.isEnabled(.githubPullRequests), "the PR card ships enabled")
    }

    await run.test("saved order is preserved and new cards are appended") {
        let layout = CardLayout(settings: [
            CardSetting(id: .arcOrganizations, isEnabled: true),
            CardSetting(id: .githubPullRequests, isEnabled: true),
        ])
        let resolved = layout.resolved(catalog: catalog)
        try expectEqual(resolved.map(\.id.rawValue), [
            CardID.arcOrganizations.rawValue,
            CardID.githubPullRequests.rawValue,
            CardID.githubInbox.rawValue,
        ], "unknown-to-the-user cards land at the end")
        try expect(resolved.last!.isEnabled, "an appended card uses its catalog default")
    }

    await run.test("identifiers that are no longer in the catalog are dropped") {
        let layout = CardLayout(settings: [
            CardSetting(id: CardID(rawValue: "removed.card"), isEnabled: true),
            CardSetting(id: .githubPullRequests, isEnabled: false),
        ])
        let resolved = layout.resolved(catalog: catalog)
        try expect(!resolved.contains { $0.id.rawValue == "removed.card" })
        try expect(!resolved.first!.isEnabled, "the stored preference still wins")
    }

    await run.test("duplicated identifiers are collapsed to the first one") {
        let layout = CardLayout(settings: [
            CardSetting(id: .githubPullRequests, isEnabled: false),
            CardSetting(id: .githubPullRequests, isEnabled: true),
        ])
        let resolved = layout.resolved(catalog: catalog)
        try expectEqual(resolved.filter { $0.id == .githubPullRequests }.count, 1)
        try expect(!resolved.first!.isEnabled)
    }

    await run.test("only enabled and implemented cards are shown") {
        let layout = CardLayout(settings: [
            CardSetting(id: .githubPullRequests, isEnabled: true),
            CardSetting(id: .githubInbox, isEnabled: true),
        ])
        let visible = layout.visibleCards(catalog: catalog)
        try expectEqual(visible.map(\.id.rawValue), [CardID.githubPullRequests.rawValue],
                        "a card without an implementation must not render")
    }

    await run.test("toggling and reordering mutate the stored list") {
        var layout = CardLayout(settings: [
            CardSetting(id: .githubPullRequests, isEnabled: true),
            CardSetting(id: .githubInbox, isEnabled: true),
        ])
        layout.setEnabled(false, for: .githubInbox)
        try expect(!layout.isEnabled(.githubInbox, catalog: catalog))

        layout.setEnabled(true, for: .arcOrganizations)
        try expect(layout.isEnabled(.arcOrganizations, catalog: catalog),
                   "a card missing from the list is appended when toggled")

        layout.move(.arcOrganizations, to: 0)
        try expectEqual(layout.settings.first?.id, .arcOrganizations)
    }

    run.section("Preferences")

    await run.test("card layout survives a round trip") {
        let preferences = Preferences(backend: InMemoryPreferences())
        var layout = CardLayout.default
        layout.setEnabled(false, for: .githubPullRequests)
        preferences.cardLayout = layout
        try expect(!preferences.cardLayout.isEnabled(.githubPullRequests))
    }

    await run.test("a corrupt layout falls back to the defaults") {
        let backend = InMemoryPreferences()
        backend.set(Data("not json".utf8), forKey: "cards.layout")
        let preferences = Preferences(backend: backend)
        try expectEqual(preferences.cardLayout, CardLayout.default)
    }

    await run.test("placement defaults to the desktop, unlocked") {
        let preferences = Preferences(backend: InMemoryPreferences())
        try expectEqual(preferences.displayMode, .desktop)
        try expect(!preferences.isLocked)

        preferences.displayMode = .floating
        preferences.isLocked = true
        preferences.setTopLeft("{100, 200}", for: .githubPullRequests)

        try expectEqual(preferences.displayMode, .floating)
        try expect(preferences.isLocked)
        try expectEqual(preferences.topLeft(for: .githubPullRequests), "{100, 200}",
                        "positions anchor on the top edge, because cards change height")
        try expectNil(preferences.topLeft(for: .githubInbox))
    }

    await run.test("a panel's height is remembered so it opens at the right size") {
        // Without this a card opens at its empty height and grows a moment later, shoving
        // whatever is beneath it down the screen on every launch.
        let preferences = Preferences(backend: InMemoryPreferences())
        try expectNil(preferences.height(for: .githubPullRequests))

        preferences.setHeight(230, for: .githubPullRequests)
        try expectEqual(preferences.height(for: .githubPullRequests), 230)

        preferences.setHeight(0, for: .githubPullRequests)
        try expectNil(preferences.height(for: .githubPullRequests), "a nonsense height is no height")
    }

    await run.test("a nonsense refresh interval falls back to the default") {
        let backend = InMemoryPreferences()
        backend.set("-5", forKey: "refresh.interval")
        try expectEqual(Preferences(backend: backend).refreshIntervalSeconds, 120)
    }

    run.section("Refresh policy")

    await run.test("the interval never drops below the minimum") {
        let policy = RefreshPolicy(interval: 10, minimumInterval: 60, maximumInterval: 900)
        try expectEqual(policy.nextDelay(consecutiveFailures: 0), 60)
    }

    await run.test("the server hint wins when it asks for more") {
        let policy = RefreshPolicy(interval: 120, minimumInterval: 60)
        try expectEqual(policy.nextDelay(consecutiveFailures: 0, serverHint: 300), 300)
        try expectEqual(policy.nextDelay(consecutiveFailures: 0, serverHint: 30), 120,
                        "a shorter hint does not speed us up")
    }

    await run.test("failures back off and stop at the maximum") {
        let policy = RefreshPolicy(interval: 120, minimumInterval: 60, maximumInterval: 900)
        try expectEqual(policy.nextDelay(consecutiveFailures: 1), 240)
        try expectEqual(policy.nextDelay(consecutiveFailures: 2), 480)
        try expectEqual(policy.nextDelay(consecutiveFailures: 8), 900)
    }

    await run.test("a rate limit reset outranks the backoff") {
        let policy = RefreshPolicy(interval: 120, minimumInterval: 60, maximumInterval: 900)
        let now = Date(timeIntervalSince1970: 1_000)
        let delay = policy.nextDelay(
            after: .rateLimited(resetAt: Date(timeIntervalSince1970: 1_400)),
            consecutiveFailures: 1,
            now: now
        )
        try expectEqual(delay, 405, "wait out the window plus a small margin")
    }

    await run.test("an expired rate limit falls back to the normal backoff") {
        let policy = RefreshPolicy(interval: 120, minimumInterval: 60)
        let now = Date(timeIntervalSince1970: 2_000)
        let delay = policy.nextDelay(
            after: .rateLimited(resetAt: Date(timeIntervalSince1970: 1_000)),
            consecutiveFailures: 1,
            now: now
        )
        try expectEqual(delay, 240)
    }

    run.section("Card state")

    await run.test("a failure keeps the last good value") {
        var state = CardState<Int>()
        try expect(state.isStale(now: Date(), maxAge: 60), "no value is always stale")

        let stamp = Date(timeIntervalSince1970: 5_000)
        state.beginRefresh()
        state.succeed(42, at: stamp)
        try expectEqual(state.value, 42)
        try expect(!state.isRefreshing)

        state.fail(.transport("offline"))
        try expectEqual(state.value, 42, "the panel keeps showing the last number")
        try expectEqual(state.failure, .transport("offline"))
        try expectEqual(state.updatedAt, stamp)
    }

    await run.test("staleness is measured from the last success") {
        var state = CardState<Int>()
        let stamp = Date(timeIntervalSince1970: 5_000)
        state.succeed(1, at: stamp)
        try expect(!state.isStale(now: stamp.addingTimeInterval(59), maxAge: 60))
        try expect(state.isStale(now: stamp.addingTimeInterval(61), maxAge: 60))
    }

    run.section("Tokens")

    await run.test("the environment store reads the documented variables") {
        let store = EnvironmentTokenStore(environment: ["GITHUB_TOKEN": " ghp_example "])
        try expectEqual(try store.token(for: .github), "ghp_example", "whitespace is trimmed")
        try expectNil(try EnvironmentTokenStore(environment: [:]).token(for: .github))
    }

    await run.test("DEVDECK_GITHUB_TOKEN wins over GITHUB_TOKEN") {
        let store = EnvironmentTokenStore(environment: [
            "GITHUB_TOKEN": "shell",
            "DEVDECK_GITHUB_TOKEN": "app",
        ])
        try expectEqual(try store.token(for: .github), "app")
    }

    await run.test("the composite store prefers the first store that has a token") {
        let primary = InMemoryTokenStore(tokens: [.github: "keychain"])
        let fallback = EnvironmentTokenStore(environment: ["GITHUB_TOKEN": "environment"])
        let composite = CompositeTokenStore([primary, fallback])
        try expectEqual(try composite.token(for: .github), "keychain")

        try primary.setToken(nil, for: .github)
        try expectEqual(try composite.token(for: .github), "environment")
    }

    await run.test("writes go to the first store that accepts them") {
        let readOnly = EnvironmentTokenStore(environment: [:])
        let writable = InMemoryTokenStore()
        let composite = CompositeTokenStore([readOnly, writable])
        try composite.setToken("written", for: .github)
        try expectEqual(try writable.token(for: .github), "written")
    }
}
