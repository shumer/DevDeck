import DevDeckCore
import DevDeckWorkerProtocol
import Foundation
import TestHarness

let run = TestRun()
let resourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Localizations")
let workerLocalization = try WorkerStartupLocalization(originalRoot: resourceRoot)
try workerLocalization.use(.english)

await runNetworkingTests(run)
await runConfigurationTests(run)
await runGitHubTests(run)
await runGitLabTests(run)
await runActionsTests(run)
await runAccountsTests(run)
await runArcTests(run)
await runDDEVTests(run)
await runProjectTests(run)
await runUpdateTests(run)
await runIdentityTests(run)
await runCheckSummaryTests(run)
await runPlatformTests(run)
await runWorkerTests(run)
await runWorkerRemoteTests(run)
await runWorkerInboxAttentionTests(run)
await runWorkerAttentionTests(run)
await runWorkerVisibilityTests(run)
await runWorkerPowerOffTests(run)
await runWorkerPowerOffRaceTests(run)
await runWorkerCheckoutTests(run, localization: workerLocalization)
workerLocalization.close()
run.finish()
