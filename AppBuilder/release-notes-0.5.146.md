# Tapgo AICoding 0.5.146

## 移除底部冗余 Plan toggle 按钮 + 重命名 codexPlugins → pluginCatalogEntries

**用户报告**：
1. + 菜单里已经有"计划模式"项，底部 Plan toggle 按钮是多余的（Codex 桌面端底部没有 Plan 按钮）。
2. 项目是 Tapgo AICoding，但 v0.5.142 我把 plugin 相关 state / 函数 / enum case 命名成了 `codexPlugins` / `loadCodexPlugins()` / `insertCodexPlugin` / `codexPluginIcon(for:)`，跟产品命名冲突。

**改动**：
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - **移除底部 Plan toggle 按钮**：Codex 桌面端底部只有 `+` / `🛡 完全访问` / 模型 / 发送；Plan mode 入口在 + 菜单的"计划模式"项。底部按钮删除后 + 菜单仍是唯一入口。
  - **重命名内部 API**（避免与产品名 Tapgo AICoding 混淆，Codex 是外部对标对象不是项目本身）：
    - `codexPlugins` → `pluginCatalogEntries`
    - `loadCodexPlugins()` → `loadInstalledPlugins()`
    - `codexPluginIcon(for:)` → `pluginIcon(for:)`
    - `AddMenuAction.insertCodexPlugin` → `.insertPlugin`
  - 注释里"对齐 Codex 桌面端"保留（这是产品目标）；"codex"作为 marketplace 枚举 case (`.codex`) 和 Codex app-server 协议层术语保留（外部协议边界）。

**未发布的功能改动**（v0.5.145 已 stash 到 `git stash@{0}`，留给 v0.5.147 单独发）：
- Codex app-server `thread/start` / `thread/resume` 加 `enabledMcpServers` 参数，从 composer `@DisplayName` 匹配插件后传给 harness 激活对应 MCP server。

测试：3116 passed / 13 failed（与 v0.5.144 baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
