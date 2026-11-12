---
kind: upgrade-guide
description: "原生 Cua Driver 调用使用元素令牌和具名配置字段。"
---

# 原生 Cua Driver 参数

[English](guide.md) | 中文

## 变更

[原生提供者](../../../../packages/experimental/computer-use-cua-driver-native/README.zh.md) 暴露 Cua Driver 0.47.19 工具。原生操作的参数不再接受分开的 `element_index` 和 `snapshot_id`。`set_config` 使用具名配置字段替代通用的 `key` 和 `value` 参数。自行构造这些调用的已有自动化需要更新参数；普通智能体会自动收到当前工具定义。

## 迁移

1. 对于原生元素操作，读取最新 `get_window_state`，传入返回的 `element_token`，替代 `element_index` 和 `snapshot_id`。再次获取该窗口快照后应刷新令牌。
2. 对于 `cua_driver_native__set_config`，使用发现的工具定义中的具名字段及允许值，例如 `"cursor.badges": "minimal"`，替代 `key`/`value` 键值对。
3. 确认已有调用符合发现的工具参数定义，并读取最新窗口状态验证操作结果。前台投递仍需显式指定；后台拒绝不代表已获准激活窗口。
