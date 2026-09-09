# Tapgo AICoding 0.5.210

## 时长格式对齐 Codex 实机（中文 + 空格）

- `DurationFormatter` 输出从英文紧凑 (`5s`/`1m 05s`/`1h 00m`) 改为 Codex 中文带空格 (`5 秒`/`1 分 5 秒`/`1 小时 2 分 5 秒`)。
- 中间零值省略：`1 小时` (3600s)、`1 小时 5 秒` (3605s)、`1 小时 2 分` (3660s)，对齐 Codex `用时 11 分钟 10 秒` 类写法。
- 影响范围：`workTitle` 完成态（"已处理 X"）、`StreamingIndicator` 进行中计时、`Turn.durationText`/`Thread.durationTotalText`、composer 指标栏。

## 测试

全量回归 3120 通过 + 三机安装回读。
