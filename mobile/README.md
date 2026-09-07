# 点点够终端（Tapgo Mobile）—— 与 Tapgo AICoding 配对的手机端

本目录是从已弃用的 `~/Ter-Tapgo`（Flutter）迁移出的原生 iOS / Android 工程物料，
专门服务于 Tapgo AICoding 的"连接手机"能力。命名"点点够终端"已沿用 Ter-Tapgo
在 App Store Connect 的注册展示名，便于复用 Bundle ID 与 Team。

## 为什么独立成 `mobile/`

- Tapgo AICoding 主体仍是 macOS SwiftPM 工程（`Package.swift`），iOS / Android
  原生工程无法被 SwiftPM 直接构建；独立目录避免污染主仓的 SPM target 列表。
- Ter-Tapgo 已弃用，但其中"开放平台"信息（Bundle ID / Team / 部署目标 / 权限 /
  后台模式 / 微信 URL Scheme 等）被原样保留，作为重新注册的依据，避免在
  App Store Connect 重建新包名造成审核重审。
- 后续每个平台一个子目录：`ios/` / `android/`，各自维护自己的 `project.yml`
  （XcodeGen）和 `build.gradle` 模板。

## 当前状态（v0.5.9）

| 项 | 状态 | 备注 |
| --- | --- | --- |
| iOS 开放平台配置抽取 | ✅ 已落到 `mobile/CONFIG.md` | 来源：Ter-Tapgo `ios/Runner/Info.plist` + `project.pbxproj` |
| iOS Info.plist / Entitlements 模板 | ✅ 已落到 `mobile/ios/` | 与 Ter-Tapgo 字段对齐 |
| iOS XcodeGen `project.yml` | ✅ 已落到 `mobile/ios/project.yml` | 待下次装 `xcodegen` 后 `xcodegen generate` |
| iOS SwiftUI 源码（App、配对消费端、Dashboard） | ✅ 已落到 `mobile/ios/Sources/` | `DashboardView` v0.5.6 补齐；App 入口/手动输入/QR 占位/Keychain 抽象 已闭环 |
| iOS `MobilePairing` 协议层自包含副本 | ✅ 与 `Sources/TapgoCore/MobilePairing.swift` 字节级同步 | `Scripts/check-sync.sh` 强制保证；任何一端修改必须同步另一端 |
| iOS `Assets.xcassets`（AppIcon + AccentColor） | ✅ 占位 | `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 引用真实目录；图标 PNG 为 1x1 占位，上架前需替换为 1024x1024 真图标 |
| iOS 协议层测试 | ✅ **446 断言全部通过** | `Scripts/run-tests.sh`，本机 Mac（仅 Foundation 即可）即可跑，无需 iOS SDK |
| iOS 13–16 真机兼容性 fix | ✅ 删 `.textInputAutocapitalization(.characters)` (iOS 15+), 改用 iOS 13+ 兼容的 `.onChange(of:perform:)` 单参数 API | 见 commit: `fix: iOS 13–16 PairingView 兼容性 (v0.5.9)` |
| iOS SwiftUI 源码完整编译 | ✅ `mobile/ios/Sources/` 在 macOS SDK 26.5 下 `swift build` 完整通过 | 临时 SwiftPM target 把 iOS Sources 包入可执行，验证 SwiftUI / Combine 签名正确；唯一跨平台假阳性 (`Color(.systemBackground)`) 用 `#if os(iOS)` 包起 |
| iOS 真机 / 模拟器构建 | ✅ JKmacmini (Xcode 26.6) BUILD SUCCEEDED | arm64+x86_64 universal；iPhone 17 (iOS 18.5) 模拟器启动到 PairingView |
| iOS 16 deployment target | ✅ v1.0.0 起 | 原 Ter-Tapgo 13.0 与 SwiftUI @main/App/StateObject/NavigationStack 冲突；project.yml 与 mobile/CONFIG.md 已对齐 |
| iOS Keychain 持久化 | ✅ v1.0.0 | Sources/PairingKeychain.swift (PairingKeychain + ProbeKey)；PairingStore.init 默认走 Keychain, 写失败时退 UserDefaults |
| iOS 真实扫码 | ✅ v1.0.0 | Sources/QRScannerView.swift (AVFoundation AVCaptureMetadataOutput + .qr)；PairingView 用 sheet 触发；Info.plist 加 NSCameraUsageDescription |
| iOS tapgo-pair:// URL scheme | ✅ Info.plist 已注册 | xcrun simctl openurl 触发 iOS 18「在"点点够终端"中打开？」系统确认；PairingStore.handleIncomingURL 已被单元测试覆盖（20 用例, 含合法/非法 scheme/v=0/字符集） |
| iOS 协议层测试 | ✅ **488 断言全部通过** | 446 MobilePairing + 20 PairingStore + 22 MobileRemoteLink；Scripts/run-tests.sh 一键 |
| Mac 端"连接手机"菜单项 | ✅ 已加到 `SidebarView` 自进化/新对话 之间 | 见 `Sources/TapgoAICoding/Views/SidebarView.swift` |
| Mac 端配对码 / QR / 状态机 | ✅ 已加到 `Sources/TapgoAICoding/Views/ConnectPhoneView.swift` | 6 位配对码 + QR + 60s 自动轮换 + 未配对/已配对/已连接三态 |
| Mac 端协议模型 `MobilePairing` | ✅ 已加到 `Sources/TapgoCore/MobilePairing.swift` | 配对码生成/校验/URL 打包解析, Core 仅依赖 Foundation |
| Mac 端协议模型测试 | ✅ 449 个断言已通过 | `swift run TapgoTests --filter "MobilePairing: protocol + URL round-trip"` |
| iOS 端 `PairingStore` | ✅ 已加到 `mobile/ios/Sources/PairingStore.swift` | v0.5.5 用 UserDefaults 落地, v0.5.6 切 Keychain |
| iOS 端 PairingStore 与 PairingView 闭环比对 | ⚠️ 仅在 Xcode (有 iOS SDK) 上跑 | 本机仅有 CLT, 无 XCTest/iOS SDK；`swiftc -parse` 已通过 |
| Android 模板 | ⏸ 占位待写 | Ter-Tapgo Android 模块极简，详见 `mobile/CONFIG.md` |
| Mac App 目标在 CLT 上的编译 | ⚠️ SwiftUI 宏插件不可用 | 与本次新增代码无关, v0.4.2 已记; Core + TapgoTests target 已通过 |

