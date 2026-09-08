# Tapgo AICoding 0.5.155

## 改进 command palette 关闭后自动 focus 回 composer

之前 command palette 关闭（点 ↩ 选命令 / 点 backdrop / 按 ESC）后 composer 失去 focus，用户用完 palette 还得手动点 composer 才能继续输入。Codex 桌面端 palette 关闭后会自动 focus 回 composer。

- `Sources/TapgoAICoding/Views/ContentView.swift`:
  - `CommandPaletteView.onDismiss` 在关闭 palette 时多 post 一个 `.tapgoFocusComposer` 通知，触发 `ChatView` 已有 `tapgoFocusComposer` handler（v0.4.x 接入）把 focus 设回 composer。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
