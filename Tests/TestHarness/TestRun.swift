import Foundation

/// A failed expectation. Assertions throw, so a test stops at its first bad expectation
/// instead of cascading into unrelated failures.
public struct TestFailure: Error, Sendable {
    public let message: String
    public let file: String
    public let line: UInt

    public init(message: String, file: String, line: UInt) {
        self.message = message
        self.file = file
        self.line = line
    }
}

/// The whole test framework.
///
/// XCTest and swift-testing both require a full Xcode install, which this project does not
/// have (see docs/adr/0002-spm-only-toolchain.md). This is the smallest thing that still
/// gives named tests, async support and a non-zero exit code for CI.
public final class TestRun: @unchecked Sendable {
    private var passed = 0
    private var skipped = 0
    private var failures: [String] = []
    private var currentSection = ""
    /// Words from the command line. A section runs when its name contains any of them, so
    /// `./run-tests.sh projects` runs the five project sections and nothing else. Empty means
    /// everything, which is what CI and the pre-commit run want.
    private let filters: [String]
    private var isSectionActive = true

    public init(arguments: [String] = Array(CommandLine.arguments.dropFirst())) {
        filters = arguments.map { $0.lowercased() }
    }

    public func section(_ name: String) {
        currentSection = name
        isSectionActive = filters.isEmpty || filters.contains { name.lowercased().contains($0) }
        if isSectionActive { print("\n\(name)") }
    }

    public func test(_ name: String, _ body: () async throws -> Void) async {
        guard isSectionActive else {
            skipped += 1
            return
        }
        do {
            try await body()
            passed += 1
            print("  ok   \(name)")
        } catch let failure as TestFailure {
            let location = "\((failure.file as NSString).lastPathComponent):\(failure.line)"
            failures.append("\(currentSection) › \(name) - \(failure.message) [\(location)]")
            print("  FAIL \(name) - \(failure.message) [\(location)]")
        } catch {
            failures.append("\(currentSection) › \(name) - threw \(error)")
            print("  FAIL \(name) - threw \(error)")
        }
    }

    /// Prints the summary and exits with 1 if anything failed, so `./run-tests.sh` and any
    /// build script can rely on the status code alone.
    public func finish() -> Never {
        let note = skipped > 0 ? ", \(skipped) skipped by filter" : ""
        print("\n\(passed) passed, \(failures.count) failed\(note)")
        for failure in failures {
            print("  · \(failure)")
        }
        exit(failures.isEmpty ? 0 : 1)
    }
}
