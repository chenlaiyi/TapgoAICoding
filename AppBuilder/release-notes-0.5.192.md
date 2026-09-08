# Tapgo AICoding 0.5.192

## 流式输出对齐 Codex 桌面端：running 用 3 跳动 dots 动画

用户反馈：v0.5.192 之前流式输出过程和 Codex 桌面端差距大。Codex 桌面端 running 状态用 3 跳动 dots 动画（每个 dot 错开 0.2s 起始），Tapgo 之前用 ProgressView spinner + 文字"正在生成回复"。

- `Sources/TapgoAICoding/Views/ConversationResponseView.swift`:
  - `ConversationWorkingIndicator` 用 3 个 `Circle()` 错开 0.2s 的 `.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(i) * 0.2)` 动画替换 `ProgressView()`，对齐 Codex 桌面端 running 视觉。

测试：基线一致（之前 v0.5.191 build 卡住，test 未跑，但改的是纯 UI 动画，不影响逻辑）。开发者签名有效；尚未完成 Apple 公证。
