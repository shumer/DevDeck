import DevDeckCore
import Foundation
import TestHarness

// The suite is an executable rather than an XCTest bundle - see docs/adr/0002-spm-only-toolchain.md.
let run = TestRun()

// Every expectation in the suite is written in English, so the tables are read from the
// repository and pointed at English before anything asks for a word.
Strings.use(.english, lookingIn: localisationRoot)

await runNetworkingTests(run)
await runConfigurationTests(run)
await runGitHubTests(run)
await runGitLabTests(run)
await runInboxTests(run)
await runActionsTests(run)
await runAccountsTests(run)
await runPresentationTests(run)
await runArcTests(run)
await runDDEVTests(run)
await runVectorTests(run)
await runProjectTests(run)
await runCommandRunnerTests(run)
await runDeckTests(run)
await runUpdateTests(run)
await runIdentityTests(run)
await runCheckSummaryTests(run)
await runLocalisationTests(run)
await runAttentionTests(run)

run.finish()
