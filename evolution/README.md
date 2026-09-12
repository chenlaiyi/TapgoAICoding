# Evolution records

`evolution/versions/vX.Y.Z.json` 是自进化版本历史的结构化真源。每个已发布版本一个文件，
`EVOLUTION.md` 的对应小节和 `AppBuilder/release-notes-X.Y.Z.md` 都由它渲染。

## Schema

```json
{
  "version": "0.5.258",
  "tag": "v0.5.258",
  "date": "2026-09-12",
  "scope": "mac",
  "message": "feat(evolution): ...",
  "changes": ["..."],
  "details": "...",
  "why": "...",
  "next": "...",
  "testStatus": "— N passed, 0 failed —",
  "commitSha": null
}
```

- `scope`: `mac` 或 `ios`；iOS 条目标题渲染为 `## vX.Y.Z (iOS) — ...`。
- `commitSha` 允许为 `null`：commit 前无法自引用最终 SHA，真实 SHA 记录在运行态 `evolution_state.json`。
- 新版本从 v0.5.258 起必须有记录；更早历史仍以 `EVOLUTION.md` 为兜底。

## Commands

```bash
python3 scripts/evolution-records.py add --version 0.5.258 --message "..."   --details "..." --next "..." --test-status pending
python3 scripts/evolution-records.py render-entry --version 0.5.258
python3 scripts/evolution-records.py render-notes --version 0.5.258
python3 scripts/evolution-records.py set-test-status --version 0.5.258 --value "— N passed, 0 failed —"
python3 scripts/evolution-records.py validate --require-rendered --check-current
```

`evolve.sh` 已接入上述流程，并额外支持 `--why` 与可重复 `--change` 写入记录。

