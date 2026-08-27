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
**Commit**: `623efa3`
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
