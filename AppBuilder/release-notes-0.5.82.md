# Tapgo AICoding 0.5.82

- 「自进化日志」追回真实版本：
  - App 内 `EvolutionLogView.makeHistory()` 此前停在 v0.5.4，落后于实际发布版本；已补 v0.5.70–v0.5.81 共 12 条，账户菜单点开「自进化日志」即可看到最近 12 个版本的发布记录。
  - 新增 `Evolution log sync` 测试段守护该问题：要求最近 4 个发布版本必须都在 makeHistory、与 EVOLUTION.md 至少有 5 个共同版本、v≥0.5.5 双向同步（防止 EVOLUTION 漏更与拼写错）。
- 测试：2700 通过 / 13 失败（13 个为预存在远程 SSH 集成）；目标 IDE 设计相关断言 53 项 + Evolution log sync 5 项全过。
- 已知限制：首次启动需要登录 codex 账号才能看到完整界面。
