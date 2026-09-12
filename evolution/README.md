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
- `scripts/evolution-metrics.py` 从记录 + `evolution_state_history.jsonl` 汇总成功率、失败、中位周期与测试总量。
- `evolution/BACKLOG.md` 是下一轮选点的单一待办清单；完成后把 `[ ]` 改为 `[x]` 并附版本号。
- `scripts/evolution-backlog.py` 提供 `list / top / validate`；Swift 侧 `TapgoCore.EvolutionBacklog` 使用同一格式驱动 App 横幅与 kickoff prompt。
- `scripts/evolution-preflight.sh` 是发布前环境预检（EVO-034）：工具链、SDK、磁盘、仓库布局、受保护清单、state 目录、origin 可达、HEAD==origin/main、gh 认证、三机 SSH、tag 冲突；失败以 12 退出且不改任何文件。
- `evolve.sh` 在算出新版本号后立即跑预检（`EVOLVE_SKIP_PREFLIGHT=1` 可跳过，`EVOLVE_PREFLIGHT_SKIP_SSH=1` 只跳过三机连通性）；`--publish --resume` 同样先过预检（tag 用 `--expect-existing-tag`）。
- 三机部署目标在 `scripts/fleet-hosts.sh` 维护唯一真源，`deploy-fleet.sh` 与预检共用，避免主机清单漂移。
- 发布中断后用 `./scripts/evolve.sh --publish --resume` 续跑：从 `evolution_state.json` 的失败阶段（verify/push/release/deploy）继续，不重做版本号、记录、测试、构建与 commit；`--resume-from <stage>` 可显式指定入口。
- `scripts/evolution-maintenance.sh` 是月度维护入口：跑回滚演练 + 指标归档，写 `state/maintenance_history.jsonl`，成功静默、失败才通知。
- `scripts/install-evolution-maintenance.sh` 注册 launchd 任务（每月 1 日 10:00，`RunAtLoad=false`）；`--print / --run-now / --uninstall` 分别用于预览、立即执行与卸载。
- 通知默认走 macOS 通知中心；接入 Bark/webhook 时把 `EVOLVE_MAINTENANCE_NOTIFY` 指向一个接收 `<title> <message>` 的包装脚本。
