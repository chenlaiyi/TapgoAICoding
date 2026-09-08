# Tapgo AICoding 0.5.190

## ConversationActivityRow running 时显示 spinner

`ConversationActivityRow` 在 running 时显示静态 `Image(systemName:)` icon，user 不知道是真正执行中还是已经停了。Codex 桌面端 running 状态显示旋转的 spinner。

- `Sources/TapgoAICoding/Views/ConversationResponseView.swift`:
  - `ConversationActivityRow` body 里 `Image(systemName:)` 在 `running && !display.isFailure` 时替换为 `ProgressView().controlSize(.small).scaleEffect(0.6)`（16x16 旋转 spinner）。

测试：3117 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
