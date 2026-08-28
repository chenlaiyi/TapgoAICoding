# Evolution Log

> Append-only changelog for self-evolution iterations of **Tapgo AICoding**.
> Each entry corresponds to one git tag (one full build → test → commit → push cycle).
> Rollback to any version: `git checkout vX.Y.Z && ./scripts/build-app.sh`.

## Format

```
## vX.Y.Z — <one-line summary>
**Date**: YYYY-MM-DD
**Commit**: <short SHA>
**Tag**: vX.Y.Z
**Test status**: 110/110 green (or however many passed)
**Changed**:
- bullet
- bullet
**Why**: 1–2 sentences on the motivation / problem solved.
**Next**: what the following iteration plans to tackle (or "see state file").
```

## v0.5.9 — Codex 式步骤进度、真实变更统计与运行流光
**Date**: 2026-08-29
**Commit**: _pending_
**Tag**: v0.5.9
**Test status**: — 步骤进度 12/12、限额解析 30/30、新套餐展示 16/16、旧展示兼容 30/30；macOS Release build + 原生界面回归通过 —
**Changed**:
- 输入区上方新增真实步骤进度胶囊，显示当前步数、当前回合文件数、绿色新增行和红色删除行；点击可展开完整步骤清单。
- 优先消费 Harness 的 `turn/plan/updated` 与 `turn/diff/updated`；仅有命令工具时，以回合开始前 Git 基线统计本回合新增变更，不混入既有脏工作树。
- 最新一行灰色运行活动加入白色流光，在搜索、读取、编辑、运行等状态之间原位更新；历史活动静止，减少动态效果时自动停用。
- 接入 Codex `account/rateLimits/read` 与实时更新通知，套餐 chip 展示真实 5 小时/周窗口、使用比例、压力等级与重置时间。
- 原生安装版验证运行中输入框焦点稳定，步骤弹窗、真实 `1 个文件已更改 +3 -0` 与完成清理全部通过。
**Why**: 用户需要像 Codex 一样一眼看懂当前在做哪一步、真实改了多少代码，并能从最新活动的流光辨认任务仍在运行；套餐用量也必须来自账户限额而非会话 token 估算。
**Next**: 为进度清单补充失败步骤与耗时，并在远程会话中验证多工作树 diff 的统计一致性。

## v0.5.8 — Codex / DeepSeek 官方插件管理
**Date**: 2026-08-28
**Commit**: ad339ce
**Tag**: v0.5.8
**Test status**: — PluginCatalog 13 passed, 0 failed；macOS Release build + 原生界面回归通过 —
**Changed**:
- 左上菜单新增「插件」，通过 980 × 680 原生弹窗管理已安装插件、搜索并浏览官方来源。
- Codex 官方目录直接读取 App 当前使用的 Codex CLI 与隔离 `CODEX_HOME`；显示应用 / MCP / 技能能力，支持安装、卸载和启停。
- DeepSeek 官方区只展示 CLI 文档明确支持的 Codex 与 Claude Code 子代理包；安装固定使用和当前 Harness 对齐的 `next` 通道，不再暴露内部 patch / driver / SDK 依赖。
- 安装与卸载均经过安全插件标识校验；操作前确认，完成后刷新目录，并明确提示新会话或重启 Harness 生效。
- 按用户参考图完成深色布局、分类计数、搜索框、来源说明、插件行与状态操作；本机真实 UI 验证为 0 / 46 / 2，搜索 `Figma` 仅保留一个匹配项。
**Why**: 用户需要在 Tapgo AICoding 内统一管理 Codex 与 DeepSeek Harness 插件，而不是自行执行不透明的 CLI 命令；同时必须避免把 DeepSeek 内部 npm 依赖误展示成可安装插件。
**Next**: 为已安装插件增加详情页，展示权限、依赖、更新状态与变更日志。

