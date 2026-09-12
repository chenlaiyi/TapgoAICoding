# v0.5.270

feat(evolution): 早期日志归档

## 变更

- v0.5.5 之前 11 节移入独立归档
- 补主日志/归档双向不变量并修复 MakeHistoryParity

主日志只保留 v0.5.5 之后,早期历史完整移入 evolution/archive/

## Next

EVO-015 worktree 隔离: 分支隔离后的强化项，每轮在独立 git worktree 执行，主 checkout 零改动
