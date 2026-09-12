# v0.5.263

feat(evolution): 分支隔离与 fast-forward

## 变更

- 每轮在 codex/evolution-vX.Y.Z 提交,原分支只 fast-forward
- publish 推送审计分支并校验 main fast-forward

提交隔离到迭代分支,原分支只 fast-forward,发布保留审计分支

## Next

EVO-007 发布后健康检查: 启动 smoke、版本/进程/PID 回读、失败自动回滚
