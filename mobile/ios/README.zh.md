# Tapgo iOS

[English](README.md) | 中文

iOS 应用提供原生的已配对 Mac 列表，配对时可命名，并显示每台 Mac 的 HTTPS 地址。当前电脑始终显示在 DSH WebKit 界面上方；“切换”返回列表，删除列表行则移除该连接。每台 Mac 可通过扫码、粘贴或 `dsh-mobile://?url=…` 深度链接导入带单进程 `token` 的 HTTPS 地址。连接列表和令牌保存在本设备 Keychain，Web 会话 Cookie 保存在 WebKit。Web 视图仅能导航到选定来源。对话界面仍使用共享的 DSH Web 客户端，尚非 iOS 原生对话界面。

在本目录运行 `xcodegen generate`，构建 `DshMobile` scheme。应用沿用 `com.devtools.terminalSimple` Bundle ID；签名和分发需要相应 Apple 开发者团队权限。

每台 Mac 的 Host 都需要独立的 tailnet 内 Tailscale Serve HTTPS 来源，可直接转发到该 Host 的本机端口 19388，也可经由可信 Mac 的持久隧道转发。启动桌面应用前，通过 `~/.tapgo-aicoding/.env` 或启动环境将 `TAPGO_MOBILE_HTTPS_ORIGIN` 设为这个完整来源。应用菜单随后提供带二维码和可复制认证链接的“连接手机”窗口。若多台 Host 共用中转机域名，请在 iOS 配对页给每条连接命名。手机与提供 HTTPS 的 Mac 必须加入同一 tailnet；不启用 Funnel。桌面 Host 仍只监听本机，仅信任配置的 HTTPS 主机；启用手机连接时使用页面内目录浏览，让手机选择该 Mac 上的文件夹。

进程重启会轮换链接令牌。此前 WebKit 获得的 Cookie 可能在配置的有效期内继续使用；认证失效时，请从对应 Mac 再复制链接重新配对，已保存的电脑名称会保留。该链接允许访问 Harness 界面并执行命令，请勿外传。
