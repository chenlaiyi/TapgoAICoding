# Tapgo iOS

[English](README.md) | 中文

iOS 应用通过 WebKit 显示运行中的 DSH Web 界面。可扫码、粘贴或使用 `dsh-mobile://?url=…` 深度链接导入带 `token` 参数的 HTTPS 地址。地址保存在本设备 Keychain，Web 会话 Cookie 保存在 WebKit；“断开”会移除已保存地址。Web 界面仅能导航到配对的来源。

在本目录运行 `xcodegen generate`，构建 `DshMobile` scheme。应用沿用 `com.devtools.terminalSimple` Bundle ID；签名和分发需要相应 Apple 开发者团队权限。

Mac 端用 Tailscale Serve HTTPS 将 8443 等端口转发至桌面 Host 的本机端口 19388，并在启动桌面应用前通过 `~/.tapgo-aicoding/.env` 或启动环境设置 `TAPGO_MOBILE_HTTPS_ORIGIN` 为对应的完整 HTTPS 来源。桌面应用菜单随后显示“连接手机”，可复制带认证令牌的链接。手机和 Mac 必须加入同一 tailnet。只使用 tailnet 内的 Serve，不启用 Funnel。桌面 Host 仍只监听本机，并仅信任配置的 HTTPS 主机。

进程重启会轮换链接令牌。此前 WebKit 获得的 Cookie 可能在配置的有效期内继续使用；需要重新认证时，请从 Mac 再复制链接。该链接允许访问 Harness 界面并执行命令，请勿外传。
