# Tapgo AICoding 0.5.157

## + 菜单"计划模式"项显示当前状态（已开启时 ✓ + 文案）

之前 + 菜单的"计划模式"项跟其他项一样（仅文字+图标），无法看出当前 plan mode 是否已开启。Codex 桌面端的 plan mode toggle 菜单项会显示当前状态。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - "计划模式"项从 `addMenuItems` 静态数组拿出来，单独在 `composerAddMenu` 里渲染。
  - plan mode 关闭时：`lightbulb` icon + "计划模式" + "启用计划模式：下一条消息只给方案不执行工具" 副文。
  - plan mode 开启时：`checkmark.circle.fill` icon + "计划模式（已开启）" + "下一条消息会让 Codex 先出方案不执行工具" 副文。
  - 点击仍然 `planningMode.toggle()`（与之前 .togglePlanMode 行为一致）。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
