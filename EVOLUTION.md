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

## v0.5.14 — 队列卡片宽度改为输入框的 90%
**Date**: 2026-08-29
**Commit**: a7ffa45
**Tag**: v0.5.14
**Test status**: — Release App 构建通过（SwiftUI 宽度常量改动，无对应单测）；三机安装重启回读 0.5.14 正常 —
**Changed**:
- `queueStatusBar` 末尾宽度约束从 `contentWidth` 改为 `contentWidth * 0.90`：队列卡片固定为输入框卡片的 90% 并整体居中，恢复「排队卡片比输入框略窄」的层次感。
- 同步更新两处注释（queueStatusBar 与队列面板说明），避免后续再被改回同宽。
**Why**: 上一版把队列卡片改成与输入框同宽后，用户反馈宽度弄错了，明确要求队列卡片应为输入框卡片宽度的 90%。
**Next**: 收集 720 / 980 两种内容宽度下的视觉反馈，必要时再微调比例。

## v0.5.13 — 队列卡片 Codex 紧凑样式 + 拖拽排序
**Date**: 2026-08-29
**Commit**: 5ccb271
**Tag**: v0.5.13
**Test status**: — TapgoCore 1246 passed, 8 failed (失败均为 RemoteSSH/RemoteDirectoryLister 远端集成用例，与本次 UI 改动无关) —
**Changed**:
- 输入框上方排队卡片改成 Codex 式紧凑面板：行内左右 padding 12 / 上下 8、`minHeight` 由 64 改为 44、缩略图 46pt → 36pt、行间用 1px 25% 透明 Divider 自然分隔，去掉每行手柄图标与外圈背景。
- 行尾去掉「更多」常驻按钮（编辑消息与关闭排队迁移到右键菜单），只保留「调整方向」与「删除」两个图标按钮，整体右侧留白收紧。
- 新增 macOS 14 风格的拖拽排序：长按行内任意位置拖动到目标行，`store.moveQueued(_:to:)` 仅在 active conversation 且未在 steering 时生效，避免抢走正在注入的消息。
- 拖拽时源行半透明，目标行显示顶部/底部品牌色 3pt 胶囊作为插入位指示线，`dropDestination` 通过 y 与 rowHeight/2 比较决定 before/after。
- 输入框右侧主操作按钮合并：运行时只显示红色「停止」，空闲时只显示品牌色「发送」，互斥展示避免视觉冗余；快捷键与无障碍标签保持不变。
- `SessionStore` 新增 `moveQueued(_ id: String, to newIndex: Int)`：仅改写当前 active 对话的子数组，其他会话顺序保持原状。
**Why**: 用户参照 Codex 当前界面要求队列卡片更紧凑、行内右侧不要过大空白，并且希望可以直接拖动重排多条排队的先后顺序；同时合并输入框右侧的「停止 / 发送」两个按钮。
**Next**: 收集拖拽在不同行数和长文本下的真实手感反馈，再决定是否加入键盘 ⌥↑ / ⌥↓ 备用排序快捷键。

### v0.5.13 — Hotfix: 队列卡片高度自适应
**Date**: 2026-08-29
**Commit**: 77aaad5
**Tag**: (v0.5.13 仍在 v0.5.13 上累积修复，标签保留 v0.5.13)
**Test status**: SDK 26.5 Release App build 通过
**Changed**:
- `queueStatusBar` 的 ScrollView 高度从固定 `.frame(maxHeight: 240)` 改为按 `activeQueue.count` 动态计算：`min(count * 45 + 6, 240)`pt；1 条排队仅占 1 行 45pt，超过 6 条才进入内部滚动。
**Why**: 用户反馈"之前改过自适应，现在又不自适应了"——单条排队时卡片不该留 240pt 空白。
**Next**: 收尾。

