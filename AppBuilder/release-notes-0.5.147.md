# Tapgo AICoding 0.5.147

## Codex app-server enabledMcpServers 协议层集成（plugin 真激活）

- `Sources/TapgoAICoding/Services/CodexHarnessClient.swift`:
  - `run(...)` 加 `enabledMcpServers: [String] = []` 参数；`threadRuntimeParams` 接收并在 params 里附加 `enabledMcpServers`（`.array(...)`）。`startThread` 和 thread/resume 两个调用点都透传。
- `Sources/TapgoAICoding/Services/SessionStore.swift`:
  - `QueuedMessage` 加 `var enabledMcpServers: [String] = []`，drain 排队消息保留原 enabledMcpServers。
  - `sendUserMessage(_:planMode:enabledMcpServers:)` / `sendNow(_:images:threadId:planMode:enabledMcpServers:)` 透传到 `newRunner.run(planMode:enabledMcpServers:)`。
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `send()` 加 `enabledMcpServersFromText(_:)` helper：扫 composer 文本里的 `@DisplayName`，跟 `pluginCatalogEntries.displayName`（小写不敏感）匹配，命中的 `installSpecifier` 收集后传给 store。
  - 效果：用户在 composer 输入 `@GitHub 列出我的 PR`，`send` 时 harness 的 thread-level `enabledMcpServers` 会附加 `["github"]`，harness 真激活 GitHub MCP server 并能调对应 tool。

**为什么不是 turn-level**：Codex app-server 协议里 `enabledMcpServers` 是 thread-level 字段（thread/start / thread/resume 接受），turn-level 不接受。每次 send 都重新设 thread-level 启用列表，harness 会按当前 thread 状态决定。

测试：3116 passed / 13 failed（与 v0.5.144/146 baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
