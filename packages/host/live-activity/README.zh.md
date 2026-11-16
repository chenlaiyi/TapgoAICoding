---
description: "iOS 实时活动的 APNs 下发：手机登记每条活动的推送令牌，Host 根据持久会话事件推送当前进度，让 App 退到后台后灵动岛仍能更新。"
kind: "package-reference"
---

# @deepseek-ai/dsh-host-live-activity

[English](README.md) | 中文

## 摘要

iOS 端把运行中的回合显示为实时活动。离开 App 后只有 ActivityKit 推送才能继续刷新。本包通过两条需要认证的路由接收活动的推送令牌，监听会话的持久事件，并发送内容状态与 App 一致的 APNs 更新（`startedAt` 为 Unix 秒、`detail`、`running`）。回合结束时发送一次 `end` 并删除登记。

## 目录

- [使用本包](#use-this-package)
- [实现说明](#understand-the-implementation)
- [延伸阅读](#further-exploration)
- [模型体验](#model-experience)
- [已知限制与未完成](#known-limitations-and-deferred-work)

-----

## 使用本包

把它挂在服务已配对手机的 Host 组合里。APNs 凭据可通过插件配置（`bundleId`、`teamId`、`keyId`、`keyFile`、`environment`）或启动环境提供：

| 变量 | 含义 |
| --- | --- |
| `TAPGO_APNS_BUNDLE_ID` | App bundle id；APNs topic 为 `<bundleId>.push-type.liveactivity`。 |
| `TAPGO_APNS_TEAM_ID` | Apple 开发者团队标识。 |
| `TAPGO_APNS_KEY_ID` | APNs `.p8` 密钥的 Key ID。 |
| `TAPGO_APNS_KEY_FILE` | 该密钥的路径；POSIX 上不得授予组或其他用户访问权限。 |

App 必须为 App ID 打开 Push Notifications 能力，并带上 `aps-environment` 授权。没有凭据时插件仍提供路由，但返回 `unconfigured`，不推送任何内容。两条路由都先经过宿主浏览器认证（手机的配对 Cookie），其他调用方在读取请求体之前即被拒绝。

### App 发送什么

`POST /live-activity/register` 携带 `sessionId`、`activityId`、至少 32 字节的十六进制 `token`、`title`、`project`。服务报告 `Unregistered`/`BadDeviceToken` 或设备返回 410 时丢弃该令牌。`POST /live-activity/unregister` 携带 `activityId`，立即删除。

### 下发策略

每个会话最多每 `minPushIntervalMs`（默认 5 秒）推送一次进度，最新状态覆盖旧的，密集的工具调用会合并为一次推送。每次更新都带 `stale-date`（`staleSeconds`，默认 120），让 iOS 可以判定状态过期。回合结束发送 `event: "end"`（`running: false`），60 秒后由系统移除。

-----

## 实现说明

<details>
<summary>实现细节——点击展开</summary>

### 事件折叠

`applySessionEvent` 把 `turn/start`、`tool/call`、`turn/end` 折叠为 `{ startedAt, detail, running }`。工具调用显示为 `正在<类别> · <提示>`，提示取 `title`、`description`、`command`、`cmd`、`file_path`、`path`、`query`、`pattern` 中第一个非空值；类别把读/搜/写/命令/代码/网页等工具名映射为与 App 相同的文案。其他事件不改变状态。

### 提供方令牌与传输

`apnsJwt` 用 `.p8` 生成 ES256 提供方令牌，把 DER 签名转换为 JOSE 定长格式，并缓存 45 分钟。`createApnsSender` 通过 HTTP/2 向生产或沙盒 APNs 发送，携带 `apns-push-type: liveactivity`、`apns-priority: 5` 与实时活动 topic。传输层可注入，测试无需网络即可断言请求头、载荷以及 unregistered/failed 结果。

### 生命周期

登记只在插件生命周期内保存在内存中；事件监听随 fiber 释放，未触发的节流定时器会被清理。重连或 App 重启后重新登记即可，因为令牌属于活动而不是连接。

</details>

-----

## 延伸阅读

- [iOS 端说明](../../../mobile/ios/README.zh.md) 描述手机渲染什么、何时登记。
- [桌面端说明](../../../apps/desktop/README.zh.md) 覆盖把手机路由到本 Host 的共享中继。

-----

## 模型体验

无：Host 侧只读取会话事件并发送 APNs 通知，不向模型上下文加入任何内容。

#### KV Cache 影响

无；本包既不组装也不发送模型请求。

## 已知限制与未完成

- APNs 凭据由部署方维护；插件只在启动时加载一次密钥，不负责申请、轮换或校验。
- 登记保存在进程内，Host 重启后丢失，直到 App 下次更新活动或重连时重新登记。
- 推送受 iOS 投递预算限制，密集更新可能被合并或丢弃；实时活动本身还有系统强制的最长存活时间。
- 一个会话只跟踪一条活动；同一会话的第二条活动只有在登记其令牌后才会替换旧的推送目标。
