import DevDeckCore
import Foundation
import TestHarness

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
