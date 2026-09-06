// TapgoTests/RemoteCodexHomeSyncTests.swift
import Foundation
import TapgoCore

@MainActor
func runRemoteCodexHomeSyncConfigNoSecret(_ t: TestRunner) {
    let config = RemoteCodexHomeSync.renderRemoteConfig()
    t.expect(config.contains("sk-cp-") == false,
             "rendered config does NOT embed the literal API key value")
    t.expect(config.contains("env_key = \"OPENAI_API_KEY\""),
             "rendered config references env_key = \"OPENAI_API_KEY\" so the harness can read it from the env at runtime")
    t.expect(config.contains("MiniMax-M3"), "rendered config pins model = MiniMax-M3")
    t.expect(config.contains("minimax"), "rendered config pins provider = minimax")
    t.expect(config.contains("https://api.minimaxi.com/v1"),
             "rendered config pins the correct base_url")
    t.expect(config.contains("wire_api = \"responses\""),
             "rendered config uses the responses wire API")
    t.expect(config.contains("auth.json") == false,
             "rendered config does not reference an auth.json file path (the key is delivered at runtime)")
    t.expectEqual(
        RemoteCodexHomeSync.parseHarnessVersion("codex-cli 0.150.1"),
        [0, 150, 1],
        "harness version: parses current CLI output"
    )
    t.expect(RemoteCodexHomeSync.isSupportedHarnessVersion([0, 149, 1]),
             "harness version: minimum accepted")
    t.expect(RemoteCodexHomeSync.isSupportedHarnessVersion([0, 150, 1]),
             "harness version: newer accepted")
    t.expect(!RemoteCodexHomeSync.isSupportedHarnessVersion([0, 149, 0]),
             "harness version: older rejected")
    t.expectNil(RemoteCodexHomeSync.parseHarnessVersion("unknown"),
                "harness version: malformed rejected")
}

@MainActor
func runRemoteCodexHomeSyncTrustedProjects(_ t: TestRunner) {
    let configWithProjects = RemoteCodexHomeSync.renderRemoteConfig(
        trustedRemotePaths: ["/Users/remoteuser/workspaces"]
    )
    t.expect(configWithProjects.contains("/Users/remoteuser/workspaces"),
             "trusted remote path appears in config")
    t.expect(configWithProjects.contains("mirrors/remotehost__Users_remoteuser") == false,
             "local mirror path does NOT leak into the remote config")
}

