# 端到端测试 v1.0.1: iPhone 点点够终端 + Mac Tapgo AICoding 真配对

> 本测试验证 iOS v1.0.0 + Mac v0.5.129 (含 PairCode 集成) 端到端配对闭环。
> 当前已在 origin/main (dbd2fd8) 同步, JKmacmini 已 build 通过。

## 前置

- [x] Mac 端代码含 `Sources/TapgoCore/MobileRemoteLink.swift` (Mac 真源)
- [x] Mac 端代码含 `Sources/TapgoAICoding/Services/PairingLinkListener.swift` (Bonjour NWListener)
- [x] Mac 端 `PhoneRemoteController` 含 `pairingCode` / `pairingURLString` / `macDeviceId`
- [x] Mac 端 `ConnectPhoneView` 含 `pairingCard` UI (6 位码 + QR + 倒计时)
- [x] iOS 端 App 已装到 JK14pro (A35FE5C0-...) / JK15pro (FCEDD862-...) 真实机
- [x] JKmacmini (Xcode 26.6) build 通过 (`swift build --target TapgoAICoding`)

## 端到端测试步骤

### 1. Mac 端启动 + 打开"连接手机"弹窗

```bash
# 在 JKmacmini 上 (有人登录桌面)
cd ~/TapgoAICoding
swift build --target TapgoAICoding
# 启动 app (如果还没启动)
open -a "Tapgo AICoding"
# 在 app 内: 侧栏 "连接手机" 按钮 → 弹窗
```

**预期**:
- 弹窗内出现新卡片 "**原生 iOS 配对码**"
- 显示 6 位字符 (例: `KYAEHS`)
- 显示二维码 (内含 `tapgo-pair://<macDeviceId>?code=KYAEHS&host=100.71.223.108&port=8723&v=1#JKmacmini`)
- 倒计时 "60 秒后刷新"
- 60 秒后自动轮换新码

### 2. iPhone 端扫码

```bash
# 在 iPhone JK14pro 上
# 打开 "点点够终端" App → PairingView
# 点击 "扫码配对" 按钮 → 弹相机
# 扫 Mac 端 QR
```

**预期**:
- iOS 系统弹 "在'点点够终端'中打开?" 确认 → 确认
- iOS 跳到 DashboardView
- DashboardView 显示 Mac 元信息 (设备 ID / 主机名 / 主机 / 端口)
- 连接状态: "Bonjour 搜索中…" (橙色) → 几秒后 "已连接 · <host:port>" (绿色)

### 3. iPhone 端手动输入 (备选)

```bash
# 在 iPhone 上 PairingView 输入 6 位码 (从 Mac 弹窗抄)
# 点击 "配对"
```

**预期**:
- 切到 DashboardView (同扫码路径)

### 4. 验证 iOS 端切项目 / 发送消息 (Phase 3 占位)

```bash
# DashboardView 上:
# "切项目" 按钮 → 调用 listSessions/switchProject JSON-RPC (Phase 2 占位, 会 timeout 8s)
# "发送消息" 按钮 → 调用 sendMessage JSON-RPC
```

**预期**:
- 切项目按钮短暂 ProgressView, 然后 "已请求切项目" / "切项目失败: timeout" (取决于 Mac 端 RequestHandler 实现)
- 发送消息按钮类似行为
- v1.0.1 阶段: 端到端配对已闭环, JSON-RPC 业务流待 Phase 3 完善

## 已知限制

1. **Mac 端 RequestHandler 占位**: `PairingLinkListener.handleRequest` 当前无 `onRequest` 路由, 收到 `request/listSessions` 等会回 `no handler` 错误. iOS 端会显示 "加载会话失败: ...". Phase 3 接 `SessionStore` / `WorkspaceStore` 解决.
2. **iOS 端 RPC 业务流**: DashboardView 的 `listSessions` / `switchProject` / `sendMessage` 已有 UI + RPC 调用, 但 Mac 端回 `no handler`. v1.0.1 阶段: UI + 协议层到位, 业务接入 Phase 3.
3. **AppIcon**: 当前是 Mac 端 logo 拍平到白底 (紫蓝渐变 + 白色 C + 绿色三角), 上线前可优化设计.

## 截图归档

- `artifacts/ios/v1.0.0-1/15-springboard-icon.png` — AppIcon 在 iOS Springboard
- `artifacts/ios/v1.0.0-1/12-p4p5-final.png` — iOS 模拟器 DashboardView (Bon 搜索中)
- (新) `artifacts/ios/v1.0.1-1/mac-connectphone-paircode.png` — Mac 端 ConnectPhoneView PairCode 卡片 (需手工截)
- (新) `artifacts/ios/v1.0.1-1/iphone-dashboard-connected.png` — iOS 真机 DashboardView "已连接" 状态 (需手工截)

## 下一步 (Phase 3)

- Mac 端 `PairingLinkListener` 加 `RequestHandler` 路由到 `SessionStore` / `WorkspaceStore`
- 实现 `listSessions` / `switchProject` / `sendMessage` 业务流
- v1.0.1 release 后可推 v1.1
