# Tapgo AICoding 0.5.186

## Sidebar project group header + 按钮加 ⌘N 快捷键

之前 sidebar 主菜单 "新建任务" 已绑定 ⌘N。sidebar 每个 project group header 的 + 按钮没快捷键——user 在 sidebar 焦点上按 ⌘N 总是打开无 project 新任务（v0.5.171-174 改进后 contextView 才有 preselectedProject）。让 + 按钮也响应 ⌘N，user 按 ⌘N 直接在当前 project 创建任务（macOS 习惯）。

- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - project group header 的 + 按钮加 `.keyboardShortcut("n", modifiers: .command)`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
