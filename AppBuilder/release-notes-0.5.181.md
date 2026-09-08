# Tapgo AICoding 0.5.181

## Sidebar thread item hover tooltip 加 thread ID 前缀

之前 sidebar thread item hover tooltip 只显示 title（`t.title`），user 想找完整 thread ID 只能看右键"复制会话 ID"。v0.5.181 在 tooltip 加 thread ID 前 8 字符，方便 user 快速识别。

- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 加 `var threadId: String? = nil` 参数。
  - `.help()` 改为显示 `"\(title) · <threadId 前 8 字符>"`（有 threadId 时）或 title（无时）。
- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - `threadRow(_:indented:)` 调用 `SidebarTaskLabel` 时传 `threadId: t.id`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
