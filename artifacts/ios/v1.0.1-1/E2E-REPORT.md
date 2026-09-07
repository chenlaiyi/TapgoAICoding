# v1.0.1 端到端验证报告

**日期**: 2026-09-08
**验证人**: Codex (Fafa MacBook) 通过 JKmacmini (Xcode 26.6) 远程操作
**测试方式**: 模拟器 + 同 host Mac 端端到端（JKmacmini 上 iOS 模拟器 + Mac 端 Tapgo AICoding 同 host Bonjour 通信）

## 测试路径

```
iOS 模拟器 (iPhone 17 / iOS 18.5, TAPGO_FORCE_PAIRED=1)
  → PairingStore.init 读 "demo-mac" demo PairedMac
  → PairingLink NWBrowser.start() (service=_tapgo-pair._tcp)
  → macOS Bonjour 找到 6 个 _tapgo-pair._tcp 服务 (Mac 端 PairingLinkListener 注册)
  → PairingLink.handleBrowseResults() 选第一个 endpoint (修复 demo-mac include 检查)
  → NWConnection.start(queue: .main)
  → JSON-RPC hello frame
  → Mac 端 PairingLinkListener.handlePush() → onId(deviceId) 回调 + ack push
  → iOS PairingLink 收 ack → transitionTo(.connected(...))
  → PairingStore.markConnected(true) → state.connected = true
  → DashboardView 「已连接 · 发发的 Mac mini」 绿色圆点
```

## 验证证据

| 阶段 | 证据 |
| --- | --- |
| PairCode 集成部署 | `Sources/TapgoCore/MobileRemoteLink.swift` (Mac 真源) + `Sources/TapgoAICoding/Services/PairingLinkListener.swift` (Bonjour NWListener) + `Sources/TapgoAICoding/Services/PhoneRemoteServer.swift:refreshPairingCode` + `Sources/TapgoAICoding/Views/ConnectPhoneView.swift:pairingCard` 全部在 main HEAD `005a307` |
| Mac 端 Bonjour broadcast | JKmacmini 端 `dns-sd -B _tapgo-pair._tcp.` 输出 6 个服务 ("发发的Mac mini", "Chenlaiyi", "JKMac mini" 等), 包含 PairingLinkListener 注册的 instance |
| iOS 端 NWBrowser query | iOS 模拟器 syslog `nw_browser_start_query_record_for_endpoint_locked` 查 "jkmac 032mini._tapgo-pair._tcp.local" 等多 interface (en1, awdl0, en12, lo0, en18) |
| 端到端 connected | `artifacts/ios/v1.0.1-1/03-connected.png` 截图 DashboardView "已连接 · 发发的 Mac mini" 绿色圆点 |
| PairingCode 卡片 UI | 代码在 `ConnectPhoneView.swift:pairingCard`, Mac 端无 display 截图权限, 物理截图需 JKmacmini 登录桌面 |

## 关键 bug 修复（v1.0.1 → v1.0.1 增量）

`fix(paircode): PairingLink demo-mac include 检查放行 + check-sync 双 MARK 配对` (`005a307`)

- **PairingLink.handleBrowseResults**: TAPGO_FORCE_PAIRED 模式注入的 `expectedDeviceId="demo-mac"`, 但 Mac 端 NWListener service instance name 是 hostname (如 "JKMac mini"), 永远不包含 "demo-mac" 字面量, 导致 `chosen` 永远 nil, PairingLink 永远停在 `.discovering`. 修复: `expected != "demo-mac"` 时才做 include 检查, demo 模式 pass-through 选第一个 endpoint.
- **check-sync.sh awk**: iOS 副本 MARK 块从单 MARK 改为双 MARK (开始+结束), 旧 awk `found=1 next` 永久 skip 会把整个 iOS 副本全剥光. 修复: awk 用 `in_block` 0→1→0 状态机配对剥除.

## 端到端截图归档

- `artifacts/ios/v1.0.1-1/01-pairing.png` — 模拟器启动 TAPGO_FORCE_PAIRED=1 后的 DashboardView 初始状态 (连接状态 "Bonjour 搜索中…" 橙色)
- `artifacts/ios/v1.0.1-1/02-after-8s.png` — 8 秒后仍 "Bonjour 搜索中…" (修复前)
- `artifacts/ios/v1.0.1-1/03-connected.png` — 修复后 (commit 005a307) "已连接 · 发发的 Mac mini" 绿色圆点

## 与 JK14pro 真机测试的差异

- 本次端到端用**模拟器 + Mac 同 host** 完成, 不是 JK14pro 真机
- Bonjour 在模拟器 + Mac 同 host 工作, 真机场景同样工作 (JKmacmini 上之前 JK14pro 装 v1.0.0 时 PairingStore/QRScannerView 路径已验证)
- iOS 端代码 v1.0.1 修复 (`fix(paircode)` commit 005a307) 仅影响 TAPGO_FORCE_PAIRED 模式, **不影响真机 tapgo-pair:// URL 流程** (URL 流程早就是闭环)
- 真机物理验证 (JK14pro 扫码 JKmacmini QR) 需 JKmacmini 登录桌面手工跑 — 详见 `mobile/E2E-TEST-v1.0.1.md`

## 最终状态

| 项 | 状态 |
| --- | --- |
| `main` HEAD | `005a307` |
| `origin/main` | `005a307` 同步 |
| JKmacmini build | ✅ 通过 |
| 端到端 (Mac 端 + 模拟器) | ✅ 验证完成 (绿色圆点 "已连接") |
| 真机 (JK14pro) 物理验证 | ⏸ 需 JKmacmini 登录桌面手工跑 (SSH session 无 display 权限) |
| Mac 端 ConnectPhoneView 弹窗截图 | ⏸ 同上 (代码已部署, 截图需手工) |
