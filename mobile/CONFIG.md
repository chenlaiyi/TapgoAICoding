# 点点够终端 · 开放平台配置（从 Ter-Tapgo 抽取）

> 来源：`~/Ter-Tapgo/ios/Runner/{Info.plist,Runner.entitlements}` 与
> `~/Ter-Tapgo/ios/Runner.xcodeproj/project.pbxproj`。以下为 2026-08-28 抽取结果。
>
> ⚠️ **Apple Developer 后台需要复核**：Ter-Tapgo 的 Bundle ID
> `com.devtools.terminalSimple` 可直接复用，但若 App Store Connect 里"点点够终端"
> 实际登记的 Bundle ID 不一致，请在 `mobile/ios/project.yml` 的
> `PRODUCT_BUNDLE_IDENTIFIER` 中改写并同步更新本文件，不要散落到 README/Evolution。

## iOS 通用

| 字段 | 值 | 来源 |
| --- | --- | --- |
| App 显示名 | `点点够终端`（CFBundleDisplayName / CFBundleName） | Info.plist |
| Bundle ID | `com.devtools.terminalSimple` | project.pbxproj |
| Apple Developer Team | `KF2CE24685` | project.pbxproj `DEVELOPMENT_TEAM` |
| Deployment Target | `iOS 13.0` | project.pbxproj `IPHONEOS_DEPLOYMENT_TARGET` |
| Marketing Version | `1.0` | project.pbxproj `MARKETING_VERSION` |
| Build Number 起始 | `1` | project.pbxproj `CURRENT_PROJECT_VERSION` |
| LSRequiresIPhoneOS | `true` | Info.plist |
| Required Device Capabilities | 由 Xcode 默认（arm64） | — |
| UIBackgroundModes | `fetch`, `processing` | Info.plist |
| BGTaskSchedulerPermittedIdentifiers | `com.itapgo.terminal.ai-sync`, `com.itapgo.terminal.data-sync` | Info.plist |
| NSAppTransportSecurity | `NSAllowsArbitraryLoads = true` | Info.plist |
| LSApplicationQueriesSchemes | `weixin`, `wechat`, `weixinULAPI`, `weixinURLParamsAPI`（若不需要微信，可删除） | Info.plist |
| 微信 URL Scheme | `weixin$(WECHAT_APP_ID)`（仅当真的接微信再配 Build Setting） | Info.plist |
| CADisableMinimumFrameDurationOnPhone | `true`（Flutter 遗留，无害；可保留） | Info.plist |
| Pair URL Scheme | `tapgo-pair`（新增，用于 Mac 端 QR 反向拉起 App） | Info.plist 新增 |

## iOS 权限 / 能力

| 字段 | 值 |
| --- | --- |
| `com.apple.developer.applesignin` | `Default`（即 "Sign in with Apple"，启用 SSO 按钮） |
| `com.apple.security.application-groups` | `group.com.devtools.terminalSimple`（为后续 Keychain 共享预留） |
| Push（`aps-environment`） | 未声明；上线前若需要推送，改为 `development` / `production` 并在 Apple Developer 后台开 APNs |
| App Groups | 已声明见上；若不需要可去掉 |
| 关联域名（Universal Links） | 未声明；若点 Mac 端"用点点够终端打开"反向跳转，再补 `applinks:tapgo-pair.example.com` |

## Android（Ter-Tapgo 中可推断的字段）

> Ter-Tapgo 是 Flutter 工程，Android 模块是 Flutter 默认模板，可推断字段有限。
> iOS 优先上线，Android 模板会在 `mobile/android/` 阶段单独抽。

| 字段 | 值 / 说明 |
| --- | --- |
| Application ID（待 iOS 验证后定） | 建议 `com.devtools.terminalSimple`（与 iOS 对仗） |
| minSdk / targetSdk | 21 / 34（Flutter 3.x 默认） |
| Display Name | `点点够终端` |
| Application ID 后缀 | `:background_fetch`、`:data_sync` 两个 WorkManager 子模块 |

## 协议：Mac ↔ iOS 配对（v1）

- **配对码格式**：6 位 `[A-Z0-9]`（去除 0/O/1/I/L 等易混淆字符），60 秒自动轮换。
- **QR 内容**：URL `tapgo-pair://<macDeviceId>?code=<PAIR_CODE>&host=<hostname>&port=<port>&v=1`；
  iOS 端只解析 scheme=`tapgo-pair`，host 字段兼容未来直接连 Bonjour 名称。
- **持久化**：Mac 端用 UserDefaults 存上次配对元数据；iOS 端 Keychain。
- **传输**：iOS 配对完成后通过 Bonjour (`_tapgo-pair._tcp`) 维持长链接；
  v1 命令帧走 JSON-RPC over TCP（端口可在 Mac 端 SettingsView 中改）。
- **版本兼容**：`v=1` 字段缺失即拒绝；升级协议时 bump 到 `v=2`，v1 端继续可用。

## Apple 后台需要确认 / 设置的事项

1. App Store Connect 已建 App "点点够终端"，确认其 Bundle ID 与上表一致。
2. Capabilities 中勾选 **Sign in with Apple**（已对齐 `Runner.entitlements`）。
3. Capabilities 中勾选 **Background Modes → Background fetch + Background processing**（已对齐 `UIBackgroundModes`）。
4. Capabilities 中按需勾选 **Push Notifications** / **App Groups** / **Associated Domains**。
5. Provisioning Profile 指向 Team `KF2CE24685`，首次 Archive 时由 Xcode 自动生成。
