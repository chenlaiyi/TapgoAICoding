# Plugins — Tapgo 官方插件模板

`plugins.itapgo.com/catalog.json` 的内容来源；每个子目录对应一个可被
`PluginManagerService.installTapgoPlugin` 通过 `git clone` 安装的最小仓库模板。

## 协议（`PluginCatalogParser.decodeTapgo`）

```json
{
  "available": [
    {
      "pluginId": "tapgo-plugin-sparkle-publish",
      "name": "tapgo-plugin-sparkle-publish",
      "displayName": "Sparkle 一键发版",
      "version": "1.0.0",
      "description": "...",
      "repo": "https://github.com/chenlaiyi/tapgo-plugin-sparkle-publish.git",
      "channel": "main",
      "capabilities": ["脚本", "发版"]
    }
  ]
}
```

字段要求：`pluginId` 必须通过 `PluginConfigEditor.isSafePluginId`（字符集 `[A-Za-z0-9._@-]` + 长度 ≤180 且非空）；
`repo` 必须是 `https` / `git` / `ssh` 三种 scheme 之一；`channel` 可选，省略时取 `main`。

## 发布步骤

1. 在 `github.com/chenlaiyi/` 下建两个空仓库 `tapgo-plugin-sparkle-publish` 与 `tapgo-plugin-screen-permission`。
2. 把对应子目录内容作为首次提交推上去（`git init && git add . && git commit && git remote add origin … && git push -u origin main`）。
3. 把 `Plugins/catalog.example.json` 部署到 TapgoServer 的 `plugins.itapgo.com/catalog.json`（nginx 直接静态文件即可）。
4. 在 TapgoAICoding 打开「插件市场 → Tapgo 官方」Tab，刷新后看到这两条，点击「安装」即可 `git clone` 到 `~/.tapgo/plugins/<id>/`。

## 当前 demo

- `tapgo-plugin-sparkle-publish/`：转发到仓库内置 `scripts/create-github-release-artifacts.sh` 的薄封装。
- `tapgo-plugin-screen-permission/`：本地查 `~/Library/Application Support/com.apple.Tcc/Tcc-originals.db`，给出 Tapgo AICoding 当前屏幕录制 / 辅助功能授权状态。
