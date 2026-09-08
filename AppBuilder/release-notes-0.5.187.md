# Tapgo AICoding 0.5.187

## NewTaskView preselectedHint 标题"将在以下项目创建任务"加 .bold

v0.5.171 加的 preselectedHint 标题"将在以下项目创建任务"是 .caption + .secondary 普通字重，在 accent 边框浅蓝背景里不够显眼。改加 .bold 让标题更突出。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - preselectedHint 标题"将在以下项目创建任务"加 `.bold()`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
