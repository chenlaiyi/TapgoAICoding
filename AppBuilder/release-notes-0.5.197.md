# Tapgo AICoding 0.5.197

## Plan mode toggle 对齐 Codex 桌面端：移除 PlanModeBanner 顶部 X 按钮，banner 整体可点击 toggle

用户反馈"+里也有计划模式，那么plan按钮是否多余了？"指出 + 菜单已经有 toggle Plan mode 入口，PlanModeBanner 顶部独立的 X 按钮冗余。v0.5.197 把 banner 整体做成 chip-style toggle：点 banner 任何位置都关闭 Plan mode，X 按钮图标保留作为视觉提示但不再独立可点击。

## 改动

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner` 改成整体 `Button` 包裹（onToggle 替代原来的 onDismiss）：点 banner 任何位置都 toggle plan mode，X 图标作为视觉装饰保留但不再是独立按钮。
  - banner 副文从 "先出方案不执行工具" 改成 "点击关闭"，更明确指示可点击关闭。
  - persistent 模式下 lightbulb 图标改成 `lightbulb.max.fill`，强化"常驻"语义。
  - accessibilityLabel/help 改成"点击关闭"语义。
  - call site 的 `onDismiss` 改成 `onToggle`，内部逻辑一致。

## 测试

未跑（纯 UI 改动不影响逻辑）。
