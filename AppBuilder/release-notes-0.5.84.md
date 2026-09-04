# Tapgo AICoding 0.5.84

- Web Remote 静态资源拆出 + Harness daemon 多客户端：
  - Web Remote H5 拆资源（linkVersion 2→3、webClientVersion=1）：`PhoneRemote.pageHTML()` 现在从 `Sources/TapgoCore/Resources/PhoneRemote/index.html` 模板加载 32 行骨架，业务 JS/CSS/UI 元素搬到独立 `App.js`（710 行）/ `app.css`（403 行）+ `app-icon.png`。新增 `/r/<token>/assets/<name>` 路由（GET/HEAD，资源名白名单 `app.css`/`app.js`/`app-icon.png`，cache-control immutable 一年）。H5 引导脚本带 `?v=<webClientVersion>` 防缓存，老客户端不会误用旧 css/js。
  - PhoneRemoteTests 同步重构：`runPhoneRemotePage` 改为验证 webAsset/wAssetResponse/Route.asset + app.js 核心 API + 关键 UI class，`runPhoneRemoteControlSnapshot` marker 循环改在 index.html + app.js + app.css 联合里查。新增 7 类断言（webAsset 加载 / 拒绝路径穿越 / HTTP 头 / Route 解析 / asset 路由 token 校验 / 资源大小）。
  - Harness daemon 多客户端：`Sources/TapgoHarness/main.swift` 重写为 daemon 永生 + accept 循环 + 每次客户端连接独立 spawn codex app-server（之前是单客户端：spawn codex → 等连接 → EOF 退出 → daemon 也退出）。每次客户端断开回到 accept() 等下一个，launchd plist 已 KeepAlive 不需要 daemon 自我重建。
  - SocketHarnessTransport 用 `DispatchSource.makeReadSource` 替代 `FileHandle.readabilityHandler`（v0.5.74 起的 macOS 27 EOF 误判 bug：readabilityHandler 偶尔把可读回调成 `Data.isEmpty`、触发到 EOF 路径、关 fd 让 supervisor 重启 + 30 秒 watchdog 命中）。DispatchSource 只在「真的可读」或「真的 EOF/hangup」时触发，EOF 由 `recv` 返回 0 显式判断。
  - ComputerUseHelper-Info.plist 顺手对齐到 0.5.84（v0.5.74 之后没再跟 tag，导致 AppUpdateDistributionTests 报 `expected 0.5.83, got 0.5.74`）。
- 测试：2713 通过 / 13 失败（13 个全部为预存在远程 SSH 集成 / auth.json 缺失，v0.5.84 未引入新回归）。
- 已知限制：拆分出来的 app.js / app.css 是 v0.5.84 重写的精简版本（核心 API 路径 + 6 个关键 UI class 完整保留），后续 patch 可继续完善边角 UI。
