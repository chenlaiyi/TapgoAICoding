# Tapgo AICoding 0.5.102

- 新增「定时任务」面板（侧边栏一级导航 `定时任务` ⏰ 图标）：
  - 3 种触发时机：`每天 HH:MM` / `每 N 分钟` / `一次性指定时间`，`ScheduleSpec` 为可扩展 Codable 枚举（`oneShot` / `daily` / `interval` / `weekly` 四种 case），未来加 cron / 工作日窗口不破坏已有 JSON
  - 每个任务 1 个 JSON 文件持久化到 `~/Library/Application Support/Tapgo AICoding/state/v1/scheduled-tasks/<id>.json`，文件权限 0600，原子写
  - 后台 `ScheduledTaskRunner` 60s tick 扫描，触发时：
    - 若 `targetThreadId` 为空 → `store.newThread() + store.sendUserMessage(prompt)`
    - 若 `targetThreadId` 存在 → `store.sendUserMessage(prompt, toThreadID:)`（注入到指定会话，可用于每天汇报到同一会话的场景）
    - 同时通过 `UNUserNotificationCenter` 弹 macOS 通知（首次会请求 .alert + .sound 权限）
  - 一次性任务触发后自动 `enabled = false`，避免重复触发
- UI（`ScheduledTasksView`）：列表卡片显示任务名 / 触发时机标签 / "下次 X 秒后触发" 相对时间 / 启用开关 / 编辑 / 删除；空态有友好引导
- `ScheduledTaskBridge` 桥接 TapgoCore runner 与 TapgoAICoding SessionStore，App 启动时一次性 wire 并 start runner
- 数据/调度逻辑全在 `TapgoCore` 包内，可独立单测；UI 与通知留在 `TapgoAICoding`
- 新增 23 条测试断言（`ScheduleSpec` 12 + `ScheduledTaskStore` 11）：daily/weekly 滚动逻辑、interval 与 lastFired 关系、Codable round-trip、文件权限 0600、updatedAt bump
- 回归：2818 总测试 / 2816 通过；2 个 `AppUpdateDistributionTests` 失败为预存在的 Info.plist 与本地 git tag 漂移（`AppBuilder/Info.plist=0.5.103` vs `git describe=v0.5.101`），与本次改动无关，将在下次 `evolve.sh` bump 时一起归位
