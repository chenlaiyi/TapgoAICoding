# Tapgo AICoding 0.5.108

- 消息输出层次感第二轮升级（对齐 Codex Desktop 截图基线）：
  - 新增 `MarkdownInlineFlow` + `InlineFlowLayout` 渲染器：行内代码段真正按 `RoundedRectangle(cornerRadius: 4)` 画在浅灰底色上，并把 monospace 文字与背景 pill 一起随正文自动换行；之前 `AttributedString.backgroundColor` 画的是直角色块、跨行时和正文 baseline 对不齐。段落、列表项、表格单元、引用、任务项、标题全部从 `Text(inlineAttributed(...))` 切到 `MarkdownInlineFlow`，风格保持一致。
  - `ActivityRollupView` 移除裸 `ProgressView()`，改用类别图标（`terminal` / `magnifyingglass` / `pencil` …）加一颗 5pt 脉动 `LivePulseDot` 表示「仍在进行中」。视觉更安静，也保留了动作语义，并新增 `accessibilityReduceMotion` 兼容。
- 新增 5 条 `DesktopDesignParity` 断言锁定上述行为（`MarkdownInlineFlow` 渲染器、4pt 圆角 pill、`LivePulseDot`、去除裸 `ProgressView`）。
- 发版流程沿用 v0.5.107：`./scripts/evolve.sh patch ...` 跑 build → test → commit → tag → push → 签 zip → gh release create → 刷 appcast → push main → 重打 .app；已装客户端 Sparkle 下一轮 poll 拉取 v0.5.108 升级提示。
