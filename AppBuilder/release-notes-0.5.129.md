# Tapgo AICoding 0.5.129

## Composer "+" 按钮对齐 Codex 桌面端下拉菜单

- 重构 composer 输入框左侧 "+" 按钮的下拉菜单为 Codex 桌面端风格：标题 "添加" + 5 个分组（文件和文件夹 / 附加 Tapgo AICoding / 目标 / 计划模式 / 录制技能 / 插件 sub-section）。
- "目标" 按钮 post `tapgoOpenGoalEditor` 通知，触发 ChatView editing sheet；
- "计划模式" 按钮 toggle ComposerView 的 `@AppStorage("tapgo.planningMode")`；
- "录制技能" 跳设置 → 电脑控制；
- "附加 Tapgo AICoding" post `tapgoAttachTapgo` 通知（v0.5.130+ 接入）。
- 重构 App.swift 加 `tapgoAddFiles / tapgoAttachTapgo / tapgoTogglePlanMode` 3 个 Notification.Name；ComposerView 加对应 onReceive 处理器。

## v0.5.128 (本版本顺带) 包含 MakeHistory 双向严格

- 升级 MakeHistoryParityTests 为双向严格：makeHistory ↔ EVOLUTION.md 每个 v0.5+ 段必须互见（iOS v1.x + v0.0-v0.2 旧段过滤）。
- 补 makeHistory 30 个历史段（v0.3.0/2/3、v0.4.0/1/3、v0.5.0/1/4、v0.5.52、v0.5.58-61、v0.5.80/81、v0.5.84-99、v0.5.104/105/108）+ EVOLUTION.md 头部 12 段（v0.3.0/2/3、v0.4.0/1/3、v0.5.0/1/4、v0.5.80/81/104）。

## `/plan [text]` slash command（v0.5.128 顺带）

- ComposerLocalCommand 加 `.plan(String)` case + 解析；bare `/plan` 切 Plan mode，`/plan <目标>` 切 + 注入目标到 composer。
- ChatView.handleLocalCommand + .send() 自动前置 `[计划模式]` 指令。
- 命令面板 Plan 行提示文案增加"也可在 composer 内输入 /plan <目标> 一键开启"。

测试：3123 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
