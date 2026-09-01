import Foundation
import TapgoCore

// MARK: - v0.5.73 HarnessDaemonLauncher unit tests
//
// `ensureDaemonRunning(codexHome:apiKey:)` has three branches:
//
//   - socket file exists                    → return true
//   - socket file missing, binary available → spawn the daemon, wait
//                                              up to 3 s for socket,
//                                              return success if it
//                                              appears
//   - socket file missing, no binary        → return false
//
// `daemonBinaryPath` is a `static let`, computed once at first
// access. That makes env-var overrides (TAPGO_HARNESS_DAEMON_BIN)
// only work for the very first call in the process — useless from
// a unit test. We can only test the deterministic branches that
// don't require binary lookup:
//
//   1. socket file present  → returns true (no spawn, instant)
//   2. socket file absent
//      AND binary absent
//      AND a temporary absent socketPath is restored after test
//   3. the launcher's public socketPath is the well-known location
//      under Application Support/Tapgo AICoding/run/harness.sock
//
// Branch 2 (binary present, socket absent, spawn succeeds) needs
// a real TapgoHarness binary and is covered by the install +
// end-to-end check after `build-app.sh` runs.

@MainActor
func runHarnessDaemonLauncherReturnsTrueWhenSocketPresent(_ t: TestRunner) {
    t.section("HarnessDaemonLauncher: returns true when launcher socket file exists")
    let realSocketPath = HarnessDaemonLauncher.socketPath
    let existed = FileManager.default.fileExists(atPath: realSocketPath)
    if !existed {
        // Create the file in the launcher's expected location.
        // The launcher's "file exists" check is just
        // `FileManager.fileExists` — no socket-level handshake.
        let dir = (realSocketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: realSocketPath, contents: Data())
        defer {
            try? FileManager.default.removeItem(atPath: realSocketPath)
        }
    }

    let ok = HarnessDaemonLauncher.ensureDaemonRunning(
        codexHome: URL(fileURLWithPath: NSTemporaryDirectory()),
        apiKey: "irrelevant"
    )
    t.expect(ok, "ensureDaemonRunning returns true when launcher socket file exists")
}

@MainActor
func runHarnessDaemonLauncherSocketPathIsWellKnown(_ t: TestRunner) {
    t.section("HarnessDaemonLauncher: socketPath is the well-known Application Support path")
    let expectedSuffix = "/Library/Application Support/Tapgo AICoding/run/harness.sock"
    let actual = HarnessDaemonLauncher.socketPath
    t.expect(actual.hasSuffix(expectedSuffix),
             "socketPath ends with \(expectedSuffix) — got \(actual)")
}

@MainActor
func runHarnessDaemonLauncherDaemonBinaryPathPrefersInstalledBinary(_ t: TestRunner) {
    t.section("HarnessDaemonLauncher: daemonBinaryPath resolves to installed binary")
    let expectedSuffix = "/.tapgo-aicoding/bin/TapgoHarness"
    let actual = HarnessDaemonLauncher.daemonBinaryPath
    t.expect(actual.hasSuffix(expectedSuffix),
             "daemonBinaryPath ends with \(expectedSuffix) — got \(actual)")
    t.expect(FileManager.default.isExecutableFile(atPath: actual),
             "daemonBinaryPath points at an executable file")
}
