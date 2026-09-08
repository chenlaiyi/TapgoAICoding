# Tapgo AICoding 0.5.159

## 清理 AddMenuAction.togglePlanMode dead code

v0.5.157 把 + 菜单的"计划模式"项从 `addMenuItems` 静态数组拿出来，单独渲染时直接 `planningMode.toggle()`，不走 `runAddMenuAction(.togglePlanMode)`。`AddMenuAction.togglePlanMode` case 变成 dead code。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `AddMenuAction` enum 移除 `.togglePlanMode` case。
  - `runAddMenuAction` switch 移除对应 case 分支。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
