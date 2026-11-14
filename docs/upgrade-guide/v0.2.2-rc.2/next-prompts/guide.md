---
kind: upgrade-guide
description: "Sessions with next-prompt events require a reader that recognizes those events."
---

# Next-prompt Session events

English | [中文](guide.zh.md)

## Change

Web and desktop generate optional next prompts after successful replies. Their exact independent model requests and recommendation results add `session/next-prompts-request` and `session/next-prompts-result` to the Session log. Older readers that do not recognize these required events refuse affected logs. Existing logs remain readable by the updated application.

## Migration

1. Update every Web, desktop and SDK reader sharing these Session files before opening a Session containing the new events. Do not downgrade the shared reader afterward.
2. To disable the additional model requests, patch the `next-prompts` row with `config.enabled: false` before starting new turns. Disabling generation does not remove already recorded events.
3. Complete a reply in the updated application and confirm that clicking a recommendation changes the draft without sending it. Reopen the Session and confirm that its latest recommendations remain available. The [generator reference](../../../../packages/session/next-prompts/README.md) describes request limits and failure behavior.
