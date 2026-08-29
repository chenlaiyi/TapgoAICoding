// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapgoAICoding",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TapgoAICoding", targets: ["TapgoAICoding"]),
        .executable(name: "TapgoTests", targets: ["TapgoTests"]),
        .executable(name: "TapgoComputerUseMCP", targets: ["TapgoComputerUseMCP"]),
    ],
    targets: [
        // Pure logic: model + services that don't need AppKit/SwiftUI.
        // Shared by both the main app and the test runner so we test the
        // *real* code instead of a hand-written copy.
        .target(
            name: "TapgoCore",
            path: "Sources/TapgoCore"
        ),
        // Computer-use primitives (screenshot / CGEvent input) shared by the
        // app (PhoneRemote) and the MCP server binary. Needs AppKit, so it
        // sits between TapgoCore (pure Foundation) and the UI targets.
        .target(
            name: "TapgoComputerUse",
            dependencies: ["TapgoCore"],
            path: "Sources/TapgoComputerUse"
        ),
        // The macOS app.
        .executableTarget(
            name: "TapgoAICoding",
            dependencies: ["TapgoCore", "TapgoComputerUse"],
            path: "Sources/TapgoAICoding"
        ),
        // MCP stdio server exposing computer-use tools to the model. Spawned
        // by the codex harness (registered in the isolated Codex home's
        // config.toml), never shipped inside the app's own process.
        .executableTarget(
            name: "TapgoComputerUseMCP",
            dependencies: ["TapgoComputerUse"],
            path: "Sources/TapgoComputerUseMCP"
        ),
        // Standalone test runner. We do not use XCTest / swift-testing
        // because the CommandLineTools SDK on this machine ships neither
        // framework. `swift run TapgoTests` is the canonical test
        // command. Returns non-zero on any assertion failure.
        .executableTarget(
            name: "TapgoTests",
            dependencies: ["TapgoCore"],
            path: "Sources/TapgoTests"
        ),
    ]
)
