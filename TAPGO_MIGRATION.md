# Tapgo AICoding Desktop 升级记录

本项目以 DeepSeek Harness `0.1.7-rc.2` 源码取代旧版 SwiftUI 与 Codex app-server 实现。新版应用沿用 `com.tapgo.aicoding`，公开版本从 `0.5.319` 提升至 `0.6.0`；旧版源码保留在 Git 标签 `v0.5.319`。

## 新版行为

- 桌面应用、网页入口、图标、URL scheme 和更新源使用 Tapgo 标识。DeepSeek 账户登录及计费仍由 DeepSeek 提供，也可使用独立 API Key。
- 新版会话使用 DSH 的持久化格式与 `$DSH_HOME`。旧版 Tapgo 的 `~/Library/Application Support/Tapgo AICoding/state` 不会被安装程序修改，但旧对话不会自动出现在新版会话列表。
- 旧版手机配对、手机遥控和公网中继尚未移植。保留旧 App 与数据备份可供查看历史或回退。
- 本次 macOS 发布使用现有 Developer ID 身份签名，尚无 Apple 公证票据。首次从网络下载时，macOS Gatekeeper 可能阻止启动。

## 验证与发布

派生版在隔离的 DSH home 和 Electron 用户数据目录完成真实主界面启动与品牌检查。桌面发布包必须通过打包脚本的运行时自检、签名验证和更新配置校验，再用于安装及更新通道。每台机器安装前保存旧 App；安装后回读版本、签名、进程与真实界面。发布状态以 GitHub Release 和线上更新源回读为准。

上游源码采用 MIT 许可证；分发派生版时保留 `LICENSE` 和第三方声明。
