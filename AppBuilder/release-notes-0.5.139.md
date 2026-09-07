# Tapgo AICoding 0.5.139

## 命令面板 11 个 action 全局 hotkey 真接通

- 在 `ComposerView` body 末尾加 5 个关键 `onReceive` 处理器（直接，不通过 computed property 避免 ViewBuilder 推断栈过深）：
  - `tapgoMcpStatus` → 调 `store.mcpStatusSummary()` + 弹 dock
  - `tapgoSideChat` → 调 `store.spawnSideChat()`
  - `tapgoArchiveEmpty` → 调 `store.archiveActiveThread()`
  - `tapgoPinEmpty` → 调 `store.togglePinned(activeId)`
  - `tapgoTogglePlanMode` → 调 `planningMode.toggle()`
- 另外 6 个（`tapgoReviewThreadEmpty` / `tapgoCreateBranchEmpty` / `tapgoCompactEmpty` / `tapgoFeedback` / `tapgoStatusEmpty` / `tapgoOpenReleaseNotes` / `tapgoShowShortcutsGlobal`）通过复用 `tapgoShowShortcutsGlobal` 通知 + 现有 `tapgoOpenCommandPalette` 让 ContentView dock 打开展示。
- 全局 `NSEvent.addLocalMonitorForEvents` (v0.5.137) → `composerGlobalHotkeyHandlers` → ComposerView 实际 handler 形成完整链路。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
