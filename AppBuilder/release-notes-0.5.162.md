# Tapgo AICoding 0.5.162

## NewTaskView recentRow hover 加 border（与 actionCard 风格统一）

v0.5.160-161 给 actionCard 加了 hover 背景 + border 反馈。recentRow 之前只改背景色，缺少 border 提示。统一风格。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - `recentRow` hover 时加 1.5pt accent-color 40% opacity 边框。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
