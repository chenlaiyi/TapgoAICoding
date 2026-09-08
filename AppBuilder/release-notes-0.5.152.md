# Tapgo AICoding 0.5.152

## SidebarTaskLabel awaiting approval 状态加 warn 色（与 failed 同等显眼）

之前 sidebar thread item 的 awaiting approval 用 `hand.raised` icon + `labelTertiary` 淡色，跟 running 没区分，user 容易忽略需要批准的会话。改成 warn 色，跟 failed 同等显眼。

- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 的 `.awaitingApproval` case icon 加 `.foregroundStyle(DSHTheme.warn)`，让 awaiting approval 在 sidebar 列表里跟 failed 一样显眼。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
