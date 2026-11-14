---
description: "Fill the composer from contextual next-prompt buttons without sending."
kind: "package-reference"
---

# @deepseek-ai/dsh-client-ui-next-prompts

English | [中文](README.zh.md)

## Summary

Display one to three next prompts below the latest completed reply in Web and desktop. Clicking a button fills an empty composer or appends to an existing draft, preserves attachments and inline references, and focuses the composer. The user edits and sends explicitly.

## Table of Contents

- [Use this package](#use-this-package)
- [Understand the implementation](#understand-the-implementation)
- [Model Experience](#model-experience)
- [Known Limitations and Deferred Work](#known-limitations-and-deferred-work)
- [Dev Note](#dev-note)

<a id="use-this-package"></a>
## Use this package

The Web bundle mounts this browser plugin with the [Host generator](../../session/next-prompts/README.md). Recommendations use the user's language. Buttons wrap at narrow widths, have a 44px minimum touch height, and support keyboard focus and activation. A generation failure displays a compact notice; ordinary typing remains available.

<a id="understand-the-implementation"></a>
## Understand the implementation

The plugin contributes to `conversation.chat.turnTail` and reads the `nextPrompts` projection through the framework. It renders only the matching completed turn. The click callback resolves the displayed Session's retained binding and calls `conversation.input.requestDraftInitialization` with `whenDraftExists: 'append'`; a locked or disposed input refuses the edit. No send operation is called. Unloading removes the slot and locale contribution.

<a id="model-experience"></a>
## Model Experience

### User-confirmed prompt

#### What the model sees

A selected recommendation reaches the model as the text content of a `user/message` event only after explicit sending. Rendering and draft editing supply no model input; the Host owns recommendation wording.

#### Token effect

No direct token effect until the user sends the draft, when ordinary user-message tokens apply.

#### KV Cache effect

Rendering and draft edits do not change model input. Explicitly sending a suggestion appends an ordinary user message.

## Known Limitations and Deferred Work

- Disabling the Host stops new requests; an already recorded latest result can still appear. Unfinished generation or an empty result shows no recommendation.
- Clicking while a submission locks the composer leaves its draft unchanged.

<a id="dev-note"></a>
### Dev Note

Non-authoritative development notes: none.