- `scripts/tests/evolution-records-test.sh` 覆盖 schema、渲染、重复版本拒绝、test-status 更新与当前版本一致性。
- `scripts/tests/evolve-failure-injection-test.sh` 用临时 git 仓库注入测试失败、构建失败、发布失败、未覆盖脏路径等场景，验证回滚与状态机。
- `scripts/evolution-metrics.py` 从记录 + `evolution_state_history.jsonl` 汇总：成功率/失败、周期中位与 **P95/max**、**MTTR**（失败 → 其后第一个终端成功，同版本 `--resume` 或下一版；含未恢复失败计数）、**单轮墙钟时长**（median/P95/总计）与可选 token/成本。
- 单轮成本来自 `evolution_state*.json` 的 `durationSeconds`/`tokens`/`costUSD`（state schema v3）：时长由 `evolve.sh` 自动记录，token/成本由 harness 通过 `EVOLVE_RUN_TOKENS` / `EVOLVE_RUN_COST_USD` 提供，缺失即留空不估算。
- `evolution/BACKLOG.md` 是下一轮选点的单一待办清单；完成后把 `[ ]` 改为 `[x]` 并附版本号。
- `scripts/evolution-backlog.py` 提供 `list / top / validate`；Swift 侧 `TapgoCore.EvolutionBacklog` 使用同一格式驱动 App 横幅与 kickoff prompt。
- 单轮成本归因（EVO-041）：App 在自进化会话（`evolutionMode` / `evo-` 前缀线程）每次拿到 token 用量时，把该线程累计值原子写入 `state/evolution_cost.json`（`EvolutionCostSnapshot`，5 秒/1000 token 节流，不写无法核实的美元金额）；`evolve.sh` 在版本号确定后解析：`EVOLVE_RUN_TOKENS`/`EVOLVE_RUN_COST_USD` 优先（source=env）→ 否则取「上次发布记录 tokens → 本次快照」的增量（source=app-snapshot-delta）→ 都没有就留空不估算。来源与数值一起写进 `evolution_state*.json`（state schema v4 的 `costSource`）。
- `scripts/evolution-deps.sh` 是外部依赖探测的唯一真源（EVO-040）：`evo_detect_sdk`（`TAPGO_SDK` 显式 → 偏好 `EVOLVE_SDK_PREFERRED`（默认 macosx26.5）→ 本机最新已装 SDK → xcrun 默认，回退时打 WARNING）、`evo_detect_codex`（`EVOLVE_CODEX_BIN` → PATH → /opt/homebrew/bin → /usr/local/bin → ~/.local/bin）、`evo_require_tool`、`evo_deps_report`。
- H5/App 字段契约（EVO-053）：`Evolution: H5 field contract` 测试把 App 真实序列化的 `evolution` JSON 与 `app.js` 真实读取的键做双向对照——H5 读的键必须存在，序列化里未被 H5 读取的键必须在白名单内；嵌套对象按「点号路径 ↔ app.js 表达式」逐条对照（funnel 用 `drafts.total`/`registered.shipped`/`conversion.registeredToShipped` 等）。
- H5 渲染执行级测试（EVO-054）：`scripts/tests/evolution-h5-render.mjs` 用最小 DOM stub 在 node 里加载真实 `app.js`，通过真实 fetch 回调驱动 `refresh()` → `renderEvolution()`，断言自进化卡片各行的文案（阶段进度、benchmark/model/backlog、p95/MTTR/tokens/成本、漏斗百分比、回滚与维护时间格式）与 `hidden` 语义；同一份 fixture（`evolution/h5-fixtures/evolution-state.json`）由 Swift 契约测试校验「仍是合法服务器 payload 且覆盖 app.js 读取的每个键」，两侧一起锁住形状与行为。
- 双实现一致性（EVO-052）：`Evolution: python/swift metrics consistency` 测试用同一份 fixture 同时跑 `scripts/evolution-metrics.py` 与 `TapgoCore.EvolutionMetrics.load`，比对 iterations/published/failed/successRate/中位与 P95 周期/MTTR（含样本数与未恢复计数）/单轮时长与 token/成本/回滚演练数/维护数/backlog 共 16 项。改动任一侧失败集合或口径时它会立刻失败。
- 指标摘要契约：`evolution_metrics_summary.json` **同时**提供扁平键（`localAppRunning/…`，脚本用）与嵌套 `localApp{installed,running,stale}`（App 用）；`EvolutionMetricsSummary` 嵌套优先、扁平兜底。指标回归里有一条"跨语言契约"断言：真实 `--out` 产物必须包含 App 读取的全部键（v0.5.306 补）。
- 指标摘要（EVO-047）：`evolution-metrics.py --out` 原子写 `state/evolution_metrics_summary.json`（evolve.sh 每轮收尾与漏斗快照一起刷新，失败只 WARN）；`TapgoCore.EvolutionMetricsSummary` 宽容解析，手机端 H5 自进化卡片据此显示「周期 p95 / MTTR / 单轮时长 / tokens / 成本 / 本机 App 落后」一行（落后时标黄色）。
- canary 全链路（EVO-050）：失败注入矩阵的 S35 用真实 `canary-promote.sh` + 真实 `deploy-fleet.sh`（fake ssh/scp 在本机执行远端 heredoc）跑通 `evolve.sh --publish --canary`：灰度单机安装 → release 契约暂存 appcast → 解除 draft → 其余机器部署 → 状态 published 且记录 canary host。
- canary 提升演练（EVO-046）：`scripts/tests/canary-promote-test.sh` 在 fixture 仓库 + 假 gh/deploy 上真跑 `canary-promote.sh` 的全部分支——推 appcast 失败(4)/draft 提升失败(5)/其余机器部署失败(6) 都会显式失败，且前两者不会继续部署；远端名走 `tapgo_upstream_remote`（可用 `EVOLVE_CANARY_REMOTE` 覆盖），`EVOLVE_CANARY_{REPO_ROOT,GH,DEPLOY_SCRIPT}` 为注入点。
- 部署演练（EVO-045）：`scripts/tests/deploy-fleet-test.sh` 用合成 .app + fake ssh/scp 在本机执行远端 heredoc，真跑 deploy-fleet 的安装/版本回读/界面断言管道/失败传播/目标过滤；deploy-fleet 暴露 `EVOLVE_FLEET_{APP,LOCAL_DEST,REMOTE_APP,SSH,SCP,RESTART_SCRIPT,UI_ASSERT_SCRIPT,RESTART_WAIT,TARGETS_OVERRIDE,OPEN,PGREP}` 注入点（真实环境走默认值）。
  - 约束：ssh 会把远端命令的参数用空格拼成一条命令，所以**不能传空参数**（会消失、导致后续参数前移）、远端路径**不能含空格**（会被拆开）。因此部署脚本用 `-` 哨兵表示"用默认路径"，默认 `/Applications/Tapgo AICoding.app` 写在远端脚本内部；`EVOLVE_FLEET_REMOTE_APP` 必须是含空格即拒绝、且以 `.app` 结尾的覆盖值。
