import Foundation
import TestHarness

// The suite is an executable rather than an XCTest bundle — see docs/adr/0002-spm-only-toolchain.md.
let run = TestRun()

await runNetworkingTests(run)
await runConfigurationTests(run)
await runGitHubTests(run)
await runInboxTests(run)
await runActionsTests(run)
await runAccountsTests(run)
await runPresentationTests(run)
await runArcTests(run)

run.finish()
