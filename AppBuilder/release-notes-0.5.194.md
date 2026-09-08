# Tapgo AICoding 0.5.194

## 流式输出对齐 Codex 桌面端：ToolCall / CommandExecution running 用 3 跳动 dots

v0.5.192/v0.5.193 改 working indicator + assistant streaming 的"生成中"指示。v0.5.194 继续把 ToolCallRow / CommandExecutionView 的 running 状态从 ProgressView 改为 3 跳动 dots（对齐 codex 桌面端 + 与 v0.5.192 一致）。

- `Sources/TapgoAICoding/Views/MessageRow.swift`:
  - `ToolCallRow` 加 `@State pulse`，running 时显示 3 个错开 0.2s 的 `Circle()` 0.6s 循环 + `easeInOut.repeatForever(autoreverses: true).delay(i*0.2)` 动画，替换原 `ProgressView().controlSize(.mini)`。
  - `CommandExecutionView` 加 `@State pulse`，`runningIcon` 用同样 3 跳动 dots 动画。
- `AppBuilder/Info.plist`, `AppBuilder/ComputerUseHelper-Info.plist`, `AppBuilder/project.yml`: bump 到 0.5.194。

测试：未跑（build 卡住几次，纯 UI 改动不影响逻辑）。开发者签名有效；尚未完成 Apple 公证。
