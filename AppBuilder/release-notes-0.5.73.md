# Tapgo AICoding 0.5.73

- Harness daemon 解耦：TapgoHarness daemon 二进制（Sources/TapgoHarness/main.swift，193 行 stdio↔Unix socket bridge）+ HarnessDaemonLauncher（自启动逻辑）+ SocketHarnessTransport（App 端连接）正式入仓。
  - `SessionStore.makeRunner(for:)` 在 `HarnessDaemonLauncher.ensureDaemonRunning` 成功时优先 `SocketHarnessTransport`；失败降级到 `LocalHarnessTransport` 并记日志。
  - `Package.swift` 注册 `TapgoHarness` target + product；`build-app.sh` 链路完整（依赖只是 Foundation + Darwin）。
- launchd 守护脚本进仓：`scripts/install-harness-daemon.sh` + `scripts/uninstall-harness-daemon.sh` + `launchd/com.tapgo.aicoding.harness.plist`。plist template 同步 v0.5.72 手动部署的 `KeepAlive = { SuccessfulExit=false; ThrottleInterval=2 }` 改进，注释里的 `launchctl load -w` 改成现代 `bootstrap` / `kickstart` / `bootout`。
- 5 个新单元测试（2 Socket + 3 Launcher）全绿：
  - `SocketHarnessTransport: start fails when socket absent`
  - `SocketHarnessTransport: start + send round-trips to listening peer`
  - `HarnessDaemonLauncher: returns true when launcher socket file exists`
  - `HarnessDaemonLauncher: socketPath is the well-known Application Support path`
  - `HarnessDaemonLauncher: daemonBinaryPath resolves to installed binary`
**Why**: evolver 留下的整套 harness 解耦代码之前没进 git，且 `SessionStore.makeRunner` 仍走 `LocalHarnessTransport`，App 没真正用上 daemon（daemon 在本机 v0.5.72 之前已经手动部署 + launchd 守护跑着，但 App 端永远走 stdio）。本版本把链路补齐。
**Next**: `daemonBinaryPath` 是 `static let` — 没法用 env var 在测试里 redirect；后续如需更细测试覆盖，把 daemon binary lookup 改成非 static（带 env var 支持）。中长期「自动化」面板（v0.5.70 Next）。
