# Tapgo AICoding 0.5.132

## 命令面板加 settings / 更新日志 / 快捷键入口

- 命令面板 actions 数组末尾（settings 之前）加 2 个新 entry：
  - **更新日志**（`doc.text` 图标）— 弹 `ReleaseNotesSheet` sheet（640x560），从项目根 `EVOLUTION.md` 读取头部 12 个 `## v...` 段标题 + 当前 App 版本号
  - **快捷键**（`questionmark.circle` 图标）— 弹 `ShortcutsView` sheet
- `CommandPaletteView` 加 `showReleaseNotesSheet` / `showShortNotes` 两个 @State；新增 `ReleaseNotesSheet` 私有 struct（独立 sheet 不依赖 ContentView 主 state）。
- 原 ContentView 顶层 `showShortcuts` sheet 移除（已移入 CommandPaletteView 内）。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
