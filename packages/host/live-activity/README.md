---
description: "APNs delivery for the iOS Live Activity: the phone registers one per-activity push token and the Host pushes turn progress computed from durable Session events, so the Dynamic Island keeps updating while the app is in the background."
kind: "package-reference"
---

# @deepseek-ai/dsh-host-live-activity

English | [中文](README.zh.md)

## Summary

The iOS app shows a running turn as a Live Activity. Once the phone leaves the app, only an ActivityKit push can refresh it. This package receives the activity's push token over two authenticated routes, watches the Session's durable events, and sends APNs updates whose content state matches the app's (`startedAt` in epoch seconds, `detail`, `running`). A finished turn sends one `end` event and drops the registration.

## Table of Contents

- [Use this package](#use-this-package)
- [Understand the implementation](#understand-the-implementation)
- [Further Exploration](#further-exploration)
- [Model Experience](#model-experience)
- [Known Limitations and Deferred Work](#known-limitations-and-deferred-work)

-----

## Use this package

Mount the plugin in a Host composition that serves the paired phone. Provide the APNs credentials either as plugin config (`bundleId`, `teamId`, `keyId`, `keyFile`, `environment`) or through the launch environment:

| Variable | Meaning |
| --- | --- |
| `TAPGO_APNS_BUNDLE_ID` | App bundle identifier; the APNs topic is `<bundleId>.push-type.liveactivity`. |
| `TAPGO_APNS_TEAM_ID` | Apple developer team identifier. |
| `TAPGO_APNS_KEY_ID` | Key identifier of the APNs `.p8` key. |
| `TAPGO_APNS_KEY_FILE` | Path to that key; on POSIX it must not grant group or other access. |

The app must enable the Push Notifications capability for its App ID and ship an `aps-environment` entitlement. Without credentials the plugin still serves the routes, reports `unconfigured`, and pushes nothing. The two routes require the composition's browser authentication (the phone's pairing cookie) and reject any other caller before reading a body.

### What the app sends

`POST /live-activity/register` carries `sessionId`, `activityId`, a hex `token` of at least 32 bytes, `title`, and `project`. A token the service reports as `Unregistered` or `BadDeviceToken`, or a device answering 410, is forgotten. `POST /live-activity/unregister` carries `activityId` and drops it immediately.

### Delivery policy

Progress is pushed at most once per `minPushIntervalMs` (default 5 s) per Session; the latest state wins, so a burst of tool calls collapses into one push. Every pushed update carries `stale-date` (`staleSeconds`, default 120) so iOS can age the state out. A turn end sends `event: "end"` with `running: false` and a dismissal date 60 s later.

-----

## Understand the implementation

<details>
<summary>Implementation internals — click to expand</summary>

### Event fold

`applySessionEvent` folds `turn/start`, `tool/call`, and `turn/end` into `{ startedAt, detail, running }`. A tool call becomes `正在<category> · <hint>`, where the hint is the first present of `title`, `description`, `command`, `cmd`, `file_path`, `path`, `query`, or `pattern`, and the category maps read/search/write/shell/code/web tool names to the same labels the app uses. Other events change nothing.

### Provider token and transport

`apnsJwt` builds an ES256 provider token from the `.p8` key, converting the DER signature into the fixed-width JOSE form; it is cached for 45 minutes. `createApnsSender` posts to the production or sandbox APNs host over HTTP/2 with `apns-push-type: liveactivity`, `apns-priority: 5`, and the live-activity topic. The transport is injectable, so tests assert headers, payloads, and unregistered/failed outcomes without a network.

### Lifecycle

Registrations live in memory for the plugin's lifetime; the Session-event listener is disposed with the fiber and pending throttle timers are cleared. A reconnect or app relaunch simply registers again, because the token belongs to the activity, not to a connection.

</details>

-----

## Further Exploration

- [iOS companion README](../../../mobile/ios/README.md) describes what the phone renders and when it registers.
- [Desktop README](../../../apps/desktop/README.md) covers the shared relay that routes the phone to this Host.

-----

## Model Experience

None, as the Host-side push sender reads Session events and sends APNs notifications without adding model context.

#### KV Cache effect

None; this package neither assembles nor sends a provider request.

## Known Limitations and Deferred Work

- APNs credentials are deployment-owned; the package never provisions, refreshes, or validates them beyond loading the key once per activation.
- Registrations are process-local. A Host restart loses them until the app registers again (which it does on the next activity update or reconnect).
- Push updates depend on iOS delivery budgets; a burst can be coalesced or dropped by the system, and Live Activities have a maximum lifetime enforced by iOS.
- Only one activity is tracked per Session; a second activity for the same Session replaces the previous push target only when its token is registered.
