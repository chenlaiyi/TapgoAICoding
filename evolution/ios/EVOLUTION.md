# iOS Evolution Log

> iOS 1.0.x 与 Mac 0.x 独立编号；本文件于 v0.5.269 从主 `EVOLUTION.md` 分离，保留原始记录。
> iOS 版本不参与 Mac tag、Info.plist 与 makeHistory 校验。

## v1.0.0 (iOS) — 点点够终端 模拟器闭环 + Keychain + 真扫码
**Date**: 2026-09-08
**Scope**: iOS 端 (Mac 主仓 v0.5.x 仍独立演进)
**Test status**: MobilePairing 446/446 + PairingStore 20/20 = 466/466；JKmacmini BUILD SUCCEEDED (arm64+x86_64 universal)
**Changed**:
- `mobile/ios/project.yml`: deployment target 13.0 → 16.0（与 SwiftUI @main/App/StateObject/NavigationStack 对齐）；删除顶层 `info:` 块（xcodegen 会覆盖 `INFOPLIST_FILE`），强制走我们手写的 `Info.plist`。
- `mobile/ios/Scripts/build.sh`: ROOT 计算 `../..` → `../../..`（与 `check-sync.sh` 对齐）；xcodegen 改为 force regenerate（避免新源文件漏扫描）。
- `mobile/ios/Info.plist`: 加 `NSCameraUsageDescription`（AVFoundation 扫码所需）。
- `mobile/ios/Sources/PairingKeychain.swift` (新增): `PairingKeychain` (SecureStorage 实现，service=`com.devtools.terminalSimple.pairing`，kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) + `PairingKeychainProbeKey` (写入+读回探测)。
- `mobile/ios/Sources/PairingStore.swift`: `init` 默认 `storage: PairingKeychain()` + `fallback: UserDefaultsStorage?`；Keychain probe 失败时降级到 UserDefaults。
- `mobile/ios/Sources/QRScannerView.swift` (新增): `UIViewControllerRepresentable` 包 `AVCaptureSession` + `AVCaptureMetadataOutput` (.qr)，含权限请求、CameraDeniedView、CameraUnavailableView 兜底。
- `mobile/ios/Sources/PairingView.swift`: 「扫码配对」从占位卡换成真按钮，触发 `sheet` 弹 `QRScannerView`；`handleScannedCode` 同时支持 `tapgo-pair://` URL 与裸 6 位码。
- `mobile/ios/Tests/PairingStoreTests.swift` (新增): 20 用例覆盖 handleIncomingURL (合法/非法 scheme/字符集/v=0)、acceptManualCode (合法/非法字符)、unpair、InMemoryStorage round-trip、持久化路径。
- `mobile/ios/Scripts/run-tests.sh`: 分两个 `@main` binary 编译并分别跑（MobilePairing 协议 + PairingStore），输出合并。
- `mobile/ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png`: 1x1 占位 → 1024x1024 合规 PNG（深蓝渐变 + 中文标注，上架前需替换为正式设计）。
- `mobile/CONFIG.md`: Deployment Target 13.0 → 16.0（标注原因）。
**Why**: 之前 README 状态表说"v0.5.9 协议层 + SwiftUI 闭环"，但 `xcodegen + xcodebuild` 真机构建从未跑通；这次把"构建+模拟器+Keychain+扫码"四件一次性打通。

