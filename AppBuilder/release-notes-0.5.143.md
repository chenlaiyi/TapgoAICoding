# Tapgo AICoding 0.5.143

## Plan mode 与 harness 协议深度集成（turn-level policy 覆盖）

- `Sources/TapgoAICoding/Services/CodexHarnessClient.swift`:
  - `run(...)` 加 `planMode: Bool = false` 参数。
  - plan mode 时 turn/start 在 params 里附加 `approvalPolicy: "on-request"` + `sandbox: "read-only"`，让 harness 在每个工具调用前停下来等用户批准（thread 级策略不动，下次 send 关闭 plan mode 自动恢复）。
- `Sources/TapgoAICoding/Services/SessionStore.swift`:
  - `QueuedMessage` 加 `var planMode: Bool = false`，drain 排队消息时保留原 plan mode。
  - `sendUserMessage(_:planMode:)` / `sendNow(_:images:threadId:planMode:)` 透传 planMode 到 `newRunner.run(planMode:)`。
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `send()` 调用 `store.sendUserMessage(payload, planMode: planningMode)`，文本前缀 + 协议层双重生效。

效果：v0.5.141 之前 Plan mode 是文本层 hack（消息前缀 `[计划模式] 请先给方案...`），依赖模型本身听话。v0.5.143 在 harness 协议层强制 read-only + 每次工具调用前询问，harness 行为跨 Codex app-server 版本一致；同时配合现有 `ApprovalRow` UI（v0.4.1+ 已接通），用户在聊天里接受 plan 后才允许工具继续。

测试：3117 passed / 12 failed（基线一致）。开发者签名有效；尚未完成 Apple 公证。
