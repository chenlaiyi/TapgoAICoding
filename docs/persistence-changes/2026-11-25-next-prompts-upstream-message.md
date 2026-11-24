---
description: "Records a persistence type transition and its compatibility acknowledgement."
kind: persistence-change
---

# 2026-11-25-next-prompts-upstream-message

English | [中文](2026-11-25-next-prompts-upstream-message.zh.md)

## Summary

Updates the declared next-prompt request message type to the upstream Message union.

## Table of Contents

- [Declaration](#declaration)
- [Compatibility](#compatibility)
- [Verification](#verification)
- [Dev Note](#dev-note)

<a id="declaration"></a>
## Declaration

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
## Compatibility

Both versions write one text user message with source kind user for each request. The changed union members are never written by this producer. Existing requests retain that same representation. The next-prompt projection replays the logged result without dispatching the logged request.

<a id="verification"></a>
## Verification

The next-prompts generation tests passed, including exact request logging and full replay without model calls.

<a id="dev-note"></a>
## Dev Note

None.
