# v0.5.302

test(evolution): 部署端到端演练

## 变更

- 新增 scripts/tests/deploy-fleet-test.sh：合成 .app + fake ssh/scp 在本机执行远端 heredoc，覆盖 dry-run 三机、本地安装/回读、本地重启+界面断言、远端安装+回读、断言经 ssh 管道、跳过开关、目标过滤，共 32 项断言。
- 修复 deploy-fleet 缺陷 1：install_remote 由 if ! 调用时 bash 关闭 errexit，scp/ssh 安装失败被后续步骤掩盖并打印假的 verified；现在每步显式判状态并返回 1。
- 修复缺陷 2：目标全部被过滤掉时 TARGETS 为空数组，bash 3.2 + set -u 下直接 unbound 崩溃；改为 ${TARGETS[@]+...} 惯用法。
- 修复缺陷 3：远端安装未确保目标父目录存在（真实 /Applications 存在所以从未暴露），现在 mkdir -p 目标目录。
- deploy-fleet 暴露 EVOLVE_FLEET_* 注入点（APP/LOCAL_DEST/REMOTE_APP/SSH/SCP/RESTART_SCRIPT/UI_ASSERT_SCRIPT/RESTART_WAIT/TARGETS_OVERRIDE/OPEN/PGREP），真实环境全部走默认值。

真跑 deploy-fleet 并修掉三个真实缺陷

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
