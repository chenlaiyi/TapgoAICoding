# Tapgo AICoding 0.5.158

## + 菜单"目标"项显示当前 goal 状态（与计划模式一致）

v0.5.157 让"计划模式"项显示当前 planMode 状态。"目标"项之前也是静态 — 用户从 + 菜单看不出当前 thread 是否有 goal。Codex 桌面端 goal 状态在 menu item 上有视觉指示。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - "目标"项从 `addMenuItems` 静态数组拿出来单独渲染。
  - 无 goal 时：`target` icon + "目标" + "设置要持续追求的目标" 副文。
  - 有 goal 时：`target.fill` icon + "目标（已设置）" + "当前目标：..." 副文（前 40 字符 + 省略号）。
  - 点击行为不变：`.setGoal` → 编辑 goal sheet。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
