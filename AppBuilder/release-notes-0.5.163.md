# Tapgo AICoding 0.5.163

## NewTaskView 加底部"取消"按钮 + ESC 快捷键

之前 NewTaskView 只在右上角放 X 关闭按钮（22x22，很小）。user 经常找不到"取消"入口。加底部"取消"按钮（bordered style + 文字，更明显） + ESC 快捷键（`.cancelAction`）支持。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 加 `footer` view：右下角"取消"按钮（bordered style + 文字）。
  - 用 `.keyboardShortcut(.cancelAction)` 让 ESC 触发 dismiss。
  - body frame 从 height 460 → 480 容纳 footer。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