## v0.5.12 — Codex 式输入区排队卡片
**Date**: 2026-08-29
**Commit**: b93bed6
**Tag**: v0.5.12
**Test status**: — 队列与并发核心回归 43/43；SDK 26.5 Release App build + 本机原生多条队列视觉与交互回归通过 —
**Changed**:
- 排队卡片与输入框同宽并直接衔接，使用统一深色圆角面板，取消逐行分隔线和多余的视觉层级。
- 每条排队消息固定为紧凑单行；真实图片附件显示圆角缩略图，多图显示数量，长文本自动截断。
- “调整方向”、删除与更多操作固定右对齐，统一为低强调灰色；更多按钮取消突兀的圆形底色。
- 队列最多显示五行后内部滚动，保留编辑、删除、关闭排队与真实 same-turn steer 行为。
- 延续本机已完成的删除：套餐用量组件、账户限额请求/事件、状态模型与相关测试不再进入 App。
**Why**: 用户要求输入框上方的排队区域与 Codex 当前界面一致，同时确保已经删除的套餐用量不会被旧发布基线重新带回。
**Next**: 根据更多真实附件数量和极窄窗口反馈继续微调截断阈值。

## v0.5.11 — 响应式环境信息与来源卡片
**Date**: 2026-08-29
**Commit**: e710977
**Tag**: v0.5.11
**Test status**: — 响应式布局 7/7；macOS Release build + 原生宽窄窗口回归通过 —
**Changed**:
- 右侧空间足够时自动显示 Codex 式圆角卡片，集中展示真实变更行数、运行位置、Git 分支、提交/推送与比较分支入口。
- 来源区展示当前会话最近三张真实图片缩略图；没有图片时显示明确空态，不制造虚假来源。
- 窗口变窄时卡片自动隐藏，恢复宽度后重新出现；手动轨迹栏打开时卡片主动让位。
- 使用聊天区 trailing safe-area inset 保持 `ChatView` 与输入控件身份稳定，宽窄切换不丢焦点、不清空草稿。
**Why**: 用户需要在宽窗口充分利用右侧空白查看环境与来源，同时窄窗口仍优先保证会话和输入空间。
**Next**: 根据真实使用反馈微调宽度阈值与卡片密度。

## v0.5.10 — 套餐用量固定右对齐
**Date**: 2026-08-29
**Commit**: 6cc0517
**Tag**: v0.5.10
**Test status**: — 套餐空态 17/17；macOS Release build + 三机安装回读通过 —
**Changed**:
- 输入区下方的套餐用量 chip 改为在内容宽度内固定靠右，不再因外层居中 frame 看起来漂到中间。
- 保留 v0.5.9 的步骤进度、真实变更统计、最新活动白色流光与账户限额能力。
**Why**: 共享任务在 v0.5.9 发布后补齐了用户此前明确要求的“输入框下方右侧”对齐；单独发布新版本，避免改写已推送标签。
**Next**: 继续验证不同窗口宽度和长套餐名称下的右对齐稳定性。

## v0.5.9 — Codex 式步骤进度、真实变更统计与运行流光
**Date**: 2026-08-29
**Commit**: cd5db2d
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

## v0.5.15 — Markdown 视觉升级 + composer 底部 metrics 重写 + 真实账户 rateLimits 接入
**Date**: 2026-08-29
**Commit**: 4bf25fe
**Tag**: v0.5.15
**Test status**: 1290 passed / 8 SSH 集成测试因 RFC 5737 测试地址 203.0.113.10 不可达失败（与本版无关）；Release App 构建通过（SDK 26.5，无 SwiftUI 宏插件问题）
**Changed**:
- **Markdown 视觉升级**：
  - `AppFont` 新增公共 `pointSize(for:multiplier:)` helper：纯数值返回 body / callout / footnote 等文本样式按用户字号偏好计算后的 point size，供 Markdown 解析层在不引入 SwiftUI 依赖的前提下取到字号。
  - `MarkdownMessageView` 把 `Block.para` 由预先构造的 `AttributedString` 改为保留原始 `MarkdownSegment`；渲染时按当前 `appFontScale.multiplier` 重新构造 AttributedString，正文 / 行内代码 / bold / link / strikethrough 字号一致跟随用户偏好。
  - 新增 `paragraphView(segs:)`：body 字号 + 3pt lineSpacing + `fixedSize(horizontal:false, vertical:true)`，长段落更易扫读且按内容撑开高度，避免被默认 single-line 容器压扁。
  - `ListView` 紧凑化：marker 用 footnote 等宽字 + `labelTertiary` 弱化色；marker 列固定 14/18pt trailing 对齐，列表项 spacing 收紧到 2pt，外层 2pt leading 缩进区分 chat 内边距。
  - 行内 `inline` 代码视觉升级：字号比正文小 1.5pt、`brandStrong` 文字色 + `moduleBg` 圆角背景底色，仿 chip 风格但保留 AttributedString 单一渲染通路。
  - `TaskListView` checkbox 用 `symbolRenderingMode(.hierarchical)` + 与正文同档字号；unchecked 落到 `labelTertiary`，色调与正文协调。
  - `QuoteView` 改为接受 `MarkdownSegment` 而非预渲染的 `AttributedString`，引用内的 inline code / bold / link 与正文保持一致。
