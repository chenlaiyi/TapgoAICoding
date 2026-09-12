# v0.5.311

test(evolution): 双实现指标一致性

## 变更

- 新增 Evolution: python/swift metrics consistency 测试：同一份 fixture（含 canary_failed 与一次失败后恢复）同时跑 evolution-metrics.py 与 TapgoCore.EvolutionMetrics.load，比对 16 个关键指标。
- 首个发现：Python 的 FAILED 集合缺 canary_failed，而 Swift failedStatuses 有它——canary 失败时 CLI 与 App 会给出不同的失败数与成功率。已把两侧对齐（状态机确实会写 canary_failed）。
- 比对项：iterations/published/failed/successRate、中位与 P95 周期、MTTR（中位/样本数/未恢复）、单轮时长/token/成本、回滚演练数、维护数、backlog 开/关。
- 这类分叉此前无任何测试能发现：两边各自有单测，但都用自造 fixture，从没对过同一份输入（上一轮扁平键/嵌套键的契约 bug 同源）。

同一 fixture 交叉比对 Python/Swift 指标并修分叉

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
