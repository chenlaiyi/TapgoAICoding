# Tapgo AICoding 0.5.182

## Sidebar 重命名从 alert 改 sheet（TextField focus 可靠工作）

v0.5.170 加 rename alert TextField focus，但 SwiftUI 14+ alert 是 native NSAlert，TextField `.focused()` 行为有限制——focus 可能不工作。改用 sheet 让 SwiftUI 完整渲染 TextField，focus 可靠。

- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - 重命名从 `.alert(...)` 改 `.sheet(isPresented:)` + 新的 `renameSheet` view。
  - `renameSheet`：360pt 宽 VStack，含标题"重命名会话"、roundedBorder TextField（`.focused($renameFocused)` + `.onSubmit(commitRename)`）、取消/确定按钮（确定用 `.buttonStyle(.borderedProminent)` + `.keyboardShortcut(.defaultAction)`）。
  - 加 `commitRename()` helper（onSubmit + 确定按钮共享逻辑）。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
