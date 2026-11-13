---
kind: upgrade-guide
description: "Native Cua Driver calls use element tokens and typed configuration fields."
---

# Native Cua Driver arguments

English | [中文](guide.zh.md)

## Change

The [native provider](../../../../packages/experimental/computer-use-cua-driver-native/README.md) exposes Cua Driver 0.47.19 tools. Native action schemas no longer accept separate `element_index` and `snapshot_id` arguments. `set_config` replaces generic `key` and `value` arguments with named configuration fields. Saved automation that constructs these calls must update its arguments; ordinary agents receive the current schemas automatically.

Packaged macOS Desktop changes its default native provider to an SDK-supervised private worker supplying the AppKit main loop for Finder folder handoff. Default profiles migrate automatically; custom provider configuration and `CUA_DRIVER_*` environment configuration retain their runtime choice. A lost result can report `NATIVE_WORKER_CALL_FAILED` even when input was delivered.

Packaged macOS desktop-scope foreground `drag` now conditionally restores the original application focus and physical pointer by default. Skipped or failed restoration reports a tool error even if the drag was delivered. The result adds `user_state_restoration` independently of the drop outcome.

## Migration

1. For native element actions, read a fresh `get_window_state` and pass the returned `element_token` instead of `element_index` and `snapshot_id`. Refresh the token after another snapshot of that window.
2. For `cua_driver_native__set_config`, use the named fields and accepted values in the discovered schema, such as `"cursor.badges": "minimal"`, instead of a `key`/`value` pair.
3. Confirm that saved calls validate against the discovered tool schema and verify action outcomes from a fresh window state. Foreground delivery remains explicit; a background refusal does not grant permission to activate a window.

4. To opt a custom configuration into a worker, supply its signed `binaryPath` and `hostBundleId` under the native provider's `config.worker` and remove conflicting `CUA_DRIVER_*` configuration. Use `worker: false` to retain in-process mode. After a failed or cancelled call, inspect fresh state before retrying.

5. Pass `restore_user_state: false` when saved foreground drags must keep upstream behavior. Otherwise read the restoration report and verify the destination. `NATIVE_INTERACTION_UNAVAILABLE` means no drag was sent; `NATIVE_INTERACTION_FAILED` means the outcome is uncertain and must be inspected before retry. Custom workers can configure a signed observer with `restoration.helperPath` or disable it with `restoration: false`.
