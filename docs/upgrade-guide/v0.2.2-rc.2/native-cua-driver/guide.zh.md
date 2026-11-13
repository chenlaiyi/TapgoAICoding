---
kind: upgrade-guide
description: "原生 Cua Driver 调用使用元素令牌和具名配置字段。"
---

# 原生 Cua Driver 参数

[English](guide.md) | 中文

## 变更

[原生提供者](../../../../packages/experimental/computer-use-cua-driver-native/README.zh.md) 暴露 Cua Driver 0.47.19 工具。原生操作的参数不再接受分开的 `element_index` 和 `snapshot_id`。`set_config` 使用具名配置字段替代通用的 `key` 和 `value` 参数。自行构造这些调用的已有自动化需要更新参数；普通智能体会自动收到当前工具定义。

打包 macOS Desktop 的默认原生提供者改为 SDK 监督的私有 worker，以提供 Finder 文件夹交接所需的 AppKit 主循环。已有默认配置自动迁移；自定义提供者配置和 `CUA_DRIVER_*` 环境配置保持原运行方式。命令失败可能报告 `NATIVE_WORKER_CALL_FAILED`，此时输入可能已送达。

打包 macOS 的桌面级前台 `drag` 默认有条件地恢复原应用焦点与物理指针。恢复被跳过或失败时会返回工具错误，即使拖放已经送达。结果新增 `user_state_restoration`，与拖放结果独立。

## 迁移

1. 对于原生元素操作，读取最新 `get_window_state`，传入返回的 `element_token`，替代 `element_index` 和 `snapshot_id`。再次获取该窗口快照后应刷新令牌。
2. 对于 `cua_driver_native__set_config`，使用发现的工具定义中的具名字段及允许值，例如 `"cursor.badges": "minimal"`，替代 `key`/`value` 键值对。
3. 确认已有调用符合发现的工具参数定义，并读取最新窗口状态验证操作结果。前台投递仍需显式指定；后台拒绝不代表已获准激活窗口。

4. 自定义配置若需使用 worker，在原生提供者的 `config.worker` 中指定已签名 `binaryPath` 和 `hostBundleId`，并移除冲突的 `CUA_DRIVER_*` 配置；使用 `worker: false` 保留进程内模式。调用失败或取消后先读取新状态，再决定是否重试。

5. 需要保留上游前台拖放行为时，传入 `restore_user_state: false`。否则读取恢复报告并验证目标；`NATIVE_INTERACTION_UNAVAILABLE` 表示未发送拖放，`NATIVE_INTERACTION_FAILED` 表示结果不确定，不能直接重试。自定义 worker 可通过 `restoration.helperPath` 配置签名观察程序，或用 `restoration: false` 关闭该行为。