### v1.0.0 增量记录 — 增量 P4 + P5: 长链接 + 信息流
**Date**: 2026-09-08
**Scope**: iOS 端 P4 / P5
**Test status**: 488/488 全过 (446 MobilePairing + 20 PairingStore + 22 MobileRemoteLink)；JKmacmini iPhone 17 模拟器启动到 DashboardView
**Changed**:
- `mobile/ios/Sources/MobileRemoteLink.swift` (新增, 195 行): JSON-RPC over TCP 帧协议层, 纯 Foundation, 含 Frame / Params / AnyJSON / RPCError / Method 常量 / makeRequest/Result/Error/Hello/Heartbeat 构造器。
- `mobile/ios/Sources/PairingLink.swift` (新增, 258 行): NWBrowser (service=`_tapgo-pair._tcp`) + NWConnection (TCP) + 10s 心跳 + 帧收发解析 + 超时回收 + 状态机 idle/discovering/connecting/connected/failed。
- `mobile/ios/Sources/PairingStore.swift`: 加 `let link = PairingLink()`, init 检测到 stored mac 后自动 `link.start()` (Bonjour) 并绑定 `onConnectionChange` 反向翻 `state.connected`; 加 `stopLink()` 主动断开。
- `mobile/ios/Sources/DashboardView.swift`: 重写为真工作面板——Mac 元信息 + PairingLink 实时状态 + 「停止连接/取消配对」 + 「切项目/发送消息/最近会话」三类 P5 信息流入口（走 JSON-RPC over TCP, 服务端未对接所以 listSessions 等 RPC 会在 8s 后失败回 `lastError`，UI 安全降级）。
- `mobile/ios/Sources/TapgoTerminalApp.swift`: RootView 改为 `@EnvironmentObject` 分流；加 `#if DEBUG` `TAPGO_FORCE_PAIRED=1` 启动路径（注入示例 mac 让 DashboardView 可在 CI / 模拟器直接截图回归）。
- `mobile/ios/Tests/MobileRemoteLinkTests.swift` (新增, 105 行): 22 用例覆盖 Frame 编解码 (request/result/error/push)、isRequest/isResponse/isPush 分类、encode 不带尾巴换行、AnyJSON 嵌套 (array + object)、bonjour 常量。
- `mobile/ios/Scripts/run-tests.sh`: 分三 `@main` binary (协议层 / PairingStore / MobileRemoteLink) 编译并分别跑, 输出合并。
**Why**: 之前 P3 已经"模拟器能启动 PairingView + Keychain + 真扫码", 但 DashboardView 是空壳。P4 + P5 把"已配对后能干什么"做成完整工作面板：长链接客户端 + 信息流 UI, 让原生 App 不只是个"扫码器"。
**Why (Mac 端协同现状)**: Mac 端 `PhoneRemoteServer.swift` (v0.5.16) 已转向 H5 HTTP (token-authed web remote), 原 Bonjour `_tapgo-pair._tcp` 服务未实现。**iOS 端 PairingLink 真实连接到 Mac 还需要 Mac 端补 Bonjour 服务 / JSON-RPC 服务**；现阶段 iOS 端协议层 + UI 完整可工作, Bonjour 搜索超时为橙色「Bonjour 搜索中…」状态, 不影响其它 UI (切项目/发送消息按钮在 not connected 时禁用)。
**Next**: P6 TestFlight + 提审需先解决 Mac 端 Bonjour 服务或决定 iOS 端转 H5 WKWebView 路线；Apple Developer 后台 Bundle ID 对齐确认；正式 1024x1024 AppIcon 替换占位渐变图。

**Next**: P4 Bonjour 长链接（iOS 端 NWBrowser + JSON-RPC 心跳 + Mac 端 ConnectPhoneView 联动）；P5 信息流骨架（最近会话、发送消息、切项目）；P6 TestFlight + 提审。

