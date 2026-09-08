# Tapgo AICoding 0.5.172

## NewTaskView preselectedHint 加 X 按钮让 user 取消预选

v0.5.171 加了 preselectedProject 预选提示（"将在 X 项目中创建任务"），但 user 无法取消预选。v0.5.172 加 X 按钮让 user 取消预选回 NewTaskView 默认行为。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - `var preselectedProject` → `let preselectedProject`（caller 设，不可写）。
  - 加 `@State private var preselectedOverride: Project?` 本地可写覆盖。
  - `preselectedHint` 显示 `preselectedOverride ?? preselectedProject`（X 按钮设 override = nil 取消）。
  - 加 `xmark.circle.fill` 按钮 + `.accessibilityLabel("取消预选项目")`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
