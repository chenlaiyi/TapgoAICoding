# Tapgo AICoding 0.5.124

## 命令面板底部 access-level badge

- mini composer 左侧加 access-level badge（`clock.arrow.circlepath` 图标 + "完全访问" / "工作区" 等文字），对应 Codex 桌面端底部的"完全访问"指示器。
- 实时从 `TapgoConfig.sandboxKey` 读 `SandboxMode`：
  - `dangerFullAccess`（完全访问）显示橙色
  - `workspaceWrite` / `readOnly` 显示 secondary
- 鼠标悬停显示完整沙箱模式名 + 提示"设置 → 电脑控制 调整"。

测试：3110 passed / 12 failed（与 v0.5.123 一致）。开发者签名有效；尚未完成 Apple 公证。
