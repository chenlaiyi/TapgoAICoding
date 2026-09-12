# v0.5.309

test(evolution): canary 全链路演练

## 变更

- 失败注入矩阵新增 S35：用真实 canary-promote.sh 与真实 deploy-fleet.sh（fake ssh/scp 在本机执行远端 heredoc）跑 evolve.sh --publish --canary，而不是像 S16/S17c 那样用 stub。
- 验证链路：灰度 deploy --only → release 契约暂存 appcast → canary-promote 拷 appcast 入仓/提交/推送 → gh release edit --draft=false → deploy --exclude → 状态 published 且 canary=fakehost。
- harness 增强：run_evolve 允许调用方覆盖 EVOLVE_DEPLOY_SCRIPT/EVOLVE_CANARY_PROMOTE_SCRIPT；release stub 在 TAPGO_CANARY=1 时复刻真实 appcast staging 契约。
- 断言含 origin main 前进 3 个提交、灰度与其余机器都拿到 0.5.2、gh undraft 被调用、UI 断言经真实 deploy-fleet 下发、日志无 ERROR。失败注入矩阵 151→162 项。

真实 promote + 真实 deploy-fleet 跑通 evolve 灰度

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
