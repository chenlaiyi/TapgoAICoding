# v0.5.291

feat(evolution): 运行态 schemaVersion

## 变更

- 新增 scripts/evolution-schema.py：登记 7 个 state artifact 的 schema 版本与必备字段，提供 status/ensure/validate，写入原子且保留文件权限。
- 迁移语义：历史记录缺 schemaVersion 一律补为 v1（低估安全、高估危险）；未来版本（如 v99）不补不改，直接以 13 退出；损坏行只报告不改写。
- 5 个写入方补 schemaVersion：test-failure-report.py、evolution-benchmark.py、evolution-model-eval.py（含 A/B 记录）、rollback-drill.sh（成功+失败）、evolution-maintenance.sh。
- evolve.sh 在环境预检后立即执行 schema gate（--publish --resume 同样），失败 exit 13 且零改动；benchmark 的 state-schema 检查改为调用该工具。
- 新增 32 项 schema 回归 + 9 项失败注入断言 + 2 项 Swift 宽容读断言；真实 state 已补章 51 条记录。

state json/jsonl 全部带版本，写入前补章、未来版本拒跑

## Next

EVO-036 度量扩展: 周期 P95、失败后 MTTR、单轮 token/时长成本
