# Tapgo AICoding 0.5.185

## ApprovalRow 拒绝按钮加 ⌘⌫ 快捷键

之前 ApprovalRow 拒绝按钮只能鼠标点（v0.5.176 加了 Return 批准，⌘⌫ 拒绝缺）。加 `.keyboardShortcut(.delete, modifiers: .command)` 让 ⌘⌫ 触发拒绝——macOS destructive action 标准快捷键。

- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 拒绝按钮加 `.keyboardShortcut(.delete, modifiers: .command)`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
