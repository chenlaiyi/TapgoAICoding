# 共享手机中继

[English](README.md) | 中文

公网中继只需要 `relay.itapgo.com` 的 A 记录和 `*.remote.itapgo.com` 的泛域名 A 记录。Nginx 为两个名称终止 HTTPS，将控制域名的 `/~!frp` 转发到 FRP 本机控制端口，将设备域名请求转发到 FRP 本机 HTTP 端口。桌面端经 443 端口主动建立 WSS 连接，再将请求转发到本机 19388 端口的 Host。手机请求由 Host 浏览器令牌授权，设备域名本身不授予权限。

中继服务器部署 [FRP 服务配置](shared-relay.frps.toml)、[systemd 单元](tapgo-relay.service)、[Nginx 配置](public-mobile.nginx.conf)和[证书续期钩子](tapgo-relay-cert-renew.sh)。Certbot 使用 [DNS 钩子](certbot-alidns-hook.py)验证 `relay.itapgo.com` 与 `*.remote.itapgo.com`；阿里云凭据仅允许 root 读取。证书更新后，部署钩子将证书复制到 FRP 服务可读目录并重载 Nginx。FRP 的控制和 HTTP 监听端口始终位于本机回环地址。

管理员在每台受管 Mac 上放置权限为 600 的中继令牌文件，并在 `~/.tapgo-aicoding/.env` 配置 `TAPGO_RELAY_DOMAIN=remote.itapgo.com`、`TAPGO_RELAY_SERVER=relay.itapgo.com` 和 `TAPGO_RELAY_TOKEN_FILE=<绝对路径>`。启动时，桌面端在 `~/.tapgo-aicoding/tapgo-mobile-relay` 下生成稳定的随机设备 ID，启动内置的 frpc 0.71.0，并在“连接手机”中显示带认证的 HTTPS 链接。iOS 通过该链接配对，以设备主机名区分 Mac。手机中原有的独立域名连接在手动移除前仍可使用。

共享 FRP 令牌的持有者可以注册任意未占用的子域名。只向同一管理员控制的 Mac 配置该令牌，不要分发给不可信的客户设备。令牌泄露时，必须在服务器和所有已接入 Mac 上轮换。手机配对链接也可访问 Host 会话并执行命令，应作为凭据保管；Host 认证到期后需重新配对。
