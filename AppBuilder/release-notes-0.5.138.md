# Tapgo AICoding 0.5.138

## 更新日志 sheet 加日期筛选

- `ReleaseNotesSheet` 顶部加 segmented `Picker`（4 档）：**全部 / 最近 7 天 / 最近 30 天 / 最近 90 天**。
- 拆 `recentEntries()` 为 `parsedEntries()` 返回 `(version, title, date)`，从 `**Date**: yyyy-MM-dd` 行解析日期。
- 新 `filteredEntries(range:)` 按 `DateRange.days` 截断筛选。
- 筛选后为空时显示"无符合时间范围的更新日志"。

测试：3117 passed / 12 failed（12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
