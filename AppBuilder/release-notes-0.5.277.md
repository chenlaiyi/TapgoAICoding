# v0.5.277

feat(evolution): 模型评测预算防线

## 变更

- 新增超时/token/费用/总时长上限与中止语义
- 操作者确认包装与结果回写指标看板,并修复 progress 测试时间依赖

单任务超时与预算超限中断,操作者显式确认后结果回写看板

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
