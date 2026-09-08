# Tapgo AICoding 0.5.179

## NewTaskView 打开时焦点默认在 footer 取消按钮（避免 Enter 误触"本地项目"）

之前 NewTaskView 打开时焦点默认在第一个 action card（"本地项目"），按 Enter 立即触发"打开本地目录" NSOpenPanel。user 想取消却按 Enter 误触发的风险高。改焦点默认在 footer 取消按钮（更安全默认）。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 加 `@FocusState private var cancelFocused: Bool`。
  - footer 取消按钮加 `.focused($cancelFocused)`。
  - body 加 `.onAppear { cancelFocused = true }`，sheet 显示时触发 focus。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
