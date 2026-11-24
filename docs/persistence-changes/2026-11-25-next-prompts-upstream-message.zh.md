---
description: "记录持久化类型更改及其兼容性确认。"
kind: persistence-change
---

# 2026-11-25-next-prompts-upstream-message

[English](2026-11-25-next-prompts-upstream-message.md) | 中文

## 概述

将后续提示建议请求的消息声明更新为上游 Message 联合类型。

## 目录

- [声明](#declaration)
- [兼容性](#compatibility)
- [验证](#verification)
- [开发备注](#dev-note)

<a id="declaration"></a>
## 声明

```yaml persistence-change
schemaVersion: 1
id: 2026-11-25-next-prompts-upstream-message
baseline: false
changes:
  - root: "event:session/next-prompts-request"
    previous: "2026-11-14-next-prompts"
    after: "9c1acbdb855533c65aefb28a25736b6b6b9dd17005ee73142d63d9fa426ff2fb"
    decision: same-version
```

<a id="compatibility"></a>
## 兼容性

两个版本都为每个请求写入一条来源类型为 user 的纯文本用户消息。此写入方不会写入发生变化的联合成员，已有请求保留相同表示。后续提示建议投影重放已记录的结果，不会重新发送已记录的请求。

<a id="verification"></a>
## 验证

后续提示建议生成测试通过，覆盖完整请求记录和不调用模型的全量重放。

<a id="dev-note"></a>
## 开发备注

无。
