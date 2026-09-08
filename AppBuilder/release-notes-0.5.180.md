# Tapgo AICoding 0.5.180

## NewTaskView preselectedHint 视觉强化：brand 浅蓝背景 + accent 边框

v0.5.171 加的 preselectedHint 背景用 `DSHTheme.interactiveHover`（淡灰），视觉太弱——重要的预选信息不够明显。改用 `Color.accentColor.opacity(0.08)` 背景 + `Color.accentColor.opacity(0.4)` 边框，跟 v0.5.162 actionCard 风格一致。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - `preselectedHint` 背景 `DSHTheme.interactiveHover` → `Color.accentColor.opacity(0.08)`。
  - 加 `.overlay(RoundedRectangle...)` accent 边框。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
