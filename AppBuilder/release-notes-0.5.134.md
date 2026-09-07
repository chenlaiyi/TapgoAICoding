# Tapgo AICoding 0.5.134

## 更新日志 sheet 加 GitHub release 链接

- `ReleaseNotesSheet` 每条版本日志变成可点击的 `Link(destination:)`（secondary 蓝色 + brand 色文字），点击跳到 `https://github.com/chenlaiyi/TapgoAICoding/releases/tag/vX.Y.Z`。
- `recentEntries()` 返回类型从 `[String]` 改为 `[(version: String, title: String)]`，解析 `## vX.Y.Z — 标题` 拆出版本号和标题。
- `releaseURL(for:)` 辅助函数返回 GitHub release tag URL。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
