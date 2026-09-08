# Tapgo AICoding 0.5.191

## GoalEditorSheet 自动 focus TextEditor

+ 菜单"目标"项点击后打开 GoalEditorSheet，但 TextEditor 没自动 focus，user 必须先点 TextEditor 才能输入目标。v0.5.191 让 sheet 打开时自动 focus。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `GoalEditorSheet` 加 `@FocusState focused`
  - TextEditor 加 `.focused($focused)` + `.onAppear { focused = true }`

测试：3117 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
