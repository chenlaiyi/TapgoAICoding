# v0.5.319

fix(harness): daemon 多客户端并发 + provider 段名 TOML 转义；模型供应商只保留 DeepSeek

## 修复：App「无法使用」的根因

- **TapgoHarness daemon 支持多客户端并发**。此前 daemon 是单客户端串行：一条连接占线时，第二条连接只能在 listen backlog 里排队，它的 `initialize` 永远得不到响应，App 侧 30 秒后报 `Harness RPC 超时：initialize` / 「任务未完成，可重试」。只要有一个长任务在跑，整个 App 看起来就不可用。现在每条连接一个独立线程 + 独立 codex app-server，互不阻塞。
- 实测：daemon 被占用时新连接的 `initialize` 由「必然超时」变为 0.05–0.26 秒返回；App 内并发验证——长任务（`sleep 25`）在跑的同时，另一个会话 3 秒完成一次对话。
- 客户端 socket 与 daemon accept 后的 fd 均设 `FD_CLOEXEC`，daemon 忽略 `SIGPIPE`，listen backlog 8→32；活跃会话数写入 daemon 日志便于排查。
- **provider 段名 TOML 转义**：遗留注册表里的 `builtin:zhipu` / `builtin:minimax` 被当成自定义 Provider 时，未加引号的 `:` 会让 codex 拒绝加载**整份** config.toml（`invalid unquoted key`），harness 连 initialize 都起不来。现在按需加双引号。
- **遗留内置供应商自动清理**：`ensureBuiltinProviders()` 按启用名单清除已下线的 `builtin:*` 条目连同选中态，不再以自定义 Provider 身份残留（模型选择器里不会再挂着 GLM / MiniMax）。

## 修复：Sparkle 自动更新的签名校验一直不通过

- App 里的 `SUPublicEDKey` 与实际发布签名用的私钥不匹配（用现有私钥重签 0.5.315 归档，得到的签名与线上 appcast 逐字节一致，证明签名用的是现有密钥），导致客户端下载更新后**签名校验失败**，自动更新从未生效；fleet 一直靠脚本手动安装所以未被发现。
- 本次把 `SUPublicEDKey` 对齐到实际签名密钥，0.5.319 起 Sparkle 更新链路口径一致。
- 注意：0.5.318 及更早的客户端带的是错误公钥，**需要手动升级一次**到 0.5.319（`scripts/deploy-fleet.sh` 已覆盖三台机），之后再自动更新即正常。

## 模型供应商只保留 DeepSeek

- `TapgoProviderKind` / `TapgoQuotaChannel` 只留 `deepseek`；删除 `GLMQuotaClient`、`MiniMaxQuotaClient` 及其测试，`RateLimits` 去掉 MiniMax 快照构建器。
- 设置页、侧边栏、额度弹窗、L10n、`scripts/init-tapgo.sh` 同步清理。
- 三个 Mac 的代码已合并到同一个 `main`（合并 jkmacmini 侧已推送的精简实现与本机实现），并清除所有过期分支引用。

## 验证

- `swift build` 通过；TapgoTests 3464 通过 / 12 失败（12 个均为既有环境失败：不可达 SSH 主机、缺少 `auth.json`）。
- 新增回归测试 32 断言：daemon 并发 8、TomlKey 14、注册表清理 10。
- 真实界面回归：三台机 App 均 0.5.319，UI 断言通过；本机与 jkmacmini 各跑通真实回合。
- 线上链路：GitHub Release 归档 + 签名 appcast 已发布，下载 URL 与 appcast URL 均已回读校验。

## Next

- 长任务与普通对话并发的人工回归；把 daemon 版本纳入 fleet 部署脚本（daemon 需单独 `install-harness-daemon.sh`）。
