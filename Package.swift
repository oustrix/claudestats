// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeStats",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "ClaudeStatsCore"),
        .executableTarget(
            name: "ClaudeStatsApp",
            dependencies: ["ClaudeStatsCore"]
        ),
        // A command-line view of the same aggregation the dashboard draws, so the app's numbers can
        // be cross-checked against an independent tool.
        .executableTarget(
            name: "ClaudeStatsDump",
            dependencies: ["ClaudeStatsCore"]
        ),
        .testTarget(
            name: "ClaudeStatsCoreTests",
            dependencies: ["ClaudeStatsCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