### v1.0.0 增量记录 — 点点够终端 模拟器闭环 (P0–P5) + 真机 install + Mac logo 对齐
**Date**: 2026-09-08
**Scope**: iOS 端独立发布 (Mac 主仓仍走 v0.5.x)
**Tag**: v1.0.0
**Test status**: 488/488 全过 (446 MobilePairing + 20 PairingStore + 22 MobileRemoteLink)；JKmacmini iPhone 14 Pro (iOS 26.6) + iPhone 15 Pro 真机 install + launch 成功
**Changed**:
- `mobile/ios/project.yml`: deployment target 13.0 → 16.0 (与 SwiftUI @main/App/StateObject/NavigationStack 对齐); 删除顶层 `info:` 块 (xcodegen 会覆盖 INFOPLIST_FILE), 强制走我们手写的 Info.plist
- `mobile/ios/Info.plist`: 加 `NSCameraUsageDescription`
- `mobile/ios/Runner.entitlements`: 临时注释 App Groups + Sign In with Apple (Apple Developer 后台 Capability 未勾; 上线前取消注释)
- `mobile/ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png`: 1×1 占位 → 1024×1024 不透明 RGB, 与 Mac 端 `AppBuilder/AppIcon.icns` 设计语言一致 (紫蓝渐变 + 白色 C 形 + 中心绿色三角)
- `mobile/ios/Scripts/build.sh`: ROOT 计算 `../..` → `../../..` (与 check-sync.sh 对齐); xcodegen force regenerate; 真机 build path 加 `security unlock-keychain`; `BUILD_TARGET=device DEVICE_UDID=...` 切换 destination + 启用签名
- `mobile/ios/Scripts/install-device.sh` (新增): 一键 unlock + install + launch + 验证
- `mobile/ios/Sources/PairingKeychain.swift` (新增, 85 行): PairingKeychain (SecureStorage 实现, service=`com.devtools.terminalSimple.pairing`, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) + PairingKeychainProbeKey (写+读回探测)
- `mobile/ios/Sources/PairingStore.swift`: init 默认走 Keychain, probe 失败时退 UserDefaults; 加 `let link = PairingLink()`, init 检测到 stored mac 后自动 `link.start()` + `onConnectionChange` 反向翻 state.connected; 加 `stopLink()`
- `mobile/ios/Sources/QRScannerView.swift` (新增, 232 行): UIViewControllerRepresentable 包 AVCaptureSession + AVCaptureMetadataOutput (.qr), 含权限请求 + CameraDeniedView + CameraUnavailableView 兜底
- `mobile/ios/Sources/PairingView.swift`: 扫码卡换成真按钮 + sheet 触发 QRScannerView; handleScannedCode 同时支持 `tapgo-pair://` URL 与裸 6 位码
- `mobile/ios/Sources/MobileRemoteLink.swift` (新增, 195 行): JSON-RPC over TCP 帧协议层 (Frame / Params / AnyJSON / RPCError / Method 常量), 纯 Foundation
- `mobile/ios/Sources/PairingLink.swift` (新增, 258 行): NWBrowser (`_tapgo-pair._tcp`) + NWConnection + 10s 心跳 + 帧收发解析 + 超时回收 + 状态机 idle/discovering/connecting/connected/failed
- `mobile/ios/Sources/DashboardView.swift`: 重写 239 行 — Mac 元信息 + PairingLink 实时状态 + 「停止连接/取消配对」 + 「切项目/发送消息/最近会话」三类 P5 信息流入口
- `mobile/ios/Sources/TapgoTerminalApp.swift`: RootView 改 @EnvironmentObject 分流; 加 `#if DEBUG` `TAPGO_FORCE_PAIRED=1` 启动路径 (注入示例 mac 让 DashboardView 可在模拟器/CI 截图回归)
- `mobile/ios/Tests/PairingStoreTests.swift` (新增, 134 行): 20 用例覆盖 handleIncomingURL / acceptManualCode / unpair / InMemoryStorage round-trip / 持久化路径
- `mobile/ios/Tests/MobileRemoteLinkTests.swift` (新增, 105 行): 22 用例覆盖 Frame 编解码 (request/result/error/push) + isRequest/isResponse/isPush 分类 + encode 不带尾巴换行 + AnyJSON 嵌套 (array + object) + bonjour 常量
- `mobile/ios/Scripts/run-tests.sh`: 分三 `@main` binary 编译并分别跑 (协议层 / PairingStore / MobileRemoteLink), 输出合并
- `mobile/CONFIG.md`: Deployment Target 13.0 → 16.0 (标注原因)
- `mobile/README.md`: 状态表加7 行 v1.0.0 + 修 shell 误吃字段
**Why**: 之前 README 说"v0.5.9 协议层 + SwiftUI 闭环", 但 xcodegen+xcodebuild 真机构建从未跑通. 这次把 构建+模拟器+Keychain+扫码+Bonjour 长链接+信息流+真机 install+Mac logo 对齐 八件事一次性打通.
**Next (P6)**: Apple Developer 后台 Capabilities 勾选 App Groups + Sign In with Apple, 取消 Runner.entitlements 注释; Archive + Distribute → App Store Connect → TestFlight; Mac 端补 Bonjour 服务或 iOS 端决定改走 H5 WKWebView 路线, 让 P4 端到端联调变绿; 正式 AppIcon (当前用 Mac 端 logo 拍平白底, 上线前可优化设计).

