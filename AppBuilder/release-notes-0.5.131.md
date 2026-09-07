# Tapgo AICoding 0.5.131

## 命令面板 section header 文字（Codex 桌面端风格）

- 命令面板在 3 个 Divider 分组前加 section 标题（caption2 + secondary 色 + 大写）：
  - **环境**（MCP）
  - **当前对话**（代码审查 / 侧边 / 创建聊天分支 / 压缩 / 反馈 / 归档 / 状态 / 目标 / Plan 模式 / 新聊天）
  - **全局**（置顶聊天 / 切换侧边栏 / 运行设置）
- `PaletteAction` 加 `sectionName: String?` 字段；`sectionDivider(_:preceding:)` 接受 section 名。
- `Entry` 加 `sectionName` 字段；`ForEach` 渲染 `if let section = e.sectionName, section != lastSectionName` 时插 caption header。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
