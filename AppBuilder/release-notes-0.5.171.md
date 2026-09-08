# Tapgo AICoding 0.5.171

## NewTaskView 接 preselectedProject 参数（sidebar + 按钮预选 active project）

之前从 sidebar 项目组 + 按钮进入 NewTaskView 时，user 还得手动选一次当前 project（即使 active project 就是它）。v0.5.171 让 NewTaskView 接 preselectedProject 参数，ContentView 传 `workspace.state.activeProject`，让 NewTaskView 显示"将在 X 项目中创建"预选提示。

- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 加 `var preselectedProject: Project? = nil`。
  - 加 `preselectedHint` view：folder/globe icon + "将在以下项目创建任务" + project displayName + `DSHTheme.interactiveHover` 背景。
  - body 在 primaryActions 后显示 preselectedHint（如果 preselectedProject != nil）。
- `Sources/TapgoAICoding/Views/ContentView.swift`:
  - `.sheet($showNewTask)` 里 NewTaskView 传 preselectedProject = workspace.state.activeProject。
  - 顺手拆出 `.onChange(of: store.activeThreadId)` 逻辑到 `activeThreadIdChanged` helper，让 body 简化、Swift type-checker 不超时。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
