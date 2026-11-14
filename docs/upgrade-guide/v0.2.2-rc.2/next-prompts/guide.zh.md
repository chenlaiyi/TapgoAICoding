---
kind: upgrade-guide
description: "含下一步提示词事件的会话需要使用认识这些事件的读取器。"
---

# 下一步提示词会话事件

[English](guide.md) | 中文

## 变更

Web 和桌面端在成功回复后生成可选的下一步提示词。准确的独立模型请求与推荐结果向会话日志新增 `session/next-prompts-request` 和 `session/next-prompts-result`。不认识这些必读事件的旧读取器会拒绝受影响的日志。更新后的应用仍能读取已有日志。

## 迁移

1. 打开含新事件的会话前，更新共享这些会话文件的所有 Web、桌面和 SDK 读取器。此后不要降级共享读取器。
2. 如需禁用额外模型请求，在启动新轮次前为 `next-prompts` 条目设置 `config.enabled: false`。禁用不会移除已有事件。
3. 在更新后的应用中完成一次回复，确认点击推荐只修改草稿、不发送。重开会话，确认最新推荐仍然可用。[生成器参考](../../../../packages/session/next-prompts/README.zh.md)说明了请求限制和失败行为。
