# Tapgo AICoding 0.5.156

## 修复：点 backdrop 关闭 command palette 也自动 focus 回 composer

v0.5.155 让 `onDismiss`（↩ 选命令 / X 按钮）关闭 palette 时 focus 回 composer，但点 backdrop（半透明黑色区域）关闭时没 focus。统一所有关闭路径都 focus composer。

- `Sources/TapgoAICoding/Views/ContentView.swift`:
  - backdrop 的 `.onTapGesture` 关闭 palette 时也 post `.tapgoFocusComposer` 通知。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
