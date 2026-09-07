# Tapgo AICoding 0.5.121

## 命令面板升级为底部抽屉（视觉对齐 Codex 桌面端）

- ⌘K 唤起的命令面板从 macOS 居中浮层改为底部 docked 抽屉：从屏幕底部上滑、宽度自适应（最大 720pt）、高度 460pt、顶部 14pt 圆角（底部不圆角）、`.regularMaterial` 背景模糊 + 阴影；spring 进场（从 bottom.move）。
- 点背景关闭；点行执行后自动关闭。
- 每行格式：左侧 SF Symbol 图标 + 标题 + 右侧状态/快捷键（Context % 实时取最近一轮 usage）。

## 命令面板命令集对齐 Codex 桌面端

11 个动作按 Codex 顺序：

| 命令 | 行为 |
|---|---|
| MCP | 显示电脑控制 Helper 安装状态（已安装 / 未配置） |
| 代码审查 | 等价 `/review`（无 scope 参数）— 打开审查 thread 跑 `git diff HEAD` |
| 侧边 | 调 `createAuxiliaryThread` 开一个临时侧边 thread（title "侧边：<原 thread 标题>"） |
| 创建聊天分支 | 弹 sheet 让用户输入分支名，新建 thread 并预填 "git worktree add -b <name>" 提示 |
| 压缩 | 等价 `/compact` — 折叠 assistant items；alert 显示折叠回合数与 assistant item 数 |
| 反馈 | 调 `snapshotActiveThreadForFeedback` 把活跃 thread 快照写到 `~/.tapgo/feedback/<ISO 时间>-<title>.md`；alert 显示落盘路径 |
| 归档 | 调 `deleteThread` 立即从活跃列表移除（保留文件） |
| 新聊天 (⌘N) | 新建 thread |
| 状态 | alert 显示 Thread ID + Context % + Model + CWD + Turns |
| 目标 | 弹目标编辑 sheet（复用 ChatView 的 `editingGoalItem`，新加 `tapgoOpenGoalEditor` 通知跨 view 通信） |
| 置顶聊天 | 调 `togglePinned` 切换当前 thread 固定 |
| 切换侧边栏 (⌘\\) | post `tapgoToggleSidebar` 通知 |
| 运行设置 (⌘,) | 打开设置 |

## Composer slash 命令已含

`/clear` `/model` `/init` `/compact` `/review` 维持 composer 内联可用（v0.5.118-120 已发布）；命令面板与 slash 命令互补——命令面板是 GUI 友好入口（`MCP/侧边/状态/置顶` 等在 shell 里没有等价物）。

测试：本机 fafamacmini 3110 passed / 12 failed（DesktopDesignParityTests 加回 `tapgoToggleSidebar` 后通过；12 项失败均为 SSH 远程集成 + auth.json 环境性，与改动无关）。开发者签名有效；尚未完成 Apple 公证。
