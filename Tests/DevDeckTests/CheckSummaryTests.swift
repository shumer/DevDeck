import ArcKit
import DevDeckCore
import Foundation
import ProjectKit
import TestHarness

func runCheckSummaryTests(_ run: TestRun) async {
    run.section("Settings - what a check says")

    let at = Date(timeIntervalSince1970: 1_800_000_000)

    await run.test("an answer is only shown next to the address it answered for") {
        let status = LocalProjectStatus(state: .stopped, detail: "http://localhost:8080 answered 404", checkedAt: at)
        let same = status.summary(checkedURL: "http://localhost:8080", currentURL: "http://localhost:8080")
        try expectEqual(same.state, "Stopped")
        try expectEqual(same.detail, "http://localhost:8080 answered 404")

        let changed = status.summary(checkedURL: "http://localhost:8080", currentURL: "http://localhost:3000")
        try expectEqual(changed.state, "Not checked", "a refusal from 8080 must not sit next to 3000")
        try expectEqual(changed.tone, .idle)
    }

    await run.test("each state of a plain project reads as a word and a detail") {
        let running = LocalProjectStatus(state: .running, checkedAt: at).summary(checkedURL: "u", currentURL: "u")
        try expectEqual(running.tone, .good)
        try expectEqual(running.state, "Running")
        try expect(running.detail.hasPrefix("answered at "), running.detail)

        let starting = LocalProjectStatus(state: .starting).summary(checkedURL: "u", currentURL: "u")
        try expectEqual(starting.tone, .busy)
        try expectEqual(starting.detail, "process up, not answering yet")

        let noURL = LocalProjectStatus(state: .stopped, checkedAt: at).summary(checkedURL: "", currentURL: "")
        try expectEqual(noURL.detail, "nothing started from here", "with no address there is nothing to have answered")

        let unconfigured = LocalProjectStatus.unavailable.summary(checkedURL: "", currentURL: "")
        try expectEqual(unconfigured.state, "Not configured")
    }

    await run.test("an Arc stack reads the same way, by the same rule") {
        let stopped = LocalStackStatus(state: .stopped, checkedAt: at)
        try expectEqual(stopped.summary(checkedAddress: "a", currentAddress: "a").state, "Stopped")
        try expectEqual(stopped.summary(checkedAddress: "a", currentAddress: "b").state, "Not checked")
        try expectEqual(LocalStackStatus(state: .running, detail: "engine 7.0.2", checkedAt: at)
            .summary(checkedAddress: "a", currentAddress: "a").detail, "engine 7.0.2")
    }
}
