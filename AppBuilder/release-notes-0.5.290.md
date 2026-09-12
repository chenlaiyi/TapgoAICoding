# v0.5.290

feat(evolution): 发布前环境预检

## 变更

- 新增 scripts/evolution-preflight.sh：检查 git/python3(>=3.9)/xcrun+swift SDK、磁盘、仓库关键文件、受保护清单、state 目录可写、origin 可达、HEAD==origin/main、gh auth、三机 SSH、tag 冲突；失败列原因并以 12 退出。
- evolve.sh 在算出新版本号后立即执行预检（--publish --resume 同样先过，tag 用 --expect-existing-tag），EVOLVE_SKIP_PREFLIGHT=1 跳过，EVOLVE_PREFLIGHT_SKIP_SSH=1 只跳过三机连通性。
- 新增 scripts/fleet-hosts.sh 作为三机部署目标唯一真源，deploy-fleet.sh 与预检共用，消除主机清单漂移。
- 新增 30 项预检回归与 14 项失败注入断言（预检失败零改动、预检通过照常发布、续跑被预检拦住）。
- 逐层实测：预检真实运行 local 9 项、publish 14 项（含两台远端 Mac SSH）全通过。

gh/SDK/磁盘/远端/三机/tag 统一预检，失败零改动退出

## Next

EVO-035 运行态 schemaVersion: state json/jsonl 加版本字段与迁移，防止字段演进静默失真
