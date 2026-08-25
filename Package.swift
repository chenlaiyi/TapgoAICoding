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
    ],
    targets: [
        // Pure logic: model + services that don't need AppKit/SwiftUI.
        // Shared by both the main app and the test runner so we test the
        // *real* code instead of a hand-written copy.
        .target(
            name: "TapgoCore",
            path: "Sources/TapgoCore"
        ),
        // The macOS app.
        .executableTarget(
            name: "TapgoAICoding",
            dependencies: ["TapgoCore"],
            path: "Sources/TapgoAICoding"
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