## v0.5.7 — iOS 原生工程闭环（Dashboard + 协议层同步 + 协议测试）
**Date**: 2026-08-28
**Commit**: e5d2eea
**Tag**: v0.5.7
**Test status**: — iOS MobilePairing 协议层 446 断言全过 — Mac `swift run TapgoTests` 仍 1251 全过
**Changed**:
- `mobile/ios/Sources/DashboardView.swift` (新增)：补齐 `RootView` 引用的 `DashboardView`，展示已配对 Mac 元信息 + 连接状态指示灯 + 取消配对按钮。
- `mobile/ios/Sources/MobilePairing.swift` (新增)：iOS 端自包含副本，等价于 `Sources/TapgoCore/MobilePairing.swift`，确保独立 Xcode 工程不依赖 SwiftPM 兄弟模块。
- `mobile/ios/Scripts/check-sync.sh` + `run-tests.sh` + `build.sh`：强制保持 Core 与 iOS 副本字节级一致；一键跑协议测试；一键 xcodegen + xcodebuild。
- `mobile/ios/Tests/MobilePairingProtocolTests.swift`：446 断言覆盖生成/校验/TTL/URL round-trip/parseIncomingURL 拒绝路径/State 派生；本机 `swiftc -emit-executable` 直跑，无需 iOS SDK。
- `mobile/ios/Assets.xcassets/`：AppIcon + AccentColor 占位（1x1 透明 PNG 临时填充避免 build 失败，上架前需替换 1024x1024 真图标）。
- `mobile/ios/project.yml`：把 `Assets.xcassets` 加入 sources；启用 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`。
- `mobile/README.md`：状态表对齐 v0.5.7 真实进度（v0.5.5 表格已过期），新增目录结构与一键命令。
- 6 个 iOS SwiftUI 源文件 `swiftc -parse` 全部通过：`TapgoTerminalApp / PairingView / PairingStore / DashboardView / MobilePairing / Tests`。
**Why**: `mobile/ios/` 工程原本缺少 `DashboardView`，编译不能闭环；MobilePairing 协议层在 iOS 工程里要靠 SwiftPM 引用兄弟模块，与"独立 Xcode 工程"约束冲突。补齐后 iOS 工程能在不依赖主仓 SPM target 的前提下独立 `xcodegen generate` + `xcodebuild`，并由 `check-sync.sh` 强制协议两端同步漂移。
**Next**: 在装全 Xcode 的机器上 `mobile/ios/Scripts/build.sh` 生成 `TapgoTerminal.xcodeproj`，跑模拟器验证 PairingStore ↔ PairingView ↔ DashboardView 闭环；接入 AVFoundation 真扫码；接入 Bonjour (`_tapgo-pair._tcp`) 长链接，把"未连接"灯变绿。

## v0.5.6 — 输入框下方右侧"套餐用量"chip
**Date**: 2026-08-28
**Commit**: c716fe4
**Tag**: v0.5.6
**Test status**: — 1251 passed, 0 failed —
**Changed**:
- 新增 `TapgoCore/SubscriptionUsage`：聚合 `Thread.usageTotal` + 最近一次 turn 的 `TokenUsage.contextWindow` + `ContextLevel` 配色等级。
- `composerMetricsBar` 右侧新增"套餐用量 X / Y (Z%)"chip，按压力等级 brand / warn / error 着色；空用量时自动隐藏。
- `TapgoTests/SubscriptionUsageTests`：30 项断言覆盖 isVisible / percent / level / chipLabel / detailText / from(turnsTotalTokens, latestUsage, fallbackWindow)。
- 顺手把上一会话未提交的插件管理 WIP（`PluginManagerService` / `PluginManagerView` / `PluginCatalog` / `PluginCatalogTests` / `SidebarView` 的『插件』菜单项与 sheet）一并 commit，避免 v0.5.6 的 SidebarView 引用悬空；`PluginManagerService.init()` 调用 `RemoteCodexHomeSync.findHarness()` 已用 `MainActor.assumeIsolated` 包装，App target 在 SDK 26.5 下恢复 build。
**Why**: 用户要求在输入框下方右侧看到当前订阅套餐用量；本版用 thread 累计 token 作为最小可用数据源，codex `account/rateLimits/read` 接入留给后续迭代。
**Next**: 接入 codex `account/rateLimits/read` 拿到真实剩余/重置时间，把 chip 升级为"已用 X / 剩余 Y / 重置于 Z"。

## v0.5.5 — 连接手机菜单 + MobilePairing 协议 + 长期记忆解析修复
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.5`)_
**Tag**: v0.5.5
**Test status**: — 1221 passed, 0 failed —
**Changed**:
- 左上角菜单栏在「自进化 / 新对话」之间插入「连接手机」，对接 Ter-Tapgo 的 iOS 端「点点够终端」。
- `TapgoCore/MobilePairing` 提供协议层：6 位配对码生成、字符集过滤、`tapgo://pair?` URL 打包/解析、State 状态机与 PairedMac 持久化。
- 新增 `ConnectPhoneView`（6 位码 + CoreImage QR + 倒计时 + 未配对/已配对/已连接三态）和 `MobilePairingStore`，状态可关闭后恢复。
- 同步产出 iOS 端 `PairingStore`（v0.5.5 走 UserDefaults，v0.5.6 切 Keychain）与 `mobile/` 工程骨架，待接入 XcodeGen + 完整 Xcode 工具链生成 `.xcodeproj`。
- `DurableMemory.parseBullets` 的 timestamped 分支现在保留 `- ` 前缀，与 legacy 分支统一；原回归测试 `DurableMemoryTests:69` 通过。
- 新增 `MemoryCloudSync`、`MemoryConsolidator`、`TurnPresentation`、`TurnSteerPayload` 与对应测试，测试数 706 → 1221。
**Why**: 用户要在 Mac 端对接 iOS 原生 App「点点够终端」，先打通协议层与 Mac 端 UI；同时修复 19 个累积改动中遗留的旧记忆解析 bug，保证长期记忆语义一致。
**Next**: v0.5.6 引入 Bonjour 长链接 + iOS 端 Keychain 持久化，并在真实 iOS 设备上做端到端配对验证。

