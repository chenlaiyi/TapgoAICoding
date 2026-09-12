# v0.5.304

test(evolution): canary 提升演练

## 变更

- 新增 scripts/tests/canary-promote-test.sh：fixture 仓库 + 裸 origin + 假 gh/deploy，真跑 canary-promote.sh 的 9 组场景共 31 项断言。
- 覆盖：参数缺失(2)/缺 canary appcast(3)/正常提升（appcast 入仓并推送 + gh release edit --draft=false + deploy --exclude canary）/重复提升不产生多余提交仍部署。
- 关键安全属性：推送失败(4)与 draft 提升失败(5)都会中止且不部署其余机器；其余机器部署失败报 6；Release 不存在或没有 gh 时只提示并继续。
- 顺带修掉硬编码：canary-promote 之前写死 git push origin，现在与 evolve.sh/sync-upstream.sh 一致走 tapgo_upstream_remote（EVOLVE_CANARY_REMOTE 可覆盖）。
- 新增 EVOLVE_CANARY_{REPO_ROOT,GH,DEPLOY_SCRIPT} 注入点；测试接进 run-all 与 benchmark。另加内容行引号守卫（makeHistory 内容行必须恰好 2 个引号）。

真跑推 appcast/解除 draft/部署其余机器并分级失败

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
