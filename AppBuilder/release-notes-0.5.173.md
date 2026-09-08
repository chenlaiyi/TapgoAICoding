# Tapgo AICoding 0.5.173

## NewTaskView "快速任务"action 尊重 preselectedProject

v0.5.171 加 preselectedProject 后，sidebar 项目组 + 按钮触发 NewTaskView 显示"将在 X 项目中创建"提示，但 user 选"快速任务"action 时仍调 `onCreate(nil)` 创建无 project 的 thread，违反 sidebar 按钮意图。v0.5.173 让"快速任务"在 preselectedOverride ?? preselectedProject 仍有值时用它。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - "快速任务" action card action 改 `onCreate(preselectedOverride ?? preselectedProject)`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
