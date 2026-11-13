---
description: "Run Cua Driver computer-use tools from its native npm SDK, with durable screenshots and explicit host desktop permissions."
kind: "package-reference"
---

# @deepseek-ai/dsh-experimental-computer-use-cua-driver-native

English | [中文](README.zh.md)

## Summary

Use Cua Driver to inspect and operate desktop windows without installing a separate permission-owning application. The native npm dependency runs inside the DSH host or supervises a private worker and exposes Cua Driver's own tools. Screenshots reach image-capable models through durable attachments. This published experimental package requires the launching host's desktop permissions and remains an explicit composition choice.

## Table of Contents

- [Use this package](#use-this-package)
- [Understand the implementation](#understand-the-implementation)
- [Further Exploration](#further-exploration)
- [Model Experience](#model-experience)
- [Known Limitations and Deferred Work](#known-limitations-and-deferred-work)
- [Dev Note](#dev-note)

-----

<a id="use-this-package"></a>
## Use this package

Mount the provider in a composition that already supplies the tool registry and system prompt.

### Minimal configuration

```yaml
- name: '@deepseek-ai/dsh-computer-use'
- name: '@deepseek-ai/dsh-experimental-computer-use-cua-driver-native'
```

The default `worker: false` uses the in-process runtime. A `worker` object supplies `binaryPath` and `hostBundleId` for an SDK-supervised private process over inherited stdio, without a socket. This process supplies the macOS AppKit main loop needed for Finder folder handoff. It permits standard permission mode only, retains host permission attribution, and requests no additional OS grant. Any `CUA_DRIVER_*` environment configuration rejects worker startup rather than replacing custom policy. The provider loads the exact SDK version in [package.json](package.json). Initialization, catalog, or exclusive registration failures roll back resources. Its registered name is `cua-driver-native`.

Worker timing fields are positive integers: `startupTimeoutMs` (10000), `shutdownTimeoutMs` (2000), `maxSessionTtlSeconds` (86400), and `maxIdleTtlSeconds` (3600). Startup and shutdown failures report `NATIVE_WORKER_STARTUP_FAILED` and `NATIVE_WORKER_SHUTDOWN_FAILED`; policy conflicts report `NATIVE_WORKER_CONFIGURATION_INVALID`. `NATIVE_WORKER_CALL_FAILED` means the result was lost and input may have been delivered; inspect fresh state before retrying. Failed shutdown retains the exclusive registration and requires a Host restart.

Use an attachment store and a model route that explicitly declares image input to receive screenshots. The [MCP result adapter](../../mcp/mcp-client/README.md) owns image admission and diagnostic behavior; programmatic callers retain the canonical raw result when a model cannot receive its images. Calls use Cua Driver's upstream tool parameters and results.

<a id="restore-state-after-foreground-drags"></a>
### Restore state after foreground drags

Packaged macOS Desktop configures `restoration` for its default worker. Its `helperPath` points to a native observer inside the same signed application. This configuration serializes SDK calls so another call from the provider cannot interleave with restoration. The observer records input-source PIDs, application activations, and positions, without recording keys or text or requesting new OS grants.

A desktop-scope `drag` with explicit `delivery_mode: foreground` enables `restore_user_state` by default: capture the original application and pointer, wait for release and native drag-session completion, then restore them. Outside input, unexpected activation, a pointer away from the release point, lost observation, or original-application exit prevents restoration. Set `restore_user_state: false` to keep upstream behavior. Other drag modes do not enable restoration and reject explicit `true`. This still uses the foreground and physical pointer.

The result's `user_state_restoration` reports focus, pointer, input sources, and restoration status independently of whether the drop landed; verify the drop from fresh state. Skipped or failed restoration is a tool error and does not undo the drag. Unavailable observation reports `NATIVE_INTERACTION_UNAVAILABLE` before dispatch; later process or protocol failures report `NATIVE_INTERACTION_FAILED`, requiring inspection before retry. Cancellation or Host exit closes the observer without deferred restoration.

`restoration.timeoutMs` (5000) bounds handshake and finish, `pollMs` (20) controls native polling, and `leaseMs` (30000) bounds the process lifetime, all in milliseconds.

### Host requirements

The native dependency supplies platform binaries through npm optional dependencies. Keep optional dependencies enabled. Grant desktop permissions to the application that launches DSH; this provider neither installs a permission-owning app nor changes OS grants. In-process mode shares the host process, so native crashes can terminate the host. The SDK supervises a private worker and closes it on unload. Use the [installed MCP provider](../computer-use-cua-driver-mcp/README.md) when the separate Cua Driver application should own permissions and execution.

### Verify the installed SDK

From the repository root, run this opt-in check against the installed native dependency. It discovers tools, reads permission status with `prompt: false`, and verifies teardown; it captures no screenshots, sends no input, and requests no OS permissions. Clearing `NODE_USE_ENV_PROXY` prevents Node from installing the launching shell's proxy before test setup.

```sh
env -u NODE_USE_ENV_PROXY DSH_COMPUTER_USE_NATIVE_E2E=1 node node_modules/vitest/vitest.mjs run --config vitest.e2e.config.ts packages/experimental/computer-use-cua-driver-native/tests/native.e2e.ts
```

-----

<a id="understand-the-implementation"></a>
## Understand the implementation

<details>
<summary>Implementation internals — click to expand</summary>

The provider reserves the shared computer-use registration before loading native code. A child plugin owns discovery, model tools, guidance, and the native runtime. The parent retains the registration until child teardown has removed tools, interrupted native calls and image-capability admission, awaited settlement, and completed native shutdown. Cancellation does not undo input already delivered to an application.

| File | Role |
|---|---|
| [src/index.ts](src/index.ts) | Native runtime ownership, catalog validation, tool registration, and provider guidance |

Tool definitions reuse the existing MCP result adapter. Cua Driver's JSON catalog determines the schemas; its raw result supplies canonical text, structured output, and image bytes. The computer-use service carries only the provider name and exclusive registration.

</details>

-----

<a id="further-exploration"></a>
## Further Exploration

- [Computer-use service](../../computer-use/computer-use/README.md) — exclusive named registration.
- [MCP client](../../mcp/mcp-client/README.md) — shared result and image projection.
- [Cua Driver SDK](https://cua.ai/docs/reference/cua-driver/sdk-reference) — upstream runtime API and host facilities.

-----

<a id="model-experience"></a>
## Model Experience

### System prompt

#### What the model sees

The provider contributes the following computer-use guidance while its native tools are mounted.

##### Native Cua Driver guidance

```markdown
Cua Driver native computer-use tools operate the host desktop. For native window actions, discover the exact app and window, then get a fresh window snapshot before acting. Use element_token from that snapshot, or coordinates from its screenshot. A new snapshot of that window invalidates its earlier element tokens. Select either target or the legacy pid/window_id fields; do not combine them. For browser actions, bind the exact tab with get_browser_state and use its page refs or viewport screenshot; do not infer viewport coordinates from a native window screenshot.

Prefer background delivery. A refusal does not authorize a foreground retry. Verify the requested outcome from fresh state after an action; a delivered click alone does not prove the outcome. After cancellation, inspect current state before retrying because completed input is not rolled back. Other sessions and applications may change the same desktop.

On macOS, in-process cursor-overlay operations may return facility_unavailable even when screenshots and input work. If no active application is reported, focus is unknown; the presence of another process does not identify what changed it.
```

#### Token effect

This fixed guidance adds system-prompt tokens while the provider is mounted. Upstream guidance resources are not automatically loaded.

#### KV Cache effect

The unchanged guidance preserves its repeated prompt prefix. Mounting, removing, or editing it changes that prefix and can reduce cache reuse.

### Discovered Cua Driver tools and results

#### What the model sees

Tools use the `cua_driver_native__` prefix followed by the upstream name and retain the upstream descriptions and input schemas. Upstream tool refusals become tool errors. Supported screenshots appear as durable image references beside result text. Structured result JSON also reaches model history, including window identifiers, element tokens, coordinates, and browser refusal details; the canonical raw result remains available to programmatic callers.

#### Token effect

The discovered catalog adds tool definitions to each request. Enabling restoration adds its drag parameter description and per-drag observation results. Accessibility trees, result text, and admitted screenshots add per-call context. Raw base64 remains in execution-local canonical values and is not copied into model history.

#### KV Cache effect

An unchanged catalog preserves its tool-definition prefix. Tool results append to Session history. Replacing the provider or its catalog changes the model-visible tools and can reduce prefix reuse.

## Known Limitations and Deferred Work

<a id="known-limitations-and-deferred-work"></a>

The package preserves the upstream driver's platform and application limits.

- **Host permissions and graphics session** — npm installation does not grant desktop access or create a graphical session.
- **Native cursor overlay** — an in-process macOS Node host without AppKit can receive `facility_unavailable` for overlay operations while screenshots and background input remain usable.
- **macOS drag and trusted browser input** — background window drags support pointer widgets; macOS drag-and-drop sessions can require explicit foreground delivery. Trusted browser clicks and pointer actions accept `delivery_mode: "foreground"` when their background route refuses. `input_route: "dom_event"` remains synthetic and does not satisfy controls that require trusted events. Verify each result from fresh state.
- **Shared desktop** — the provider does not reserve windows or complete workflows for a Session. Other callers and applications can change the same desktop between calls.
- **Cancellation** — an aborted call can have delivered input already; inspect fresh state before retrying. The provider waits for SDK shutdown during unload but does not promise native action rollback.
- **Failed shutdown** — if native shutdown fails, the registration remains occupied. Restart the host before mounting another computer-use provider.
- **Experimental release** — tool schemas follow the pinned upstream SDK and have no DSH stability promise.

<a id="dev-note"></a>
### Dev Note

<details>
<summary>Working context for maintainers — click to expand</summary>

None.

</details>
