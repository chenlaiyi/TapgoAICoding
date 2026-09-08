# Tapgo AICoding 0.5.165

## ApprovalRow 拒绝按钮加 destructive role

之前 ApprovalRow 拒绝按钮用 `.bordered` 普通样式，跟批准按钮区分不明显。按 macOS convention destructive action 用 `.destructive` role，让 VoiceOver 读出"破坏性"提示 + 系统给红色 accent 提示。

- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 拒绝按钮加 `Button(role: .destructive)` 让 macOS 标记为 destructive action。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
