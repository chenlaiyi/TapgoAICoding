# v0.5.305

feat(evolution): 手机端指标补齐

## 变更

- evolution-metrics.py 新增 --out（原子写 JSON 摘要）与 --quiet；evolve.sh 每轮收尾把它和反馈漏斗快照一起刷新（refresh_snapshots），失败只 WARN。
- 新增 TapgoCore.EvolutionMetricsSummary：宽容解析 state/evolution_metrics_summary.json，口径仍以 Python 指标工具为唯一真源。
- PhoneRemote.EvolutionStatus 增加 metricsSummary；H5 自进化卡片新增一行「周期 p95 · MTTR · 单轮 · tokens · 成本」，本机 App 落后时额外提示并把整行标黄。
- 测试：metrics 断言扩到 27 项（--out 原子写与内容），PhoneRemote 快照 58→64、H5 页面 74→78。

周期 p95/MTTR/单轮成本/本机落后进入手机卡片

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
