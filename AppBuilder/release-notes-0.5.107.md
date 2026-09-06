# Tapgo AICoding 0.5.107

- 全面提升消息输出层次感与色彩区分（对齐 Codex Desktop 截图基线）：
  - `MarkdownMessageView` 列表 bullet 颜色从 `messageText` 降到 `labelTertiary`，字重从 `.semibold` 改为 `.regular`，让 bullet 当成"装饰"而不是"内容"。
  - 行内代码字号与正文同大（之前小 1.5pt），字重抬到 `.medium`，仅靠 monospace + 浅底色区分；`陈*军`、`master` 这类关键字段不再"小一号"。
  - 代码块顶栏去掉"字符数"噪音，新增 `codeBlockLanguageBadge()`，按 25 种语言返回彩色 SF Symbol 图标（PHP 蓝、JS 黄、TS 蓝、Vue 绿、Swift 橙、Python 蓝、Go 青、Rust 棕、Shell 绿、Docker 蓝等）。
  - 列表 marker 列宽保留、行间距收紧，列表层级与正文视觉解耦。
- 发版流程沿用 v0.5.106：`./scripts/evolve.sh patch ...` 跑 build → test → commit → tag → push → 签 zip → gh release create → 刷 appcast → push main → 重打 .app；已装客户端 Sparkle 下一轮 poll 拉取 v0.5.107 升级提示。
