# Tapgo AICoding 0.5.122

## 命令面板底部 mini composer（视觉对齐 Codex 桌面端）

- 命令面板底部加固定 dock 工具条：`+` 按钮（聚焦主 composer）+ `TextField`（输入即时消息，回车 / 发送按钮提交）+ 当前模型名（实时从 `TapgoConfig.selectedModelKey` 读）+ 发送按钮（accent 圆 circle，`arrow.up`，空内容时禁用）。
- mini composer 内容经 `tapgo.composer.pendingText` UserDefaults shuttle 传回主 composer：发送时 post `tapgoFocusComposer` 通知 + 关 palette；主 composer 看到 pending text 时填充。
- 视觉与 Codex 桌面端一致——`Divider().opacity(0.5)` 切分 + 底部行半透明 surface。
- 关闭回调重构：`CommandPaletteView` 改用 `onDismiss: () -> Void` 闭包而非 `\.dismiss` 环境（overlay 模式无 dismiss 环境）；同时把误删的 `ShortcutsView.dismiss` 加回。

测试：本机 fafamacmini 3110 passed / 12 failed（与 v0.5.121 一致，全部 SSH 环境性）。开发者签名有效；尚未完成 Apple 公证。
