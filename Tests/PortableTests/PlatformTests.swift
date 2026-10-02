import DevDeckCore
import Foundation
import ProjectKit
import TestHarness

func runPlatformTests(_ run: TestRun) async {
    run.section("Platform boundaries")

    await run.test("a WSL default token store cannot silently persist a credential") {
        let store = CompositeTokenStore.standard()
        let error = try await expectThrows { try store.setToken("test-only", for: .github) }
        try expectEqual(error as? TokenStoreError, .readOnly)
    }

    await run.test("WSL does not advertise a virtual interface as a phone LAN address") {
        try expectEqual(LocalAddress.addresses(), [])
    }

    await run.test("detached starts use the selected Linux shell") {
        let command = LocalProjectService.detachedCommand("echo hello", log: URL(fileURLWithPath: "/tmp/demo.log"), pidFile: URL(fileURLWithPath: "/tmp/demo.pid"))
        try expect(command.contains("nohup \(ShellCommandRunner.defaultShell) -lc"))
        try expect(!ShellPath.fallback.contains("homebrew"))
    }
}