## v0.5.3 — 修复截图粘贴被吞掉但未生成附件
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.3`)_
**Tag**: v0.5.3
**Test status**: — 706 passed, 0 failed —
**Changed**:
- ⌘V 监听改用 AppKit 可读对象检测，覆盖图片对象与图片文件 URL。
- 剪贴板没有 PNG 表示时，通过 `NSImage` 解码 TIFF/JPEG/HEIC 等表示并统一转成临时 PNG 附件。
**Why**: 旧代码识别到通用图片后会吞掉 ⌘V，但真正读取时只取 `.png`；macOS 截图常提供 TIFF，导致输入框看起来完全没有反应。
**Next**: 已用 Preview 复制真实截图并在安装版 App 验证缩略图与临时 PNG；继续覆盖更多第三方图片来源。

## v0.5.2 — 强制小步增量输出与异常即时反馈
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.2`)_
**Tag**: v0.5.2
**Test status**: — 706 passed, 0 failed —
**Changed**:
- 新增 `AgentOutputPolicy`，把“小步增量”定义为可测试的强制契约：每完成一个有意义步骤立即输出 1–3 行结果和下一步，不把已完成步骤攒到最终回复。
- 失败、异常或阻塞必须在发现后的下一条消息立即说明影响和处理方向；最终回复只收口结果、验证证据和剩余风险。
- 完整契约注入 `thread/start` / `thread/resume`，短提醒同时放在每个当前用户任务之前，避免长对话或旧上下文稀释规则。
- App 在命令、MCP 工具、文件变更完成时即时插入两行进度；失败事件立即插入异常、影响与处理方向，且这些运行态提示不会被长期记忆提取。
- 模型目录关闭并行工具批处理；`ensureReady()` 会比较并刷新 App 专属模型目录，现有安装不再永久沿用旧 `base_instructions`。
- 新增 21 项 `AgentOutputPolicy` 回归测试；总测试数 685 → 706。
**Why**: v0.5.1 只包含一句宽泛提示；仅加强 Prompt 的首次原生回归中，模型仍把三个工具并行执行后集中总结，因此增加 App 事件层保证。
**Next**: 继续用安装版长任务验证模型在多次工具调用之间真实产生用户可见进度，并跟进 Harness 的原生进度事件能力。
