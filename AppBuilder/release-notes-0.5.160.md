# Tapgo AICoding 0.5.160

## NewTaskView actionCard 加 hover 反馈

之前 NewTaskView 的"本地/远程/快速"3 个 actionCard 是 plain button，无 hover 视觉反馈，用户不知道是可点的。Codex 桌面端的类似选择 card 在 hover 时有边框/背景变化。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - `actionCard` 加 `@State var hovering` + `.onHover { hovering = $0 }`。
  - hover 时背景从 `DSHTheme.surfaceRaised` 改为 `DSHTheme.interactiveHover`，并加 1.5pt 边框（用 icon color 40% opacity）提示可点。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
