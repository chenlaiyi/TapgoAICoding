# v0.5.306

fix(evolution): 指标摘要契约

## 变更

- 真机发现：evolution-metrics 只写扁平键 localAppRunning/Installed/Stale，而 App 的 EvolutionMetricsSummary 读嵌套 localApp.*——手写 Swift fixture 恰好是嵌套形状，于是单测全绿、真实产物却读不出本机漂移。
- 生产侧同时输出嵌套 localApp{installed,running,stale}（脚本用扁平键、App 用嵌套），两边同源。
- 读取侧改嵌套优先、扁平兜底，老快照不会因此失效。
- metrics 回归新增跨语言契约断言：真实 --out 产物必须含 p95CycleSeconds/mttrMedianSeconds/mttrSamples/runDurationMedianSeconds/runTokensTotal/runCostUSDTotal 与嵌套 localApp.stale。
- 真机端到端复验：把真实摘要放到 jkmacmini 的 state 后，其 /api/state 的 evolution.metricsSummary 返回 12 个键（p95=1158.7 / mttr=855 / runDuration=500 / stale=true），验证完即清理。

生产侧补嵌套 localApp + 跨语言契约断言

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
