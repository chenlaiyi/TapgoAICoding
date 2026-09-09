# Tapgo AICoding 0.5.219

## 命令活动行完成态对齐 Codex 实机（终端 → 已运行）

- Codex 实机截图：完成态命令显示「已运行 <cmd>」（过去式），与 file edit / search 过去式一致。
- 此前 v0.5.199 设的「终端 cmd」前缀改回过去式「已运行 cmd」；失败态后缀「· 执行失败」保留。
- 同步更新 3 条 TurnPresentationTests 断言。

## 测试

全量回归 3125 通过 + 三机安装回读。