- **Composer 底部 metrics 重写（5 个文本 chip → 圆形 meter + 弹窗）**：
  - 旧 `composerMetricsBar` 的 rounds · steps / LLM 时长 / 缓存命中 / 输入 tokens 5 个文本 chip 整行删除；替换为一个 `CircularContextMeter`，按"实时 rateLimits 压力 → 上下文窗口使用率"优先级显示百分比。
  - 详细信息挪进悬停 / 点击弹出的新组件 `ModelUsagePopover`：套餐用量 / 5h 与 weekly 窗口剩余与重置时间 / credits 余额 / 输入输出 tokens / 平均缓存命中 / 上下文上限。
  - 弹窗默认鼠标移出自动关闭；用户点击后进入 pinned 状态，再次点击或外部关闭清除 pinned。
- **真实账户 rateLimits 接入**：
  - 新增 `TapgoCore/RateLimits`：`RateLimitsSnapshot` / `RateLimitsWindow` / `RateLimitsCredits` / `RateLimitsPlanType` 与 `RateLimitsSnapshot.fromJSON(_:)`，兼容 harness 直接返回 payload 与包 `result` 字段两种形态。
  - 新增 `TapgoCore/ModelUsageMetrics`：`averageCacheHitPercent(turns:)` 与 `percentOfWindow(used:window:)`。
  - `CodexHarnessClient.readRateLimits()` 走 JSON-RPC `account/rateLimits/read`，`initialize` / `initialized` 之后调用，幂等；返回失败时返回空 snapshot 让 UI 仍可显示"等待服务端响应"。
  - `ExecEvent` 解析 harness 推送的 `account/rateLimits/updated` 通知（`ExecEventParserTests` +57 行覆盖），与主动轮询合并到 `SessionStore.rateLimits`。
  - `SessionStore` 增加 `rateLimits` / `rateLimitsLoading` / `rateLimitsError` 状态 + `refreshRateLimits()`；每次 popover 打开时刷新。
- **Composer 清空按钮误显修复**：
  - 新增 `tapgoIsComposerUserContentEmpty(text:attachedImageCount:)` helper，过滤 NBSP / 全角空格 / 零宽字符。空 composer 不再误显 `xmark.circle.fill`。
- 同步把 `makeHistory()` 上一轮漏补的 v0.5.14 条目 prepend，避免 App 内『自进化日志』页面落后于实际版本。
**Why**: 上一轮 v0.5.14 把队列卡片宽度调到 90% 后，本轮集中处理三类遗留：(a) Markdown 段落 / 列表 / 行内代码视觉层次弱；(b) composer 底部 5 个文本 chip 一直展开，与 chat 内其余位置权重不平衡；(c) v0.5.6 的"套餐用量"chip 一直用 thread 累计 token 做占位，需要接入真实 harness `account/rateLimits` 数据；三件事都集中在"输入 / 消息内容可读性"这条主线上，因此合并发 v0.5.15。
**Next**: 真机视觉回归 composer 底部圆环在不同上下文压力下的颜色梯度；为 ModelUsagePopover 增加可点击复制剩余 / 重置时间；评估是否把 5h / weekly 窗口快捷指示器放进 chip 头部避免每次点开。
