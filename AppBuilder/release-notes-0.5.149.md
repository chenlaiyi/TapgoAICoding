# Tapgo AICoding 0.5.149

## 修复：persistent 模式下 PlanModeBanner X 按钮不真 dismiss

v0.5.141 加 `planModePersistent` 常驻模式时引入的 bug：banner X 按钮的 `onDismiss` 是 `if !planModePersistent { planningMode = false }`。persistent=true 时跳过关闭 `planningMode`，banner render条件仍满足（`if planningMode`），X 按钮变成无操作。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner.onDismiss` 改为始终 `planningMode = false`：X 按钮 = 关闭 plan mode，符合常驻模式"一直开直到主动关"的语义（X 就是那个"主动关"按钮）。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
