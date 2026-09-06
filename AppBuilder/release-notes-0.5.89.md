# Tapgo AICoding 0.5.89

- 「参照目标 IDE 风格」trajectory 配色全员到位：
  - `MessageRow.swift` 助手正文（`MessageBubble` 的 assistant 分支）在 MarkdownMessageView 前加 2pt × 22pt `DSHTheme.trajectoryAssistant.opacity(0.55)` 左缘胶囊，与 v0.5.88 用户气泡左缘 `trajectoryUser` 胶囊形成"用户蓝 / 助手青"的对称视觉锚点 — 5 色 trajectory 板（reasoning 紫 / toolCall 琥珀 / toolResult 天蓝 / user 蓝 / assistant 青）现已全部挂到 UI。
- ⌘\ 侧边栏切换（zcode 风格的全局快捷方式）：
  - `App.swift` `CommandGroup(after: .windowList)` 新增 `切换侧边栏` 按钮，`keyboardShortcut("\\", modifiers: [.command])`
  - `App.swift` 加 `tapgoToggleSidebar` Notification.Name；`ContentView` 接收并以 0.18s easeInOut 动画切换 `sidebarVisible`
  - 命令面板新增两条入口：`切换侧边栏 ⌘\` 和 `进入自进化会话 ⌘⌥E`，让不记快捷键的用户也能搜到
- 测试：2711 通过 / 0 失败（`DesktopDesignParityTests` 由 66 → 69，新锁 trajectoryAssistant 助手 accent + ⌘\ 双入口）
- 发版流程沿用 v0.5.87/0.5.88：单条 `./scripts/evolve.sh patch ...` 跑 build → test → commit → tag → push → 签 zip → gh release create → 刷 appcast → push main → 重打 .app；已装客户端 Sparkle 下一轮 poll 拉取 v0.5.89 升级提示。
