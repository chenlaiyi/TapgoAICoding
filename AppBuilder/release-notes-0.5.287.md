# v0.5.287

feat(evolution): 月度维护自动化

## 变更

- 新增 scripts/evolution-maintenance.sh：串联 rollback-drill + evolution-archive，写 maintenance_history.jsonl，失败给一行原因并触发通知。
- 新增 launchd 模板与 install-evolution-maintenance.sh：每月 1 日 10:00 执行，RunAtLoad=false，支持 --print/--run-now/--uninstall。
- 通知默认走 macOS 通知中心，可用 EVOLVE_MAINTENANCE_NOTIFY 换成 Bark/webhook 包装脚本；--no-notify 关闭。
- 指标接入 Python/Swift/H5：maintenanceRuns/lastMaintenanceStatus/lastMaintenanceAt 显示在指标详情与手机端自进化卡片。
- 新增 40 项维护回归与 benchmark maintenance-helper；EVO-032 完成并补 P8 运维韧性 backlog。

定时跑回滚演练与指标归档，成功静默、异常才通知

## Next

EVO-033 发布失败续跑: `--resume` 从失败阶段继续（push 成功但 release 失败时不再整轮重来）
