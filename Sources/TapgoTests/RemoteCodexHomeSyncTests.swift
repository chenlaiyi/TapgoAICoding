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
    let wrapper = RemoteCodexHomeSync.remoteHarnessWrapper(remoteHome: "/Users/remoteuser/.tapgo-aicoding/remote")
    t.expect(wrapper.contains("codex --version"),
             "wrapper checks the actual remote codex binary version")
    t.expect(wrapper.contains("required=\(RemoteCodexHomeSync.minimumHarnessVersion)"),
             "wrapper enforces the supported remote protocol floor")
    if let versionCheck = wrapper.range(of: "codex --version"),
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

/// v0.5.109 回归：npm 版 /opt/homebrew/bin/codex 是 `#!/usr/bin/env node`
/// 脚本。GUI 启动的 App 只有最小 PATH，`env node` 解析不到就以 127 退出，
/// 设置页恒报“Codex CLI 版本过旧或无法识别”。这里用注入的最小 PATH 模拟
/// GUI 环境，断言 HarnessChildEnvironment 注入后版本探测依然成功。
@MainActor
func runRemoteCodexHomeSyncVersionCheckMinimalPath(_ t: TestRunner) {
    let harnessPath = RemoteCodexHomeSync.findHarness()
    guard !harnessPath.isEmpty else {
        t.expect(false, "findHarness locates a codex binary on this machine")
        return
    }

    let guiEnv = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": NSHomeDirectory(),
    ]
    let injected = HarnessChildEnvironment.make(base: guiEnv)
    t.expect(injected["PATH"]?.hasPrefix("/opt/homebrew/bin:") == true,
             "injected env puts /opt/homebrew/bin at the front of PATH")
    t.expect(injected["PATH"]?.contains("\(NSHomeDirectory())/.local/bin") == true,
             "injected env keeps ~/.local/bin on PATH")

    let version = RemoteCodexHomeSync.supportedHarnessVersion(
        at: harnessPath,
        baseEnvironment: guiEnv
    )
    t.expect(version != nil,
             "version check succeeds even with a GUI-minimal base PATH (npm codex resolves node via injected PATH); got \(version ?? "nil") at \(harnessPath)")
}
