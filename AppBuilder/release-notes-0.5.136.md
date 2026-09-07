# Tapgo AICoding 0.5.136

## Plan mode 视觉强化 — composer 顶部蓝色 banner

- `ComposerView` 顶部加 `PlanModeBanner`（蓝色 brandPrimary 背景 + 灯泡图标 + "Plan mode 已开启" + "下一条消息会让 Codex 先出方案不执行工具" 副文本），与 Codex 桌面端 composer 顶部提示风格一致。
- 当 `planningMode` 为 true（点 Plan 按钮 / palette Plan 模式 / /plan slash / tapgoTogglePlanMode 通知）时显示；点击 Send 后 `send()` 把 `planningMode = false` 重置，banner 立即消失。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