## 配对协议（Mac ↔ iOS）

Mac 端生成一个 6 位大写字母数字配对码（默认 60 秒轮换），同时渲染一张 QR，内容是
`tapgo-pair://<mac-device-id>?code=<CODE>&host=<mac-hostname>&port=<local-port>&v=1`。
iOS 端扫码或手动输入 6 位码即完成配对，配对信息写入 iOS Keychain（SecureStorage）。
Mac 端会显示"已配对 / 已连接 / 未连接"三态；v0.5.5 先做协议与 UI 闭环, Bonjour (`_tapgo-pair._tcp`) 长链接在 v0.5.6 接入。

> 协议版本 `v=1`；后续协议升级需要在 URL 上 bump 版本号，保留向后兼容。

## iOS 目录结构

```
mobile/ios/
├─ project.yml                # XcodeGen 项目定义 (Xcode 14+ / Swift 5.9 / iOS 13+)
├─ Info.plist                 # CFBundleDisplayName=点点够终端, URL Scheme=tapgo-pair, BG modes
├─ Runner.entitlements        # App Group + Apple Sign In
├─ Assets.xcassets/           # AppIcon (占位) + AccentColor
├─ Sources/
│   ├─ TapgoTerminalApp.swift # @main App 入口 + RootView (按 state 分流)
│   ├─ PairingView.swift      # 手动输入 6 位码 + QR 占位
│   ├─ PairingStore.swift     # 配对状态机 + UserDefaults 落地 (v0.5.6 切 Keychain)
│   ├─ DashboardView.swift    # 已配对后展示 Mac 元信息 + 取消配对 (v0.5.6 新增)
│   └─ MobilePairing.swift    # 与 Sources/TapgoCore/MobilePairing.swift 同源副本
├─ Tests/
│   └─ MobilePairingProtocolTests.swift  # 协议层 446 断言, swiftc 直接可跑
└─ Scripts/
    ├─ check-sync.sh          # 强制保持 iOS 副本与 Core 字节级一致
    ├─ run-tests.sh           # 一键: 同步校验 + swiftc 编译 + 跑协议层测试
    └─ build.sh               # xcodegen generate + xcodebuild (需全 Xcode)
```


