# Tapgo AICoding 0.5.166

## NewTaskView action card 文案精简（"本地文件夹 / 远程项目 / 快速任务"）

之前 NewTaskView 3 个 action card 标题："本地文件夹 / 远程项目 / 快速任务 (无项目)" — 标题过长，挤在 card 里。精简为"本地项目 / 远程项目 / 快速任务"，ChatView 上下文已经清楚是项目。Hint 文案"快速任务 (无项目)"保持不变（hint 在 card 下面，有空间展示完整）。

- `Sources/TapgoAICoding/Resources/L10n.swift`:
  - `localFolder`: "本地文件夹" → "本地项目"
  - `quickNoProject`: "快速任务 (无项目)" → "快速任务"

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
