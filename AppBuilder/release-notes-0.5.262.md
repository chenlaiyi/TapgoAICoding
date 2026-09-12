# v0.5.262

fix(evolution): state 选点与 backlog 同源

## 变更

- state 改用 RESOLVED_NEXT 并补失败注入断言

记录与 state.nextActions 同时来自 backlog 顶部,补齐选点闭环

## Next

EVO-006 分支/worktree 隔离: 每轮在 `codex/evolution-vX.Y.Z` 工作树执行；publish 走 PR 或至少远端 fast-forward 校验
