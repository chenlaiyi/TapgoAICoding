# Tapgo AICoding 0.5.175

## 修复：ApprovalRow 拒绝按钮改用 .borderedProminent 让 destructive style 真显示

v0.5.165 加 `Button(role: .destructive)` 让 macOS 标记 destructive action，但 `.buttonStyle(.bordered)` 不支持 role tinting —— role 实际被忽略，按钮没显示红色。改用 `.borderedProminent` 让 role 真生效显示红色 destructive 样式。

- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 拒绝按钮 `.buttonStyle(.bordered)` → `.buttonStyle(.borderedProminent)`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
