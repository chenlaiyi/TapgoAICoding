# Tapgo AICoding 0.5.151

## 修复：PlanModeBanner X 按钮 accessibilityLabel 与实际行为一致

v0.5.149 让 X 按钮始终 `planningMode = false`（关 plan mode 本身），但 accessibilityLabel 仍是 "关闭 Plan mode 提示"（关 banner 提示），不准。同步加 help tooltip。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner` X 按钮 `.accessibilityLabel` 从 `"关闭 Plan mode 提示"` 改为 `"关闭 Plan mode"`，与 v0.5.149 行为一致。
  - 新增 `.help("关闭 Plan mode")` tooltip。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
