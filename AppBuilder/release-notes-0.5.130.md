# Tapgo AICoding 0.5.130

## 命令面板按状态分组（视觉对齐 Codex 桌面端）

- 命令面板 14 个 actions 之间插入 3 个水平 `Divider` 视觉分组：
  - **环境**（MCP）
  - **当前对话操作**（代码审查 / 侧边 / 创建聊天分支 / 压缩 / 反馈 / 归档 / 状态 / 目标 / Plan 模式 / 新聊天）
  - **全局设置**（置顶聊天 / 切换侧边栏 / 运行设置）
- `PaletteAction` 加 `isSectionDivider: Bool` 字段 + `static func sectionDivider(_:)` 辅助构造器；`Entry` 加 `isDivider: Bool` 字段；`ForEach` 渲染时 `if e.isDivider { Divider() }` 否则渲染 `Button`。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
