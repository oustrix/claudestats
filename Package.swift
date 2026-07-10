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
        .testTarget(
            name: "ClaudeStatsCoreTests",
            dependencies: ["ClaudeStatsCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
