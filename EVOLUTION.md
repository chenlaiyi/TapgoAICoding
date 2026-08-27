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

## v0.3.0 — Initial shipped baseline (pre-evolution)
**Date**: 2026-08-25
**Commit**: 6422947
**Tag**: _none — pre-evolution baseline_
**Test status**: 110/110 green
**Changed**: (see git history: `git log dd13454..6422947`)
- 设置新增"账户"tab 退居 + 重新设计扫码登录界面
- 移除侧边栏"@ 插件"菜单项（保留输入框内插入技能入口）
- 管理员微信扫码登录门禁 + 输入排队/插话 + 用户消息操作条与头像昵称
**Why**: User-facing gating + UX polish before opening the self-evolution loop.
**Next**: v0.3.1 — evolution infrastructure scaffold (next entry).


## v0.3.2 — fix: evolve.sh skips SSH-integration tests by default; README test count 110→332
**Date**: 2026-08-25
**Commit**: `c141776`  _(see `git log -1 v0.3.2`)_
**Tag**: v0.3.2
**Test status**: — 332 passed, 0 failed —
**Changed**:
- fix: evolve.sh skips SSH-integration tests by default; README test count 110→332
evolve.sh now sets TAPGO_SKIP_REMOTE_INTEGRATION=1 unless WITH_INTEGRATION is set, so SSH-dependent tests (which need a real remote host at the RFC 5737 203.0.113.10 address) are skipped by default. README updated to reflect the actual 332-test count instead of the outdated 110. The evolve.sh sanity check was demoted to a warning, version bumps now source from the latest git tag, and a couple of unset-variable bugs under set -u were fixed.
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.3.3 — fix: login gate tolerates transient network blips during QR fetch + status poll
**Date**: 2026-08-26
**Commit**: _(see )_
**Tag**: v0.3.3
**Test status**: — 332 passed, 0 failed —
**Changed**:
- fix: login gate tolerates transient network blips during QR fetch + status poll
扫码登录页加载阶段增加一次 URLError 自动重试（避免 DNS/TLS 短暂抖动直接让用户看到失败页），并将轮询阶段的连续网络失败容差从 3 次（6s）放宽到 6 次（12s），对齐国内 → 海外服务器的真实网络抖动窗口。源码改动集中于 AdminLoginView.start() 与 AdminLoginView.poll()，未改 client 协议或持久化逻辑。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.3.4 — feat: 设置→外观 tab 全局字号(小/中/大),AppFont central font tokens
**Date**: 2026-08-26
**Commit**: _(see )_
**Tag**: v0.3.4
**Test status**: — 379 passed, 0 failed —
**Changed**:
- feat: 设置→外观 tab 全局字号(小/中/大),AppFont central font tokens
新增 Sources/TapgoCore/AppFont.swift:AppFontScale 枚举(small 0.85×/medium 1.00×/large 1.20×) + EnvironmentKey + AppFont.scaled(_:multiplier:)/monoScaled(size:multiplier:) 统一字号 token,所有视图 .font(.caption/.body/.title3 等) 统一改为 AppFont.scaled(...),SettingsView 新增'外观' tab(分段 picker + 实时预览),ChatView ⋮ 菜单字号切换继续走同一 UserDefaults key(tapgo.fontScale)→App 根级通过 @Environment(\.tapgoFontScale) 注入;彻底避开 dynamicTypeSize(macOS 失效)和 scaleEffect(撕裂布局)。22 个 AppFontScale 单测,总测试 357→379。修一个老 bug:ChatView StreamingIndicator struct 缺'{'导致 Swift 解析异常。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.4.0 — Harness 协议与上下文恢复升级
**Date**: 2026-08-27
**Commit**: _(see `git log -1 v0.4.0`)_
**Tag**: v0.4.0
**Test status**: — 420 passed, 0 failed —
**Changed**:
- 修复同一聊天永远不执行 `thread/resume` 的上下文断链，并在 rollout 被清理时用最近 8 轮、最多 24k 字符的本地摘录恢复。
- 对齐 Codex 0.149/0.150 JSON-RPC server-request 审批：保留顶层 request id，回复 `accept` / `decline`，未知请求失败关闭。
- 接入 `item/commandExecution/outputDelta` 与 `aggregatedOutput` 回填，真实保留 `interrupted` 状态，并为 RPC 增加 30 秒超时与 turn 后进程回收。
- 借鉴 DeepSeek Harness `dsh-v0.1.1-rc.2` 的 80% 压缩压力阈值、失败关闭和恢复原则；不嵌入仍处 Developer Preview 的 Node/Python Runtime。
- 跨会话记忆改为串行 actor 写入，校验 HTTP 状态，仅接受最多 3 条短 Markdown 要点并去重；关闭开关后不再写入或注入。
- 初始化脚本统一 harness 选择并强制最低 Codex 0.149.1；纳入此前漏提交的 AppFont/搜索测试文件，恢复干净 clone 可测试性。
**Why**: 修复原生 App 的实际上下文失忆、审批失效、终端无实时输出和旧 CLI 被误选等主链问题，同时吸收两套最新 Harness 中已经成熟且适合 Swift 客户端的设计。
**Next**: 接入 `thread/read`/`thread/compact/start` 可见状态、文件 patch 增量与 FakeTransport 两轮端到端测试。


