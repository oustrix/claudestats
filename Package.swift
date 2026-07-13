// swift-tools-version: 6.0
import PackageDescription

// Swift 6.2 "approachable concurrency" upcoming features, applied to every target. These are
// shipped, source-compatible-once-adopted changes that become default in a future language mode;
// enabling them now surfaces real data-race and existential costs early rather than at the next
// major-version jump.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "ClaudeStats",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "ClaudeStatsCore", swiftSettings: swiftSettings),
        // Everything the app is made of except the @main entry point. A library so a test target can
        // import it — an executable target cannot be cleanly @testable-imported.
        .target(
            name: "ClaudeStatsAppLib",
            dependencies: ["ClaudeStatsCore"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "ClaudeStatsApp",
            dependencies: ["ClaudeStatsAppLib"],
            swiftSettings: swiftSettings
        ),
        // A command-line view of the same aggregation the dashboard draws, so the app's numbers can
        // be cross-checked against an independent tool.
        .executableTarget(
            name: "ClaudeStatsDump",
            dependencies: ["ClaudeStatsCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ClaudeStatsCoreTests",
            dependencies: ["ClaudeStatsCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ]
)
