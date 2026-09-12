# v0.5.289

feat(evolution): 发布失败续跑

## 变更

- evolve.sh 把 publish 尾段拆成 publish_verify/push/release/deploy + publish_tail(stage)，正常流程行为不变（失败注入 79 项原样通过）。
- 新增 --publish --resume 与 --resume-from <verify|push|release|deploy>：读 evolution_state.json 的失败状态，校验 tag/HEAD/版本记录后从对应阶段续跑，跳过版本号/记录/测试/构建/commit。
- 远端真相优先：远端 tag 缺失时 release/deploy 自动回退到 push；state 无 worktreeVerified 时回退到 verify；canary 运行继承 canary host。
- 顺带修复 state.canary：此前 CANARY=0 也是非空字符串，导致每次普通发布都被记成 canary 运行。
- 失败注入矩阵扩到 106 项：新增 release/push/worktree 三类续跑、已发布状态空操作、--resume 缺 --publish 拒绝等断言。

发布中断后 --resume 从失败阶段继续，不再整轮重来

## Next

EVO-034 发布前环境预检: gh 认证 / SDK / python3 / 磁盘 / 远端可达 / tag 冲突统一预检后再启动
