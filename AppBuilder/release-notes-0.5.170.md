# Tapgo AICoding 0.5.170

## Sidebar 重命名会话 alert TextField 默认 focus

之前 sidebar 右键菜单选"重命名"时弹 alert，user 必须先点 TextField 才能输入标题——多一步操作。v0.5.170 让 TextField 默认 focus，alert 弹出 user 就能直接输入。

- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - 加 `@FocusState private var renameFocused: Bool`。
  - TextField 加 `.focused($renameFocused)`。
  - 加 `.onChange(of: renamingThreadId)`：id 从 nil 变非 nil 时 `DispatchQueue.main.asyncAfter(0.05) { renameFocused = true }`，让 alert 显示后 focus 落在 TextField。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
