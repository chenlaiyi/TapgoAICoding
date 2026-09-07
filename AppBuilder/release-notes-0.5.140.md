# Tapgo AICoding 0.5.140

## NSEvent 全局 hotkey 与 dock keyboardShortcut 冲突解决

- `App.swift` 加 `@MainActor enum PaletteState { static var isOpen: Bool = false }`。
- `installGlobalHotkeyMonitor` 的 NSEvent 回调：若 `PaletteState.isOpen` 为 true（dock 打开），return `event`（不消费）让 dock 内的 keyboardShortcut 正常处理 ↩ 选；否则 post Notification + 消费事件。
- `init` 加 NotificationCenter observer 监听 `tapgoPaletteDidOpen` / `tapgoPaletteDidClose` → 更新 `PaletteState.isOpen`。
- `ContentView` `showCommandPalette = true/false` 切换处 post 通知。
- 解决：之前 dock 打开时 NSEvent 消费了键盘事件，dock 内的 keyboardShortcut 收不到，↩ 键失效。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
