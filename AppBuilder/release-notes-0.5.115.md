# Tapgo AICoding 0.5.115

- 接入 Tapgo 官方插件市场（plugins.itapgo.com）：插件管理器新增「Tapgo 官方」分类，展示官方插件清单与能力说明。
- 官方插件可一键安装与卸载：通过 `git clone` 安装到 `~/.tapgo/plugins/<id>/`，已安装项排在列表最前。
- 目录数据来自 plugins.itapgo.com/catalog.json，网络不可用时静默降级，不影响其它市场的使用。
- 消息渲染优化：文件引用（`path/to/file.ext:42`）渲染为可辨识的引用样式；列表按缩进层级正确嵌套；大消息解析加入缓存，滚动更流畅。
- 修复 Finder/Dock 启动时 Codex CLI 版本探测失败的问题（GUI 最小 PATH 下自动补齐 Homebrew 路径）。

验证覆盖 PluginCatalog 解析与 pluginId 安全、Markdown 文件引用/嵌套列表解析、GUI 最小 PATH 版本探测回归与真实 SSH 执行器回归。开发者签名有效；尚未完成 Apple 公证。
