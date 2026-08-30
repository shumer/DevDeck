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
        .library(name: "ArcKit", targets: ["ArcKit"]),
        .library(name: "DDEVKit", targets: ["DDEVKit"]),
        .library(name: "ProjectKit", targets: ["ProjectKit"]),
        .library(name: "DevDeckUI", targets: ["DevDeckUI"]),
        .executable(name: "DevDeck", targets: ["DevDeckApp"]),
    ],
    targets: [
        // Pure logic: configuration, networking, secrets. No AppKit, so the test
        // runner can exercise all of it head-less.
        .target(name: "DevDeckCore"),

        // GitHub integration: GraphQL queries, models, card snapshots.
        .target(name: "GitHubKit", dependencies: ["DevDeckCore"]),

        // Arc XP integration: projects, their links and their local Fusion stack.
        .target(name: "ArcKit", dependencies: ["DevDeckCore"]),

        // DDEV integration: projects, their state and their containers.
        .target(name: "DDEVKit", dependencies: ["DevDeckCore"]),

        // Projects that are neither: a folder, a command and a health URL.
        .target(name: "ProjectKit", dependencies: ["DevDeckCore"]),

        // SwiftUI card views shared by the desktop panels and any future surface.
        .target(
            name: "DevDeckUI",
            dependencies: ["DevDeckCore", "GitHubKit", "ArcKit", "DDEVKit", "ProjectKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // The AppKit shell: borderless panels, menu bar, placement and locking.
        .executableTarget(
            name: "DevDeckApp",
            dependencies: ["DevDeckCore", "GitHubKit", "ArcKit", "DDEVKit", "ProjectKit", "DevDeckUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Renders the menu-bar icon to a PNG. A 15-point drawing cannot be judged from source.
        .executableTarget(
            name: "IconPreview",
            dependencies: ["DevDeckUI"],
            path: "Tools/IconPreview",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Renders the application icon into an .iconset for `iconutil`, called by build.sh.
        .executableTarget(
            name: "AppIconExport",
            dependencies: ["DevDeckUI"],
            path: "Tools/AppIconExport",
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
            // DevDeckUI is here for the card-sizing arithmetic, which the panels depend on
            // being right and which is plain maths rather than anything drawn.
            dependencies: ["DevDeckCore", "GitHubKit", "ArcKit", "DDEVKit", "ProjectKit", "DevDeckUI", "TestHarness"],
            path: "Tests/DevDeckTests"
        ),
    ]
)
