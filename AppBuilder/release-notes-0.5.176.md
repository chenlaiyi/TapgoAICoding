# Tapgo AICoding 0.5.176

## ApprovalRow 批准按钮加 .keyboardShortcut(.defaultAction)

之前 user 必须鼠标点批准按钮。v0.5.176 加 `.keyboardShortcut(.defaultAction)` 让按 Return 自动批准——macOS alert 默认 button = Return 行为。

- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 批准按钮加 `.keyboardShortcut(.defaultAction)`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
