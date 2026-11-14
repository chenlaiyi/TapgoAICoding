---
description: "Records a persistence type transition and its compatibility acknowledgement."
kind: persistence-change
---

# 2026-11-14-next-prompts

English | [中文](2026-11-14-next-prompts.zh.md)

## Summary

Adds independent next-prompt request audit events and validated recommendation results for the Web and desktop composer.

## Table of Contents

- [Declaration](#declaration)
- [Compatibility](#compatibility)
- [Verification](#verification)
- [Dev Note](#dev-note)

<a id="declaration"></a>
## Declaration

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
## Compatibility

Existing logs remain valid. New event discriminators are log-only and do not enter model history. Updated readers recover recommendations through the nextPrompts projection; older readers that do not recognize these required events refuse them rather than misinterpret them. The Session writer version is unchanged.

<a id="verification"></a>
## Verification

pnpm exec vitest run packages/session/next-prompts/tests/generation.spec.ts packages/client/ui-next-prompts/tests/next-prompts.client.spec.tsx: 10 tests passed, covering exact request logging, deduplication, invalid output, cancellation, disabled generation, draft preservation and explicit sending.

<a id="dev-note"></a>
## Dev Note

None.
