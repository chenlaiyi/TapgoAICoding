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
        // stdio↔Unix-socket bridge daemon. Spawned by launchd (registered
        // via scripts/install-harness-daemon.sh) and shared across TapgoApp
        // restarts. Never linked into the app's own process — only the
        // Swift CLI binary.
        .executable(name: "TapgoHarness", targets: ["TapgoHarness"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        // Pure logic: model + services that don't need AppKit/SwiftUI.
        // Shared by both the main app and the test runner so we test the
        // *real* code instead of a hand-written copy.
        .target(
            name: "TapgoCore",
            path: "Sources/TapgoCore",
            resources: [
                .copy("Resources/PhoneRemote")
            ]
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
            dependencies: [
                "TapgoCore",
                "TapgoComputerUse",
                .product(name: "Sparkle", package: "Sparkle")
            ],
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
        // Harness bridge daemon. Single `main.swift` (193 lines, only
        // `import Foundation` + `import Darwin`). Spawns `codex app-server`
        // and bridges its stdio to a Unix domain socket that the app
        // talks to via `SocketHarnessTransport`. Independent of the
        // TapgoComputerUse tree.
        .executableTarget(
            name: "TapgoHarness",
            path: "Sources/TapgoHarness"
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