## v0.4.1 — Harness 进程监督、JSON-RPC id 防重用、审批超时
**Date**: 2026-08-27
**Commit**: `fa917d3`
**Tag**: v0.4.1
**Test status**: — 517 passed, 0 failed —
**Changed**:
- 新增 `Sources/TapgoCore/HarnessSupervisor.swift` (200 行):包装 `HarnessTransport`,在 harness 进程意外退出时按指数退避(默认 1s→2s→4s,封顶 8s)自动重启,2 次失败后放弃并触发 `onGiveUp`;`stop()` / clean exit (code 0 / signal kill) 不触发自动重启;`onRestart` 回调让客户端在重启后重跑 JSON-RPC `initialize` 握手。
- 新增 `Sources/TapgoCore/HarnessIdAllocator.swift` (99 行):单调递增 JSON-RPC id 分配器,**永不重用**已发 id;`reserveServerId(_:)` 让服务器发来的审批 id 占位,防止本端后续 outbound 请求撞 id;`reset()` 在 supervisor 自动重启后调用,清空上一进程的 ghost id。
- 新增 `Sources/TapgoCore/ApprovalTimeoutTracker.swift` (80 行):审批超时追踪器,server→client 方向独立计时,默认 60s,超时自动 `decline`(此前只有 client→server 的 30s RPC 超时,审批可无限挂起);`sweep(now:)` 在每轮 turn 开始时跑一次,清掉过期 arm。
- 新增 `Sources/TapgoTests/FakeHarnessTransport.swift` (118 行):内存内 `HarnessTransport` 实现,`sendNotification` / `sendServerRequest` / `respond` / `respondError` / `simulateExit` / `simulateStartFailure` 全部可脚本化,毫秒级测试,无需 SSH。
- 新增 4 个测试文件共 ~80 测试:`FakeHarnessTransportTests` (18)、`HarnessIdAllocatorTests` (14)、`ApprovalTimeoutTests` (13)、`HarnessSupervisorTests` (32)。测试总数 420 → **517**。
**Why**: v0.4.0 协议升级后,harness 进程意外退出/审批挂起/id 重用三个场景没有专用覆盖,生产中出现的偶发失败难以定位;Fake harness 让协议回归不再依赖 SSH(203.0.113.10),`evolve.sh` 默认跳过真实 SSH 集成测试的同时,协议层有了独立快速反馈。
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.

## v0.4.2 — 适配 macOS 27 SDK 缺失的 SwiftUI macros plugin
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.4.3`)_
**Tag**: v0.4.3
**Test status**: — 517 passed, 0 failed —
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`：补 `import Combine`，消除 `Timer.publish` 用的 `Combine.Publishers` 未导入 warning（之前靠 SDK 26.5 隐式允许，SDK 27 收紧后会变成 warning）。
- `scripts/build-app.sh`：默认走 `xcrun -sdk macosx26.5 swift ...`，可通过 `TAPGO_SDK=macosx27.0` 覆盖。脚本入口做 SDK 存在性校验，缺 SDK 时列出已安装的 SDK 并以 exit 7 退出。
- `scripts/evolve.sh`：step 3 的 `swift build -c release --product TapgoAICoding` 同样改为 `${SWIFT[@]}`（SDK 26.5），与 `build-app.sh` 保持一致；step 8 调 `./scripts/build-app.sh` 自动复用。`swift run TapgoTests` 不动（TapgoTests 无 SwiftUI import，SDK 选择不影响）。
- **Core / Tests 完全不动**，517 项测试仍全过，`.app` bundle 在 SDK 26.5 下 release build 成功（44.8s），ld 的两条 search-path warning 是 SDK 26.5 期望 Xcode `Developer/usr/lib` 路径（与本机只有 CommandLineTools 相关，与代码无关）。
**Why**: macOS 27 SDK 的 CommandLineTools Swift 6.4 不再带 `SwiftUI.StateMacro` / `.Environment` 等外部宏的 plugin，导致 `@State private var foo` 直接报 `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`，整 app target 编译失败。这是 v0.4.0 / v0.4.1 baseline 就存在的限制（之前用户用 SDK 26.5 工具链 build，机器升级后失败），不是新代码引入的；修复策略是把脚本的 SDK 选择 pin 到最后一个仍带 SwiftUI macros plugin 的 SDK（26.5），等 Apple 在 macOS 28 重加 plugin 后用 `TAPGO_SDK=macosx27.0` 或更高显式覆盖即可。
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.4.3 — 对话独立执行与 Harness 失效恢复修复
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.4.3`)_
**Tag**: v0.4.3
**Test status**: — 572 passed, 0 failed —
**Changed**:
- 每个对话独立持有 runner、异步任务、运行状态和停止标记；切换到新对话后可立即执行，原对话继续在后台运行。
- 队列、插话、停止和目标计时改为按对话隔离；A 完成不会启动、删除或中断 B 的任务。
- 审批请求按本地 turn 命名空间和所属 runner 路由，避免并发 app-server 的相同 JSON-RPC id 串线。
- 审批使用真实 60 秒定时任务自动拒绝，兼容数字和字符串 RPC id，并在完成、停止、进程丢失时清理。
- Harness 未经显式停止却退出时立即结束旧请求/回合，code 0、信号退出与重启 spawn 失败均纳入有限重试，避免旧 continuation 永久挂起。
- 新增 `ConversationRunRegistry` 与更完整的 `HarnessSupervisor` 回归测试；测试总数 517 → 572。
**Why**: 修复“会话 A 执行时切到 B，B 只能排队；插话又会中断 A”的全局单 runner 架构缺陷，同时封堵审批超时和进程重启仍可能让任务永久卡住的两条链路。
**Next**: 增加 App target 的可注入 runner 协调器测试和长任务无事件看门狗。
