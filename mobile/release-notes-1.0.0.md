# Release Notes 1.0.0 (iOS) — 点点够终端

**App**: 点点够终端 (Tapgo Mobile Terminal)
**Bundle ID**: `com.devtools.terminalSimple`
**Marketing Version**: 1.0
**Build**: 1
**Deployment Target**: iOS 16.0
**Date**: 2026-09-08
**Status**: ✅ 已通过 iPhone 14 Pro / iPhone 15 Pro 真机 install + launch 回归 (JKmacmini, Xcode 26.6, iOS 26.6)

---

## 🎉 这是点点够终端的第一个正式版本

点点够终端是 Tapgo AICoding 桌面端的官方移动配对 App。完成扫码配对后, 你可以在手机上:

- 看到当前 Mac 工作区的连接状态
- 切换工作项目
- 给当前会话发送消息
- 浏览 Mac 端最近的会话列表
- 通过 Bonjour 长链接 + JSON-RPC over TCP 与 Mac 端实时通信

## 安装与使用

1. **iPhone 真机**: 通过 TestFlight / App Store 安装 (P6 阶段)
2. **配对**: 打开 App → 扫码 Mac 端「Tapgo AICoding → 连接手机」弹窗里的二维码, 或手动输入 6 位配对码
3. **使用**: 配对成功后自动跳转 DashboardView, 开始使用快捷动作

## 开发里程碑

| 阶段 | 描述 | 状态 |
| --- | --- | --- |
| P0 | iOS MobilePairing 协议层与 Mac 端 Core 字节级同步 | ✅ |
| P1 | iOS 16.0 deployment target; xcodegen+xcodebuild BUILD SUCCEEDED; iPhone 17 模拟器启动到 PairingView | ✅ |
| P2 | 1024×1024 不透明 RGB AppIcon (与 Mac 端 logo 一致: 紫蓝渐变 + 白色 C 形 + 中心绿色三角) | ✅ |
| P3 | Keychain 持久化 (PairingKeychain + ProbeKey fallback); AVFoundation 真实扫码 (QRScannerView); `tapgo-pair://` URL scheme 在 iOS 18 系统级「在"点点够终端"中打开?」确认注册成功 | ✅ |
| P4 | Bonjour 客户端 + JSON-RPC over TCP 帧协议 (NWBrowser `_tapgo-pair._tcp` + 心跳); 模拟器显示「Bonjour 搜索中…」(橙色, Mac 端 v0.5.16 转 H5 后无 `_tapgo-pair._tcp` 服务, 端到端联调待 Mac 端补) | ✅ (客户端) |
| P5 | 信息流 UI: DashboardView 切项目 / 发送消息 / 最近会话三入口; 模拟器渲染验证通过 | ✅ |
| 真机 install + launch | Scripts/install-device.sh 一键; JK14pro + JK15pro 双机安装成功 | ✅ |
| P6 | Apple Developer 后台 Capabilities 勾选 + TestFlight + App Store 提审 | ⏸ |

## 技术规格

| 项 | 值 |
| --- | --- |
| Bundle ID | com.devtools.terminalSimple |
| Apple Developer Team | KF2CE24685 |
| Deployment Target | iOS 16.0 |
| Marketing Version | 1.0 |
| Build Number | 1 |
| Languages | zh-Hans (developmentLanguage) |
| Background Modes | fetch, processing |
| BGTaskScheduler IDs | com.itapgo.terminal.ai-sync, com.itapgo.terminal.data-sync |
| URL Schemes | tapgo-pair |
| App Groups | group.com.devtools.terminalSimple (暂注释, 后台未勾选) |
| Sign In with Apple | Default (暂注释, 后台未勾选) |
| Push Notifications | 未声明 |
| Associated Domains | 未声明 |

## 测试覆盖

| 模块 | 断言数 | 工具 |
| --- | --- | --- |
| MobilePairing 协议层 | 446 | swiftc 直跑 |
| PairingStore 状态机 | 20 | swiftc 直跑 |
| MobileRemoteLink JSON-RPC 帧 | 22 | swiftc 直跑 |
| **合计** | **488/488** ✅ | `mobile/ios/Scripts/run-tests.sh` |

## 真机回归

| 设备 | UDID | iOS | 结果 |
| --- | --- | --- | --- |
| JK14pro (iPhone 14 Pro) | A35FE5C0-C4C1-5438-8243-B8645E02AAF9 | 26.6 (23G71) | ✅ install + launch |
| JK15pro (iPhone 15 Pro) | FCEDD862-053E-5F7C-B32F-F652DF17788D | 26.6 | ✅ install + launch |

## 截图归档

- `artifacts/ios/v1.0.0-1/01-pairing-view.png` — 初始 PairingView
- `artifacts/ios/v1.0.0-1/04-pairing-scan.png` — 集成 AVFoundation 扫码后
- `artifacts/ios/v1.0.0-1/06-after-pair.png` — 系统弹「在点点够终端中打开?」(tapgo-pair:// 注册证据)
- `artifacts/ios/v1.0.0-1/11-dashboard-clean.png` — 已配对 DashboardView (浅色模式)
- `artifacts/ios/v1.0.0-1/12-p4p5-final.png` — P4 + P5 收尾 (Bonjour 搜索中)
- `artifacts/ios/v1.0.0-1/15-springboard-icon.png` — 新 AppIcon 在 Springboard

## 已知限制

1. **真机截图自动化**: Xcode 26.6 的 `devicectl` 没有 screenshot 子命令; 真机截图需在 JKmacmini 上用 Xcode → Devices and Simulators → Take Screenshot 手动截取
2. **Mac 端 Bonjour 服务**: Mac 端 v0.5.16 起转向 H5 HTTP 控制页 (无需安装原生 App), 原 `MobilePairing` 协议层保留但 UI 不再用. iOS 端 PairingLink 客户端代码完整, 但 Mac 端没有监听 `_tapgo-pair._tcp` 服务, 所以 iOS DashboardView 上一直显示「Bonjour 搜索中…」(橙色). 端到端联调需要 Mac 端补 Bonjour 服务或 iOS 端决定改走 H5 WKWebView 路线
3. **AppIcon**: 当前是 Mac 端 logo 拍平到白底, 上线前可让设计师优化 (圆角, 阴影, 光泽等 iOS HIG 装饰)

## 下一步

1. Apple Developer 后台 Capabilities 勾选 App Groups + Sign In with Apple, 取消 Runner.entitlements 注释
2. Mac 端补 Bonjour 服务 (`_tapgo-pair._tcp`) 或 iOS 端改 H5 路线
3. Archive → Distribute → App Store Connect → TestFlight 灰度
4. 正式 AppIcon 设计优化

## 完整命令

```bash
# 协议层 + PairingStore + MobileRemoteLink 测试 (无需 iOS SDK)
cd mobile/ios && ./Scripts/run-tests.sh
# → 488/488 通过

# 模拟器 build + install
cd mobile/ios && ./Scripts/build.sh
xcrun simctl install <DEVICE_UDID> build/Build/Products/Debug-iphonesimulator/点点够终端.app

# 真机 build + install (一键)
cd mobile/ios && BUILD_TARGET=device DEVICE_UDID=A35FE5C0-C4C1-5438-8243-B8645E02AAF9 ./Scripts/build.sh
cd mobile/ios && ./Scripts/install-device.sh A35FE5C0-C4C1-5438-8243-B8645E02AAF9 JK14pro
```