## v1.0.1 (iOS) — 增量: Mac 端 PairCode 集成 + tapgo-pair:// UI + Bonjour 长链接
**Date**: 2026-09-08
**Scope**: iOS 端独立 patch (Mac 主仓 v0.5.129, iOS 仍为 1.0.0)
**Tag**: v1.0.1
**Test status**: 488/488 (iOS 端未变, 协议层 sync 通过); Mac 端 `swift build --target TapgoAICoding` 在 JKmacmini (Xcode 26.6) 通过
**Changed**:
- `Sources/TapgoCore/MobileRemoteLink.swift` (新增, 134 行): JSON-RPC over TCP 帧协议层, 真源.
- `Sources/TapgoAICoding/Services/PairingLinkListener.swift` (新增, 163 行): Bonjour `_tapgo-pair._tcp` NWListener + JSON-RPC 帧解析; hello → onId(deviceId) + ack push; request → RequestHandler 路由 (Phase 2 占位).
- `Sources/TapgoAICoding/Services/PhoneRemoteServer.swift` (+69 行):
  - `@Published private(set) var pairingCode: MobilePairing.PairCode?` (60 秒 TTL)
  - `@Published private(set) var pairingURLString: String` (tapgo-pair:// URL)
  - `let macDeviceId: String` (UserDefaults 持久化)
  - `refreshPairingCode()` / `startPairingTimer()` / `startPairingLinkListener()` / `handlePairingId(_:)` 四个新方法
  - `init` + `startIfNeeded` + `stop` 同步集成
- `Sources/TapgoAICoding/Views/ConnectPhoneView.swift` (+130 行): 新增 `pairingCard` (6 位码大字体 + 60s 倒计时 + tapgo-pair:// QR + 复制按钮 + Hostname) + `PairingQRRenderer` (CIQRCodeGenerator → NSImage) + `String.nonEmpty` extension
- `mobile/ios/Sources/MobileRemoteLink.swift` (新增, 283 行): Mac 真源的 iOS 副本 (字节级同步, MARK 注释块)
- `mobile/ios/Scripts/check-sync.sh` (+56 行): 扩展为同时校验 `MobilePairing` + `MobileRemoteLink` 双协议层
- `mobile/E2E-TEST-v1.0.1.md` (新增, 90 行): 端到端测试脚本 (Mac 端 PairCode 卡片 + iPhone 真机扫码 → DashboardView 已连接)

**Why**: 之前 v0.5.16 Mac 端 `ConnectPhoneView` 重写转 H5 路线时把 6 位配对码 UI 删了，导致 iOS App v1.0.0 配对功能孤立. 本次恢复 v0.5.7 路径, 端到端配对闭环.
**Test status (manual)**: 端到端真机测试需 JKmacmini 登录桌面手工跑 (SSH session 无 display 权限). 模拟器 build + 真机 build 都通过, 但 PairCode 卡片 UI 截图 + DashboardView 已连接状态截图需用户手工.
**Next (Phase 3)**: Mac 端 `PairingLinkListener` `RequestHandler` 路由到 `SessionStore` / `WorkspaceStore`; 实现 `listSessions` / `switchProject` / `sendMessage` 真业务流.