- UI 快照基线（EVO-044）：`preview-evolution-ui.sh` 的渲染在同机确定性（实测两次逐字节一致），`scripts/evolution-ui-diff.py` 与 `evolution/ui-baseline/evolution-ui.png` 做像素门禁——字节相同直接通过，否则按「通道差 > 8 的像素占比 ≤ 0.1%」判定并给出差异 bbox；缺 Pillow 且字节不同会以 exit 3 明确报告"无法比对"而不是假装通过。改 UI 后用 `./scripts/tests/evolution-ui-snapshot-test.sh --update-baseline` 刷新基线并提交。
- 本机 App 漂移留痕（EVO-043）：本机 App 按约定不在发布中重启，`evolve.sh` 会用 `evolution-ui-assert.sh --print-running-version` 探测**正在运行**的版本，写进 state 的 `localApp{installed,running,stale}`；落后时打 WARN 并在总结里给出 `./scripts/restart-and-resume.sh`。`evolution-metrics.py` 输出 `local app: running=… installed=… (stale|fresh)`。
- `scripts/evolution-ui-assert.sh` 断言"运行中的界面真的可用且是新版本"（EVO-039）：读 UserDefaults 的 H5 token → 找 PID 的 LISTEN 端口 → `/api/state` 的 `appVersion` 必须等于期望版本 → `/r/<token>` 骨架引用 app.js → `/r/<token>/assets/app.js` 含界面标记（默认 evolutionCard）→ 无 token 请求必须 403/404。退出码 21–28 区分失败原因，`--json` 可机读。
- `deploy-fleet.sh` 在版本/PID 回读后对远端用 `ssh host bash -s < scripts/evolution-ui-assert.sh` 执行该断言（不依赖远端仓库版本），本地仅在 `--restart-local` 时断言；失败即部署失败，`EVOLVE_SKIP_UI_ASSERT=1` 可跳过。
- `scripts/evolution-feedback-funnel.py` 量化反馈闭环（EVO-038）：`snapshot` 子命令把结果原子写成 `state/feedback_funnel.json`（`--out -` 打印到 stdout），evolve.sh 每轮收尾刷新一次（失败只 WARN）。
- App 侧 `TapgoCore.FeedbackFunnelSnapshot` 宽容解析该快照：指标详情新增「反馈草稿 / 反馈转化 / 反馈等待」三张卡，手机端自进化卡片新增一行「反馈漏斗：drafts 开/总 · 注册 · 发布 · 转化」（EVO-042）。：`drafts → registered → shipped` 三阶段计数、转化率、等待时长（median/P95）与陈旧告警（`--stale-days`，默认 30；`--fail-on-stale` 可当门禁用）。
- 反馈 provenance 约定：草稿写 `discoveredAt`；提升进 `registry.json` 时补 `registeredAt`（入库日期）、`origin`（manual/draft）、`sourceDraft`（回指草稿）、`fixedIn`（真正修掉该问题的发布 tag）。`fixedIn` 早于 `registeredAt` 的条目算“回填”，只计入 shipped 计数、不编造等待时长；发布日缺失（早于结构化版本记录）计入 `unknownReleaseDate`。
- `scripts/evolution-remote-lock.sh` 是跨机互斥锁（EVO-037）：`acquire` 在锁陈旧（`started` 超过 `EVOLVE_LOCK_TTL_SECONDS`，默认 14400s）时自动回收，元数据读不出 `started` 时只报 HELD 不自动接管；`reclaim` 是显式抢占（force-with-lease，`evolve.sh --break-remote-lock` 走它）；`status` 输出 `ttlSeconds/ageSeconds/remainingSeconds/stale`。
- `scripts/evolution-schema.py` 是运行态 schema 注册表与门禁（EVO-035）：`status` 看版本分布，`ensure` 给历史记录补章 `schemaVersion` 后校验，`validate` 只读校验；未来版本以 13 退出，读者（Python/Swift/H5）保持宽容。
- 当前版本：`evolution_state.json` / `evolution_state_history.jsonl` = v2，`evolution_progress.json`、`test_run_history.jsonl`、`evolution_benchmark_history.jsonl`、`model_eval_history.jsonl`、`rollback_drill_history.jsonl`、`maintenance_history.jsonl` = v1；新增 artifact 必须先在 registry 登记。
- `scripts/evolution-preflight.sh` 是发布前环境预检（EVO-034）：工具链、SDK、磁盘、仓库布局、受保护清单、state 目录、origin 可达、HEAD==origin/main、gh 认证、三机 SSH、tag 冲突；失败以 12 退出且不改任何文件。
- `evolve.sh` 在算出新版本号后立即跑预检（`EVOLVE_SKIP_PREFLIGHT=1` 可跳过，`EVOLVE_PREFLIGHT_SKIP_SSH=1` 只跳过三机连通性）；`--publish --resume` 同样先过预检（tag 用 `--expect-existing-tag`）。
- 三机部署目标在 `scripts/fleet-hosts.sh` 维护唯一真源，`deploy-fleet.sh` 与预检共用，避免主机清单漂移。
- 月度维护默认带 `--full-build`（EVO-049）：演练除了校验归档可解包 + health-check + tag 工作树干净，还会在 detached worktree 里做一次 `swift build -c release`——「可恢复」不只是归档能解压，还要证明该 tag 现在仍能从源码编译。维护历史写 `drill.fullBuild`，`evolution-metrics.py` 输出 `rollback drill: … fullBuild=yes/no`。
- 月度维护触发与验证：`launchctl kickstart -k gui/$(id -u)/com.tapgo.aicoding.evolution-maintenance` 可手动跑一次（等价于每月 1 日 10:00 的定时任务）；验证三件事——`launchctl print` 的 `runs`/`last exit code`、`state/maintenance_history.jsonl` 新记录、`~/Library/Logs/TapgoAICoding/evolution-maintenance.log` 输出。
- 维护告警自检（EVO-051）：`./scripts/evolution-maintenance-selftest.sh` 会装一个临时 LaunchAgent（独立 Label、RunAtLoad、注入必失败演练桩 + 通知捕获 + 临时 state），在**真实 launchd 上下文**验证「失败 → 告警」链路，跑完自动 bootout 并删除 plist——生产任务与 state 不受影响；`--use-system-notify` 可改走真实 osascript（会弹通知），`--print`/`--keep` 分别用于查看 plist 与保留排查目录。
- 维护告警链路：失败时 `evolution-maintenance.sh` 默认走 `osascript display notification`（可用 `EVOLVE_MAINTENANCE_NOTIFY` 换成 Bark/webhook 包装脚本）。回归里用假 osascript 校验 `display notification "<原因>" with title "Tapgo 自进化维护失败"` 的转义与内容。
- 发布中断后用 `./scripts/evolve.sh --publish --resume` 续跑：从 `evolution_state.json` 的失败阶段（verify/push/release/deploy）继续，不重做版本号、记录、测试、构建与 commit；`--resume-from <stage>` 可显式指定入口。
- `scripts/evolution-maintenance.sh` 是月度维护入口：跑回滚演练 + 指标归档，写 `state/maintenance_history.jsonl`，成功静默、失败才通知。
- `scripts/install-evolution-maintenance.sh` 注册 launchd 任务（每月 1 日 10:00，`RunAtLoad=false`）；`--print / --run-now / --uninstall` 分别用于预览、立即执行与卸载。
- 通知默认走 macOS 通知中心；接入 Bark/webhook 时把 `EVOLVE_MAINTENANCE_NOTIFY` 指向一个接收 `<title> <message>` 的包装脚本。
