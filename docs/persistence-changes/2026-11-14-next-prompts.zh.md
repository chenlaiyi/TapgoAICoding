---
description: "记录持久化类型更改及其兼容性确认。"
kind: persistence-change
---

# 2026-11-14-next-prompts

[English](2026-11-14-next-prompts.md) | 中文

## 概述

为 Web 和桌面输入框新增独立的下一步提示词请求审计事件与校验后的推荐结果。

## 目录

- [声明](#declaration)
- [兼容性](#compatibility)
- [验证](#verification)
- [开发备注](#dev-note)

<a id="declaration"></a>
## 声明

```yaml persistence-change
schemaVersion: 1
id: 2026-11-14-next-prompts
baseline: false
changes:
  - root: "event:session/next-prompts-request"
    previous: null
    after: "385a58903bebf19b138d86f9bcb61a4e0e593fe50accd2c47f74c614afa1ec01"
    decision: same-version
  - root: "event:session/next-prompts-result"
    previous: null
    after: "3ed010bcc42d206c163ec021f2047357852b41b0af715392159d1064a006a4a7"
    decision: same-version
```

<a id="compatibility"></a>
## 兼容性

已有日志仍然有效。新事件判别符仅用于日志，不进入模型历史。更新后的读取器通过 nextPrompts 投影恢复推荐；不认识这些必读事件的旧读取器会拒绝读取，而不会错误解释。会话写入版本不变。

<a id="verification"></a>
## 验证

pnpm exec vitest run packages/session/next-prompts/tests/generation.spec.ts packages/client/ui-next-prompts/tests/next-prompts.client.spec.tsx：10 个测试通过，覆盖准确请求记录、去重、无效输出、取消、禁用生成、保留草稿及明确发送。

<a id="dev-note"></a>
## 开发备注

无。
