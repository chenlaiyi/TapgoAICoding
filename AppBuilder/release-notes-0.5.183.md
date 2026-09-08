# Tapgo AICoding 0.5.183

## NewTaskView "快速任务"副文在 preselectedProject 时改"在 X 项目中创建临时对话"

之前 v0.5.171-174 让"快速任务"action card 标题在有 preselectedProject 时改"在 X 项目中创建"，但副文仍用静态 `L10n.quickNoProjectHint = "不绑定项目,仅作为临时对话"`，跟新行为矛盾。v0.5.183 让副文在有 preselectedProject 时改"在 X 项目中创建临时对话"。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 副文改成 if/else：有 preselectedOverride ?? preselectedProject 时显示 `"在 \"<p.displayName>\" 中创建临时对话"`，无时显示原 L10n.quickNoProjectHint。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
