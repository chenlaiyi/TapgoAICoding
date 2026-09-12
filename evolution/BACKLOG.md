# Self-evolution backlog

优先级从高到低；每次迭代完成后更新状态，并在 `evolution/versions/` 留记录。

## P0 — 闭环正确性

- [x] **EVO-001 原子性加固**：路径白名单、并发锁、语义化版本、提交前测试+构建、失败回滚（v0.5.257）
- [x] **EVO-002 结构化版本真源**：每版 JSON 记录，日志/release notes 由记录渲染（v0.5.258）
- [x] **EVO-003 失败注入矩阵**：测试/构建/发布/脏路径/重复 tag 场景可重复验证（v0.5.259）
- [x] **EVO-004 历史日志去重 + 指标**：清理 v0.5.70/71/102/106/107/230/232 重复节；状态历史 JSONL + 指标（v0.5.260）
- [x] **EVO-005 backlog 驱动选点**：Python/Swift 双解析，面板显示下一项，prompt 与 `nextActions` 自动注入（v0.5.261；state.nextActions 修复见 v0.5.262）
- [x] **EVO-006 分支隔离**：每轮在 `codex/evolution-vX.Y.Z` 提交，原分支只 fast-forward；publish 推送审计分支（v0.5.263）

## P1 — 可观测与验证

- [x] **EVO-007 发布前健康门禁**：Bundle 版本/结构/签名 6 项检查，失败停在 commit 前并回滚（v0.5.264）
- [x] **EVO-008 三机部署纳入闭环**：publish 成功后自动 `deploy-fleet.sh` 并回读版本/PID，失败写 `health_failed`（v0.5.264）
- [x] **EVO-009 迭代指标看板**：成功率、失败/回滚、周期趋势与 backlog 接入 `EvolutionLogView`（v0.5.265）
- [x] **EVO-010 测试 flaky 追踪**：解析失败 section/用例，自动重跑失败 section，区分环境失败与真实回归并写运行历史（v0.5.266）

## P2 — 体验与安全

- [x] **EVO-011 自进化进度 UI**：9 阶段进度、停止请求、Token/用时、diff 审阅接入会话横幅（v0.5.267）
- [x] **EVO-012 自改门禁**：受保护路径变更需精确内容 token 审批，未审批拒绝启动（v0.5.268）
- [x] **EVO-013 iOS 版本序列分离**：iOS 1.0.x 历史移入 `evolution/ios/EVOLUTION.md`，主日志仅留指针（v0.5.269）
- [ ] **EVO-014 旧日志归档**：把 v0.5.5 之前与 iOS 历史移入 `evolution/archive/`，主日志保持可读
- [ ] **EVO-015 worktree 隔离**：分支隔离后的强化项，每轮在独立 git worktree 执行，主 checkout 零改动
