# Tapgo AICoding 0.5.125

## Plan mode（Codex 桌面端核心 UX）

- **Composer 工具栏 Plan toggle**：在 `environmentChip` 之后加 `Plan` 按钮。点击切换状态（`@AppStorage("tapgo.planningMode")` 持久化）。开启时按钮变蓝底白字，关闭时灰字。
- **发送时自动加 `[计划模式]` 指令前缀**：开启状态下，下一条消息会被自动包成 `[计划模式] 请先给方案（Markdown：步骤 / 风险 / 验证），不要执行任何工具调用。\n\n<原消息>` 发送；发送后 toggle 自动归位（单次模式）。
- **命令面板 "Plan 模式" 入口**：palette 在"状态"后加 `Plan 模式` action（`lightbulb` 图标），点击 → 设置 `tapgo.planningMode = true` + alert 提示"已开启。下一条消息会让 Codex 先出方案不执行工具。"

测试：3110 passed / 12 failed（与 v0.5.124 一致）。开发者签名有效；尚未完成 Apple 公证。
