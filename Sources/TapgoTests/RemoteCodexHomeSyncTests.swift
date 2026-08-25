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
}

@MainActor
func runRemoteCodexHomeSyncNoLiteralKey(_ t: TestRunner) {
    let config = RemoteCodexHomeSync.renderRemoteConfig()
    let wrapper = RemoteCodexHomeSync.remoteHarnessWrapper(remoteHome: "/Users/remoteuser/.tapgo-aicoding/remote")
    let combined = config + "\n" + wrapper
    t.expect(combined.contains("sk-cp-") == false,
             "no 'sk-cp-' prefix (API key marker) anywhere in the public API")
}
