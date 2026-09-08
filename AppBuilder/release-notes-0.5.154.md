# Tapgo AICoding 0.5.154

## SidebarTaskLabel failed 改用实心图标（与 awaiting approval 风格统一）

v0.5.152-153 把 awaiting approval 改实心 + warn 色。failed 还是 outline（`exclamationmark.circle`），跟 awaiting approval 风格不一致。改用实心 `exclamationmark.circle.fill`。

- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 的 `.failed` case icon 从 `exclamationmark.circle` → `exclamationmark.circle.fill`（实心）。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
