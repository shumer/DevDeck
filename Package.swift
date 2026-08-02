// swift-tools-version: 6.0
import PackageDescription

// Language modes are split on purpose: the headless layers run under Swift 6 strict
// concurrency, while the AppKit/SwiftUI shell stays on the 5 mode where main-actor
// isolation of the framework types is inferred rather than enforced.
// See docs/adr/0002-spm-only-toolchain.md.
let package = Package(
    name: "DevDeck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DevDeckCore", targets: ["DevDeckCore"]),
        .library(name: "GitHubKit", targets: ["GitHubKit"]),
        .library(name: "DevDeckUI", targets: ["DevDeckUI"]),
        .executable(name: "DevDeck", targets: ["DevDeckApp"]),
    ],
    targets: [
        // Pure logic: configuration, networking, secrets. No AppKit, so the test
        // runner can exercise all of it head-less.
        .target(name: "DevDeckCore"),

        // GitHub integration: GraphQL queries, models, card snapshots.
        .target(name: "GitHubKit", dependencies: ["DevDeckCore"]),

        // SwiftUI card views shared by the desktop panels and any future surface.
        .target(
            name: "DevDeckUI",
            dependencies: ["DevDeckCore", "GitHubKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // The AppKit shell: borderless panels, menu bar, placement and locking.
        .executableTarget(
            name: "DevDeckApp",
            dependencies: ["DevDeckCore", "GitHubKit", "DevDeckUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Live check against the real API, run by scripts/smoke-test.sh.
        .executableTarget(
            name: "DevDeckSmoke",
            dependencies: ["DevDeckCore", "GitHubKit"],
            path: "Tools/Smoke"
        ),

        // Minimal test framework. XCTest and swift-testing both need a full Xcode
        // install, which this toolchain does not have.
        .target(name: "TestHarness", dependencies: ["DevDeckCore"], path: "Tests/TestHarness"),

        // The suite itself: a plain executable that exits non-zero on failure.
        .executableTarget(
            name: "DevDeckTests",
            dependencies: ["DevDeckCore", "GitHubKit", "TestHarness"],
            path: "Tests/DevDeckTests"
        ),
    ]
)
