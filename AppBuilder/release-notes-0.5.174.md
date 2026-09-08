# Tapgo AICoding 0.5.174

## NewTaskView "快速任务"action card 标题在 preselectedProject 时改"在 X 项目中创建"

v0.5.173 修了"快速任务"action 用 preselectedProject 代替 nil，但 card 标题仍是静态"快速任务"。v0.5.174 让 card 标题在 `preselectedOverride ?? preselectedProject != nil` 时改为 `"<project>中创建"`，让 user 看到预选被尊重（v0.5.173 改动对 user 可见）。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - "快速任务" action card title 用 closure 根据 `preselectedOverride ?? preselectedProject` 返回动态文案。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