| iOS 长链接 (Bonjour + JSON-RPC over TCP) | ✅ v1.0.0 客户端代码到位 | Sources/PairingLink.swift (NWBrowser + 心跳) + Sources/MobileRemoteLink.swift (JSON-RPC 帧协议)；PairingStore.init 自动 start()；端到端联调需 Mac 端补 _tapgo-pair._tcp 服务 (现 Mac 端 v0.5.16 转 H5 HTTP, 原 Bonjour 服务未实现) |
| iOS 信息流 UI (P5 骨架) | ✅ DashboardView 渲染验证 | 切项目 / 发送消息 / 最近会话三入口；UI 截图见 artifacts/ios/v1.0.0-1/11-dashboard-clean.png |
| iOS 真机 build + install (JK14pro iPhone 14 Pro) | ✅ v1.0.0 | Scripts/build.sh 加 BUILD_TARGET=device 真机构建；Scripts/install-device.sh 一键 install+launch；App Store Connect 显示 Bundle ID=com.devtools.terminalSimple, version=1.0(1)；devicectl 无 screenshot 子命令 (Xcode 26.6)，截图需在 JKmacmini 上手工 Xcode → Devices and Simulators → Take Screenshot |
| iOS v1.0.1 Mac 端 PairCode 集成 | ✅ v1.0.0+ | Mac 端 `ConnectPhoneView.pairingCard` (6 位码 + tapgo-pair:// QR + 60s 倒计时) + `PhoneRemoteController` PairCode 状态机 + `Sources/TapgoAICoding/Services/PairingLinkListener.swift` Bonjour `_tapgo-pair._tcp` + JSON-RPC over TCP；`Sources/TapgoCore/MobileRemoteLink.swift` 真源 + `mobile/ios/Sources/MobileRemoteLink.swift` 副本 字节级 sync; iPhone 端 PairingLink NWBrowser 发现 Mac → NWConnection → 心跳 → DashboardView 「已连接」|
| iOS 已配对状态自动启动长链接 | ✅ v1.0.0 | PairingStore.init 检测到 stored mac 后自动启动 PairingLink；Bonjour 搜索中 (橙色圆点) |

## 一键跑命令

```bash
# 协议层 + 同步校验（仅需 Mac + Foundation, 无需 iOS SDK）
mobile/ios/Scripts/run-tests.sh

# 真机/模拟器构建（需全 Xcode + brew install xcodegen）
mobile/ios/Scripts/build.sh
```

## v0.5.9 增量（PairingView 兼容性 fix）

- 删 `.textInputAutocapitalization(.characters)` (iOS 15+ API, 13/14 真机会编译失败)
- `.onChange(of:initial:_:)` (iOS 17+ 签名) → `.onChange(of:perform:)` (iOS 13+ 单参数)
- `.background(Color(.systemBackground))` 用 `#if os(iOS)` 包起，避免 macOS SDK 跨平台验证假阳性
- `mobile/ios/Scripts/run-tests.sh` 仍 446/446 通过；新增的临时 SwiftPM target `/tmp/tapgo_ios_swiftpm` 在 SDK 26.5 下 `swift build` Build complete

不影响 Mac App 版本号；用户 WIP (v0.5.9 RateLimits / TurnProgressSummary) 保留未提交。

## 下一步执行清单

1. 在装全 Xcode 的机器上 `brew install xcodegen`，然后 `mobile/ios/Scripts/build.sh`
   生成 `TapgoTerminal.xcodeproj`；用 Xcode 打开后选真机/模拟器跑一次，确认
   SwiftUI 入口可启动到配对扫码界面，并验证 PairingStore ↔ PairingView 闭环。
2. 在 Apple Developer 后台确认 Bundle ID `com.devtools.terminalSimple` 已绑定的
   App Store Connect App 与本目录 `project.yml` 一致；若不一致，**只改
   `mobile/ios/project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER`** 和
   `mobile/CONFIG.md`，避免散落到其他文档。
3. 替换 `Assets.xcassets/AppIcon.appiconset/icon-1024.png` 占位为真 1024x1024
   图标（当前是 1x1 透明占位 PNG，仅用于让 build 通过）。
4. 走 TestFlight：Archive → Distribute → App Store Connect → TestFlight，
   在 App Store Connect 把 `点点够终端` 的 Build 关联到 1.0 准备提交审核。
5. 配对协议在 Mac 端 `MobilePairing.swift` (Core) 与 iOS 端 `Sources/MobilePairing.swift`
   对仗；任何字段调整需要两边同时改，再跑 `mobile/ios/Scripts/run-tests.sh` 验证。