@MainActor
func runRemoteCodexHomeSyncWrapper(_ t: TestRunner) {
    runRemoteWrapperExecution(t)
    let wrapper = RemoteCodexHomeSync.remoteHarnessWrapper(remoteHome: "/Users/remoteuser/.tapgo-aicoding/remote")
    t.expect(wrapper.contains(#""$TAPGO_CODEX" --version"#),
             "wrapper checks the actual remote codex binary version")
    t.expect(wrapper.contains("required=\(RemoteCodexHomeSync.minimumHarnessVersion)"),
             "wrapper enforces the supported remote protocol floor")
    if let versionCheck = wrapper.range(of: #""$TAPGO_CODEX" --version"#),
       let keyRead = wrapper.range(of: "IFS= read -r KEY") {
        t.expect(versionCheck.lowerBound < keyRead.lowerBound,
                 "wrapper validates the remote harness before reading the API key")
    } else {
        t.expect(false, "wrapper contains ordered version and key checks")
    }
    t.expect(wrapper.contains("IFS= read -r KEY"),
             "wrapper reads the API key from stdin (no on-disk source)")
    t.expect(wrapper.contains("export OPENAI_API_KEY=\"$KEY\""),
             "wrapper exports OPENAI_API_KEY from the read value")
    t.expect(wrapper.contains("unset KEY"),
             "wrapper unsets the temporary KEY var after exporting")
    t.expect(wrapper.contains("exec env CODEX_HOME="),
             "wrapper execs codex with CODEX_HOME set")
    t.expect(wrapper.contains("set -e"),
             "wrapper has set -e so a missing key aborts instead of silently launching")
    t.expect(wrapper.contains("app-server --listen stdio://"),
             "wrapper launches the codex app-server over stdio")
    t.expect(wrapper.contains("sk-cp-") == false,
             "wrapper does NOT embed any literal API key")
    let shellCheck = Process()
    shellCheck.executableURL = URL(fileURLWithPath: "/bin/sh")
    shellCheck.arguments = ["-n", "-c", wrapper]
    do {
        try shellCheck.run()
        shellCheck.waitUntilExit()
        t.expectEqual(shellCheck.terminationStatus, 0,
                      "wrapper is valid POSIX shell syntax")
    } catch {
        t.expect(false, "wrapper shell syntax check launches")
    }
}

@MainActor
func runRemoteCodexHomeSyncNoLiteralKey(_ t: TestRunner) {
    let config = RemoteCodexHomeSync.renderRemoteConfig()
    let wrapper = RemoteCodexHomeSync.remoteHarnessWrapper(remoteHome: "/Users/remoteuser/.tapgo-aicoding/remote")
    let combined = config + "\n" + wrapper
    t.expect(combined.contains("sk-cp-") == false,
             "no 'sk-cp-' prefix (API key marker) anywhere in the public API")
}

/// Execute the generated wrapper with a controlled CLI; checks quoting,
/// home expansion and cwd fail-closed behavior without any model request.
@MainActor
func runRemoteWrapperExecution(_ t: TestRunner) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("tapgo-wrapper-" + UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    do {
        let directory = root.appendingPathComponent("project")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let fake = root.appendingPathComponent("fake codex")
        try """
        #!/bin/sh
        if [ "$1" = --version ]; then echo 'codex-cli 0.153.4'; exit 0; fi
        printf 'harness-cwd=%s\\n' "$(pwd -P)"
        printf 'harness-home=%s\\n' "$CODEX_HOME"
        printf '%s\\n' "$@"
        """.write(to: fake, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        func run(_ path: String) throws -> (Int32, String) {
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.environment = ["HOME": root.path, "PATH": "/usr/bin:/bin"]
            shell.arguments = ["-c", RemoteCodexHomeSync.remoteHarnessWrapper(
                remoteHome: "~/isolated", codexPathOnRemote: fake.path, workingDirectory: path,
                runtimeOverrides: RemoteCodexHomeSync.runtimeOverrides(model: "a\"b", provider: "probe", baseURL: "https://example.com/v1", contextWindow: 200000))]
            let input = Pipe(), output = Pipe()
            shell.standardInput = input
            shell.standardOutput = output
            shell.standardError = output
            try shell.run()
            try input.fileHandleForWriting.write(contentsOf: Data("dummy-fixture\n".utf8))
            try input.fileHandleForWriting.close()
            shell.waitUntilExit()
            return (shell.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        let success = try run("~/project")
        t.expectEqual(success.0, 0, "wrapper starts the remote CLI")
        let actual = success.1.split(separator: "\n").first(where: { $0.hasPrefix("harness-cwd=") }).map { String($0.dropFirst("harness-cwd=".count)) } ?? ""
        t.expectEqual(URL(fileURLWithPath: actual).resolvingSymlinksInPath().path, directory.resolvingSymlinksInPath().path, "tilde cwd resolves on the remote shell")
        t.expect(success.1.contains("harness-home=" + root.path + "/isolated"), "isolated home resolves on remote")
        t.expect(success.1.contains("https://example.com/v1"), "provider URL uses TOML-compatible escaping")
        t.expect(!success.1.contains("dummy-fixture"), "key is not printed")
        let missing = try run("~/missing-project")
        t.expectEqual(missing.0, 5, "missing directory aborts before running the harness")
        t.expect(!missing.1.contains("harness-cwd="), "invalid cwd never falls back to home")
    } catch { t.expect(false, "wrapper execution: \(error.localizedDescription)") }
}
