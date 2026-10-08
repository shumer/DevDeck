// swift-tools-version: 6.0
import PackageDescription

// Language modes are split on purpose: the headless layers run under Swift 6 strict
// concurrency, while the AppKit/SwiftUI shell stays on the 5 mode where main-actor
// isolation of the framework types is inferred rather than enforced.
// See docs/adr/0002-spm-only-toolchain.md.
#if os(Windows)
let package = Package(
    name: "DevDeck",
    defaultLocalization: "en",
    products: [
        .library(name: "DevDeckCore", targets: ["DevDeckCore"]),
        .library(name: "GitHubKit", targets: ["GitHubKit"]),
        .library(name: "ProjectKit", targets: ["ProjectKit"]),
        .library(name: "DevDeckEngine", targets: ["DevDeckEngine"]),
        .executable(name: "DevDeckEngineHost", targets: ["DevDeckEngineHost"]),
        .executable(name: "DevDeckProcessHost", targets: ["DevDeckProcessHost"]),
    ],
    targets: [
        .target(
            name: "DevDeckCore",
            exclude: ["Process/ShellPath.swift", "Process/LocalAddress.swift"]
        ),
        .target(name: "GitHubKit", dependencies: ["DevDeckCore"]),
        .target(name: "ProjectKit", dependencies: ["DevDeckCore"]),
        .target(name: "DevDeckEngine", dependencies: ["DevDeckCore", "GitHubKit", "ProjectKit"]),
        .target(
            name: "DevDeckLocalization", path: "Resources/Localizations",
            sources: ["LocalizationResources.swift"],
            resources: [.copy("en.lproj"), .copy("ru.lproj"), .copy("de.lproj"), .copy("it.lproj"), .copy("es.lproj"), .copy("fr.lproj")]
        ),
        .executableTarget(name: "DevDeckEngineHost", dependencies: ["DevDeckCore", "DevDeckEngine", "DevDeckLocalization"]),
        .executableTarget(name: "DevDeckProcessHost", dependencies: ["DevDeckCore"]),
        .executableTarget(name: "DevDeckWindowsSmoke", dependencies: ["DevDeckCore", "DevDeckEngine"], path: "Tools/WindowsLifecycle"),
        .executableTarget(name: "DevDeckEngineTests", dependencies: ["DevDeckCore", "DevDeckEngine", "DevDeckLocalization", "ProjectKit", "TestHarness"], path: "Tests/EngineTests"),
        .executableTarget(
            name: "DevDeckWSLSmoke",
            dependencies: ["DevDeckCore", "ProjectKit", "DevDeckEngine"],
            path: "Tools/Smoke/WSLLifecycle"
        ),
        .executableTarget(
            name: "DevDeckNetworkSmoke", dependencies: ["DevDeckCore", "GitHubKit"],
            path: "Tools/Smoke/Network"
        ),
        .target(name: "TestHarness", dependencies: ["DevDeckCore"], path: "Tests/TestHarness"),
        .executableTarget(
            name: "DevDeckWindowsCoreTests",
            dependencies: ["DevDeckCore", "GitHubKit", "ProjectKit", "DevDeckEngine", "TestHarness"],
            path: "Tests/WindowsCoreTests"
        ),
    ]
)
#else
let package = Package(
    name: "DevDeck",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DevDeckCore", targets: ["DevDeckCore"]),
        .library(name: "GitHubKit", targets: ["GitHubKit"]),
        .library(name: "ArcKit", targets: ["ArcKit"]),
        .library(name: "DDEVKit", targets: ["DDEVKit"]),
        .library(name: "ProjectKit", targets: ["ProjectKit"]),
        .library(name: "DevDeckEngine", targets: ["DevDeckEngine"]),
        .executable(name: "DevDeckEngineHost", targets: ["DevDeckEngineHost"]),
        .library(name: "DevDeckUI", targets: ["DevDeckUI"]),
        .executable(name: "DevDeck", targets: ["DevDeckApp"]),
    ],
    targets: [
        // Pure logic: configuration, networking, secrets. No AppKit, so the test
        // runner can exercise all of it head-less.
        // Three deprecated Keychain calls live in C, where a pragma can say they are
        // deliberate; Swift cannot silence a deprecation at a call site and this project's CI
        // fails on warnings.
        .target(name: "KeychainACL"),
        .target(name: "DevDeckCore", dependencies: ["KeychainACL"]),

        // GitHub integration: GraphQL queries, models, card snapshots.
        .target(name: "GitHubKit", dependencies: ["DevDeckCore"]),

        // Arc XP integration: projects, their links and their local Fusion stack.
        .target(name: "ArcKit", dependencies: ["DevDeckCore"]),

        // DDEV integration: projects, their state and their containers.
        .target(name: "DDEVKit", dependencies: ["DevDeckCore"]),

        // Projects that are neither: a folder, a command and a health URL.
        .target(name: "ProjectKit", dependencies: ["DevDeckCore"]),
        .target(name: "DevDeckEngine", dependencies: ["DevDeckCore", "GitHubKit", "ProjectKit"]),
        .target(
            name: "DevDeckLocalization", path: "Resources/Localizations",
            sources: ["LocalizationResources.swift"],
            resources: [.copy("en.lproj"), .copy("ru.lproj"), .copy("de.lproj"), .copy("it.lproj"), .copy("es.lproj"), .copy("fr.lproj")]
        ),
        .executableTarget(name: "DevDeckEngineHost", dependencies: ["DevDeckCore", "DevDeckEngine", "DevDeckLocalization"]),
        .executableTarget(name: "DevDeckEngineTests", dependencies: ["DevDeckCore", "DevDeckEngine", "DevDeckLocalization", "ProjectKit", "TestHarness"], path: "Tests/EngineTests"),

        // SwiftUI card views shared by the desktop panels and any future surface.
        .target(
            name: "DevDeckUI",
            dependencies: ["DevDeckCore", "GitHubKit", "GitLabKit", "ArcKit", "DDEVKit", "ProjectKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .target(
            name: "GitLabKit",
            dependencies: ["DevDeckCore"]
        ),

        // The AppKit shell: borderless panels, menu bar, placement and locking.
        .executableTarget(
            name: "DevDeckApp",
            dependencies: ["DevDeckCore", "GitHubKit", "GitLabKit", "ArcKit", "DDEVKit", "ProjectKit", "DevDeckUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Renders the menu-bar icon to a PNG. A 15-point drawing cannot be judged from source.
        .executableTarget(
            name: "IconPreview",
            dependencies: ["DevDeckUI"],
            path: "Tools/IconPreview",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Renders every card mark at the size a card draws it. Same reason as IconPreview.
        .executableTarget(
            name: "GlyphPreview",
            dependencies: ["DevDeckUI"],
            path: "Tools/GlyphPreview",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Live check against the real API, run by scripts/smoke-test.sh.
        .executableTarget(
            name: "DevDeckSmoke",
            dependencies: ["DevDeckCore", "GitHubKit", "GitLabKit"],
            path: "Tools/Smoke",
            exclude: ["WSLLifecycle", "Network", "Invoke-NetworkSmoke.ps1"]
        ),

        // Minimal test framework. XCTest and swift-testing both need a full Xcode
        // install, which this toolchain does not have.
        .target(name: "TestHarness", dependencies: ["DevDeckCore"], path: "Tests/TestHarness"),

        // The suite itself: a plain executable that exits non-zero on failure.
        .executableTarget(
            name: "DevDeckTests",
            // DevDeckUI is here for the card-sizing arithmetic, which the panels depend on
            // being right and which is plain maths rather than anything drawn.
            dependencies: ["DevDeckCore", "GitHubKit", "GitLabKit", "ArcKit", "DDEVKit", "ProjectKit", "DevDeckUI", "TestHarness"],
            path: "Tests/DevDeckTests"
        ),
    ]
)
#endif
