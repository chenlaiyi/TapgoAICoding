# Tapgo AICoding 0.5.142

## Composer "+" 菜单插件组接入 Codex 插件目录（实时）

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - 新增 `@State private var codexPlugins: [PluginCatalogItem] = []` 与 `loadCodexPlugins()` 异步加载 `PluginManagerService.loadCatalog()`，筛选 `marketplace == .codex && installed && enabled`。
  - `composerAddMenu` 插件组改为优先显示 `codexPlugins`；当 Codex 插件为空或加载失败时回落显示本地静态 `addMenuPlugins`（v0.5.141 的 5 项：终端执行 / 文件读写 / 网络搜索 / MCP 工具 / 技能），保证菜单永不为空。
  - 新增 `AddMenuAction.insertCodexPlugin(name:detail:)`，点击 Codex 插件 → `NotificationCenter.post(name: .tapgoInsertSkill, object: name)`，复用既有插入通道。
  - 加 `codexPluginIcon(for:)` 静态映射：GitHub → `chevron.left.forwardslash.chevron.right`，Cloudflare → `cloud.fill`，Figma → `paintbrush.fill`，Gmail → `envelope.fill`，Slack → `bubble.left.fill`，Notion → `doc.text.fill`，含 `mcp` capability → `cube`，未知 → `puzzlepiece.extension`。
  - `handleComposerAppear` 里启动 `Task { await loadCodexPlugins() }`，composer 出现时后台拉目录（不阻塞 UI）。

测试：3117 passed / 12 failed（基线一致）。开发者签名有效；尚未完成 Apple 公证。
