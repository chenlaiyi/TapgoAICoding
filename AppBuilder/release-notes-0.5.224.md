# Tapgo AICoding 0.5.224

## 补 v0.5.217/0.5.218/0.5.223 回归测试

- TurnPresentationTests：
  - `diffStats` 统计 +N/-M 准确性
  - `fileChangeCompletedLabel` 过去式 + 差异统计（已创建 / 已编辑 / 已删除 / 无 diff）
- ConversationPresentationTests 已对齐的 `workTitle(status:.completed, duration: 65) == "用时 1 分 5 秒"` 在本文件中复用断言

## 测试

全量回归 3135 通过 + 三机安装回读。
