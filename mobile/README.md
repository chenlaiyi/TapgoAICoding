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

## 当前状态（v0.5.6）

| 项 | 状态 | 备注 |
| --- | --- | --- |
| iOS 开放平台配置抽取 | ✅ 已落到 `mobile/CONFIG.md` | 来源：Ter-Tapgo `ios/Runner/Info.plist` + `project.pbxproj` |
| iOS Info.plist / Entitlements 模板 | ✅ 已落到 `mobile/ios/` | 与 Ter-Tapgo 字段对齐 |
| iOS XcodeGen `project.yml` | ✅ 已落到 `mobile/ios/project.yml` | 待下次装 `xcodegen` 后 `xcodegen generate` |
| iOS SwiftUI 源码（App、配对消费端、Dashboard） | ✅ 已落到 `mobile/ios/Sources/` | `DashboardView` v0.5.6 补齐；App 入口/手动输入/QR 占位/Keychain 抽象 已闭环 |
| iOS `MobilePairing` 协议层自包含副本 | ✅ 与 `Sources/TapgoCore/MobilePairing.swift` 字节级同步 | `Scripts/check-sync.sh` 强制保证；任何一端修改必须同步另一端 |
| iOS `Assets.xcassets`（AppIcon + AccentColor） | ✅ 占位 | `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 引用真实目录；图标 PNG 为 1x1 占位，上架前需替换为 1024x1024 真图标 |
| iOS 协议层测试 | ✅ **446 断言全部通过** | `Scripts/run-tests.sh`，本机 Mac（仅 Foundation 即可）即可跑，无需 iOS SDK |
| iOS SwiftUI 源码 `swiftc -parse` 语法校验 | ✅ 6 个 .swift 全部 parse 通过 | `TapgoTerminalApp / PairingView / PairingStore / DashboardView / MobilePairing / Tests` |
| iOS 真机 / 模拟器构建 | ⏸ 下一步 | 需要本机或 CI 装全 Xcode；`Scripts/build.sh` 已写好，缺 xcodegen/xcodebuild 时给出明确指引 |
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

## 一键跑命令

```bash
# 协议层 + 同步校验（仅需 Mac + Foundation, 无需 iOS SDK）
mobile/ios/Scripts/run-tests.sh

# 真机/模拟器构建（需全 Xcode + brew install xcodegen）
mobile/ios/Scripts/build.sh
```

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
