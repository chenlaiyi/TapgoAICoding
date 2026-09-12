# v0.5.264

feat(evolution): 发布健康门禁与三机闭环

## 变更

- 新增 6 项 Bundle 健康检查并作为提交前门禁
- 发布成功后自动三机部署并回读 PID,失败写 health_failed

构建后健康检查阻断坏包;发布后自动部署三机并回读版本/PID

## Next

EVO-009 迭代指标看板: 成功率、flaky、回滚次数、周期趋势接入 `EvolutionLogView`
