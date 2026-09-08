# Tapgo AICoding 0.5.153

## SidebarTaskLabel awaiting approval 改用实心图标（视觉风格统一）

v0.5.152 把 awaiting approval 改 warn 色，但 icon 还是 outline (`hand.raised`)。跟 running 的 `circle.lefthalf.filled` 风格不一致。改用实心 `hand.raised.fill`，跟其他 fill 系列图标风格统一。

- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 的 `.awaitingApproval` case icon 从 `hand.raised` → `hand.raised.fill`（实心）。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
