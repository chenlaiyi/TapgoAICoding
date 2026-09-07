# Tapgo AICoding 0.5.123

## 命令面板键盘交互

- **Esc 关闭命令面板**：隐藏式 Button + `.keyboardShortcut(.escape)` 触发 onDismiss；与 Codex 桌面端习惯一致。
- **⌘K 切换关闭**：命令面板打开时再按 ⌘K 关闭（与 App 菜单层 `tapgoOpenCommandPalette` 通知对称）。
- 搜索框自动 focus 沿用 v0.5.122 之前的 `NSTextField.makeFirstResponder`（打开即输入无需点击）。

测试：3110 passed / 12 failed（与 v0.5.122 一致，12 项均为 SSH 环境性）。开发者签名有效；尚未完成 Apple 公证。
