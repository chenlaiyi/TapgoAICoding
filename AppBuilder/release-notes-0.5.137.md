# Tapgo AICoding 0.5.137

## 全局 hotkey 注册（让命令面板 11 个 action 快捷键在 dock 关闭时也生效）

- `App.swift` `init()` 末尾加 `installGlobalHotkeyMonitor()`：用 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 监听 macOS 范围内所有 keyDown 事件。
- 11 个 action 快捷键（`⌃⌘M` MCP / `⌃⌘R` 代码审查 / `⌃⌥S` 侧边 / `⌃⌘B` 创建聊天分支 / `⌃⌘K` 压缩 / `⌥⌘F` 反馈 / `⌥⌘⌫` 归档 / `⌃⌘I` 状态 / `⌃⌘P` 计划模式 / `⌥⌘P` 置顶 / `⇧⌘R` 更新日志 / `⇧?` 快捷键）外加 `⌘K`/`⌘⇧P` 触发 dock。
- 监听匹配 keyCode + modifierFlags 后 post `Notification.Name`（新增 11 个），让 ContentView/ChatView 现有 onReceive 处理器触发（多数已就绪）。
- 注：NSEvent 监听 macOS app 范围（不需辅助功能权限），但要先于 view 自己的 keyboardShortcut 处理。Codex 桌面端默认全局快捷键生效。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
