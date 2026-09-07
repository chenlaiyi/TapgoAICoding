# Tapgo AICoding 0.5.127

## 测试覆盖

- 新增 `MakeHistory parity: structural and Info.plist sync` 套件（`MakeHistoryParityTests.swift`），字符串级扫描 `EvolutionLogView.swift` + `EVOLUTION.md` + `Info.plist` + `AppBuilder/project.yml`：
  - 抽 `version: "vX.Y.Z"` 模式验证 makeHistory 版本数 ≥ 20；
  - 验证 makeHistory 数组内引号数为偶数（防 v0.5.125 中文双引号导致吞下个 entry 的 bug 重现）；
  - 验证 makeHistory 最近 10 个版本都在 EVOLUTION.md 头部段出现（保证新发版同步双向）；
  - 验证 `Info.plist` 与 `project.yml` 的版本号一致。

测试：3116 passed / 12 failed（新增 6 个 MakeHistory 测试；12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
