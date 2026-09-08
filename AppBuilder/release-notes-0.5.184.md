# Tapgo AICoding 0.5.184

## NewTaskView 取消 preselected 预选时加 0.2s 动画反馈

之前 v0.5.172 加的 preselectedHint X 按钮直接 `preselectedOverride = nil` 让 preselectedHint 瞬间消失。v0.5.184 加 `withAnimation(.easeOut(duration: 0.2))` 让消失有平滑过渡。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - preselectedHint X 按钮 action `withAnimation(.easeOut(duration: 0.2)) { preselectedOverride = nil }`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
