# Tapgo AICoding 0.5.105

- 定时任务面板升级：**每次执行都留痕**，触发 / 注入结果可见可回看
  - 新增 `ExecutionRecord`（firedAt + outcome: success / failure / skipped + durationMs + errorMessage），每个任务最多保留最近 5 条
  - 旧 v0.5.102 任务的 JSON 文件零迁移：`executionHistory` 为 Optional，缺失字段自动兜底为空
  - `ScheduledTaskBridge.inject` 改为 `async throws`，目标会话丢失时抛 `ScheduledTaskError.threadMissing`；注入成功 / 失败都会写入历史
- 列表行加 ▶ 立即运行按钮：跳过 `lastFiredAt` / `nextFireAt`，不发通知，立刻把当前 prompt 注入并把 outcome 记入历史（用于"写完先试一次"）
- 编辑器新增 `每周某天` 选项：周一到周日 + HH:MM，映射到底层 `ScheduleSpec.weekly`
- 列表行新增「上次执行」行：成功绿色 ✓ + 耗时、失败红色 ⚠ + 错误摘要、跳过橙色 ↪ + 原因；并显示 `近 N 次` 计数
- macOS 通知逻辑保留，但失败时错误会同时出现在历史里（双通道：用户不必打开控制台就能看到失败原因）

