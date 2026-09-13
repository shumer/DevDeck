import DevDeckCore
import Foundation
import TestHarness

/// A Keychain that refuses some reads, the way it does when a prompt is dismissed.
private final class RefusingTokenStore: TokenStore, @unchecked Sendable {
    private let inner: InMemoryTokenStore
    private let refused: Set<String>

    init(tokens: [TokenKey: String], refusing refused: Set<String>) {
        inner = InMemoryTokenStore(tokens: tokens)
        self.refused = refused
    }

    func token(for key: TokenKey) throws -> String? {
        if refused.contains(key.account) { throw TokenStoreError.keychain(-128) }
        return try inner.token(for: key)
    }

    func setToken(_ token: String?, for key: TokenKey) throws {
        try inner.setToken(token, for: key)
    }
}

func runIdentityTests(_ run: TestRun) async {
    run.section("Code identity - who signed this")

    await run.test("the suite's own binary has no identity that survives a rebuild") {
        // The linker signs ad-hoc on Apple silicon and not at all elsewhere; either way there is
        // nobody behind it, and that is the case the open access list exists for.
        let kind = CodeIdentity.current()
        try expect(!kind.survivesRebuild, "\(kind)")
    }

    await run.test("a path that is not a bundle is unsigned, not a crash") {
        try expectEqual(CodeIdentity.kind(ofBundleAt: URL(fileURLWithPath: "/nonexistent/Nothing.app")), .unsigned)
    }

    run.section("Code identity - what follows from it")

    await run.test("the Keychain mode follows the signature") {
        try expectEqual(KeychainAccessPolicy.mode(for: .adHoc), "open")
        try expectEqual(KeychainAccessPolicy.mode(for: .unsigned), "open")
        try expectEqual(KeychainAccessPolicy.mode(for: .signed(identity: "ABCDE12345")), "app:ABCDE12345",
                        "named, so a different identity later is a different mode")
        try expect(KeychainAccessPolicy.opensAccess(for: .adHoc))
        try expect(!KeychainAccessPolicy.opensAccess(for: .signed(identity: "ABCDE12345")))
    }

    await run.test("tokens are rewritten when the signature changes, and never opened by a copy without one") {
        try expect(KeychainAccessPolicy.shouldRewrite(storedMode: nil, wantedMode: "open"), "first launch of an ad-hoc build")
        try expect(KeychainAccessPolicy.shouldRewrite(storedMode: "open", wantedMode: "app:ABCDE12345"),
                   "the first signed build binds what an ad-hoc one left open")
        try expect(KeychainAccessPolicy.shouldRewrite(storedMode: "app:ABCDE12345", wantedMode: "app:ZZZZZ99999"),
                   "a different identity binds to itself")
        try expect(!KeychainAccessPolicy.shouldRewrite(storedMode: "app:ABCDE12345", wantedMode: "app:ABCDE12345"))
        try expect(!KeychainAccessPolicy.shouldRewrite(storedMode: "app:ABCDE12345", wantedMode: "open"),
                   "an unsigned copy must not open tokens a signed one bound, even with the password")
    }

    await run.test("a rewrite counts what it could not read, and a missing token is not a failure") {
        let github = TokenKey(account: "github")
        let gitlab = TokenKey(account: "gitlab")
        let nothing = TokenKey(account: "github.unused")

        let clean = KeychainAccessPolicy.rewrite(
            keys: [github, gitlab, nothing],
            in: InMemoryTokenStore(tokens: [github: "ghp_x", gitlab: "glpat_y"])
        )
        try expectEqual(clean, KeychainAccessPolicy.Rewrite(rewritten: 2, failed: 0))
        try expect(clean.isComplete)

        let refused = KeychainAccessPolicy.rewrite(
            keys: [github, gitlab],
            in: RefusingTokenStore(tokens: [github: "ghp_x", gitlab: "glpat_y"], refusing: ["gitlab"])
        )
        try expectEqual(refused, KeychainAccessPolicy.Rewrite(rewritten: 1, failed: 1))
        try expect(!refused.isComplete, "a dismissed prompt leaves the mode unrecorded, so the next launch finishes")
    }

    await run.test("a signed app accepts only a build signed by the same hand") {
        let mine = CodeIdentity.Kind.signed(identity: "ABCDE12345")
        try expect(UpdateCheck.trusts(update: mine, running: mine))
        try expect(!UpdateCheck.trusts(update: .signed(identity: "ZZZZZ99999"), running: mine),
                   "somebody else's Developer ID is somebody else's app")
        try expect(!UpdateCheck.trusts(update: .adHoc, running: mine),
                   "an unsigned build must not replace a signed one")
    }

    await run.test("an ad-hoc app has nothing to compare against and takes what the plist says") {
        try expect(UpdateCheck.trusts(update: .adHoc, running: .adHoc))
        try expect(UpdateCheck.trusts(update: .signed(identity: "ABCDE12345"), running: .adHoc),
                   "moving from ad-hoc to signed is exactly the update this is for")
    }
}
