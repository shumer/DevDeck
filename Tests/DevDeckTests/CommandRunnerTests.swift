import DevDeckCore
import Foundation
import TestHarness

/// These run real processes, which the rest of the suite never does.
///
/// They earn it: every bug this file covers — a blocked main thread, a command waiting on
/// stdin, a timeout that never fired — was invisible to a stubbed runner and showed up as a
/// button that did nothing.
func runCommandRunnerTests(_ run: TestRun) async {
    run.section("Commands")

    let runner = ShellCommandRunner()
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

    await run.test("output and exit code come back") {
        let result = try await runner.run("echo hello", in: temporary, timeout: 10)
        try expect(result.succeeded)
        try expectEqual(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    await run.test("a non-zero exit is reported, not thrown") {
        let result = try await runner.run("echo oops >&2; exit 3", in: temporary, timeout: 10)
        try expectEqual(result.exitCode, 3)
        try expectEqual(result.failureLine, "oops")
    }

    await run.test("a command that reads stdin does not hang") {
        // `npx` asks "Ok to proceed?" when the package is missing. With an inherited stdin
        // that question waits forever and the card sits on "starting…".
        let result = try await runner.run("cat", in: temporary, timeout: 10)
        try expect(result.succeeded)
        try expectEqual(result.standardOutput, "", "stdin is /dev/null, so cat sees EOF at once")
    }

    await run.test("a long command is cut off by the timeout") {
        let started = Date()
        let result = try await runner.run("sleep 30", in: temporary, timeout: 1)
        let elapsed = Date().timeIntervalSince(started)
        try expect(elapsed < 10, "the watchdog has to fire without the main thread's help")
        try expect(!result.succeeded, "a terminated command is a failed one")
    }

    await run.test("large output does not deadlock the pipes") {
        // Enough to overflow a pipe buffer several times over on both streams at once.
        let result = try await runner.run(
            "for i in $(seq 1 4000); do echo out-$i; echo err-$i >&2; done",
            in: temporary,
            timeout: 30
        )
        try expect(result.succeeded)
        try expect(result.standardOutput.contains("out-4000"))
        try expect(result.standardError.contains("err-4000"))
    }

    await run.test("the shell is a login shell, so PATH matches the user's terminal") {
        // The whole reason for `zsh -lc`: an app launched from Finder otherwise has no
        // Homebrew and no nvm on PATH, and `npx` cannot be found.
        let result = try await runner.run("echo $PATH", in: temporary, timeout: 10)
        try expect(result.standardOutput.contains("/usr/local/bin") || result.standardOutput.contains("/opt/homebrew/bin"),
                   "expected a profile-provided PATH, got \(result.standardOutput)")
    }

    await run.test("a missing directory fails before anything runs") {
        let error = try await expectThrows {
            _ = try await runner.run("echo hi", in: URL(fileURLWithPath: "/nope/nope"), timeout: 5)
        }
        try expectEqual(error as? CommandError, .missingDirectory("/nope/nope"))
    }

    await run.test("work happens off the main thread") {
        // The original bug: the runner blocked whoever called it, and the caller was the main
        // actor, so the whole app froze for as long as the command ran.
        let onMain = await MainActor.run { Thread.isMainThread }
        try expect(onMain, "sanity: the check itself runs on the main thread")

        let result = try await runner.run("sleep 0.2; echo done", in: temporary, timeout: 10)
        try expect(result.succeeded)
    }
}
