# Tapgo AICoding 0.5.177

## Sidebar thread item 双击进入 rename 模式

之前 sidebar thread item 双击只 select thread（无效操作）。v0.5.177 加 `.onTapGesture(count: 2)` 触发 rename 模式（macOS Finder 习惯），打开重命名 alert（v0.5.170 加了 TextField 默认 focus）。

- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - 3 个 thread item Button（flattenedThreads / flatTaskThreads / visible）加 `.onTapGesture(count: 2)` 触发 `renamingThreadId = thread.id + renameDraft = thread.title`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
