# v0.5.261

feat(evolution): backlog 驱动选点

## 变更

- Python/Swift 双解析 backlog 并注入 prompt/面板/nextActions
- evolve.sh 默认 next 从 backlog 顶部解析

BACKLOG.md 成为脚本、UI、prompt、state 四处的选点真源

## Next

EVO-006 分支/worktree 隔离: 每轮在 `codex/evolution-vX.Y.Z` 工作树执行；publish 走 PR 或至少远端 fast-forward 校验
