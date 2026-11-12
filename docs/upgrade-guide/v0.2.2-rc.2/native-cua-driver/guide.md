---
kind: upgrade-guide
description: "Native Cua Driver calls use element tokens and typed configuration fields."
---

# Native Cua Driver arguments

English | [中文](guide.zh.md)

## Change

The [native provider](../../../../packages/experimental/computer-use-cua-driver-native/README.md) exposes Cua Driver 0.47.19 tools. Native action schemas no longer accept separate `element_index` and `snapshot_id` arguments. `set_config` replaces generic `key` and `value` arguments with named configuration fields. Saved automation that constructs these calls must update its arguments; ordinary agents receive the current schemas automatically.

## Migration

1. For native element actions, read a fresh `get_window_state` and pass the returned `element_token` instead of `element_index` and `snapshot_id`. Refresh the token after another snapshot of that window.
2. For `cua_driver_native__set_config`, use the named fields and accepted values in the discovered schema, such as `"cursor.badges": "minimal"`, instead of a `key`/`value` pair.
3. Confirm that saved calls validate against the discovered tool schema and verify action outcomes from a fresh window state. Foreground delivery remains explicit; a background refusal does not grant permission to activate a window.
