# Tapgo AICoding 0.5.128

## 测试覆盖升级

- `MakeHistory parity: structural and Info.plist sync` 套件从单向（makeHistory → EVOLUTION）升级为**双向严格**（makeHistory ↔ EVOLUTION）：
  - makeHistory 每个版本必须在 EVOLUTION.md 头部段出现
  - EVOLUTION.md 每个 v0.5+ 段必须在 makeHistory 出现（iOS 子项目 v1.x 与 v0.0-v0.2 旧段不参与）
- 补齐 19 个历史漏段以让测试通过：
  - makeHistory 新增 v0.3.0/2/3、v0.4.0/1/3、v0.5.0/1/4、v0.5.52、v0.5.58-61、v0.5.80/81、v0.5.84-99、v0.5.105、v0.5.108 等 19 个 EvolutionEntry（commit SHA 来自 git log 反查）
  - EVOLUTION.md 头部 v0.5.5 之前补齐 12 个 v0.3.0-v0.5.4 段

测试：3117 passed / 12 failed（+1 个新增双向校验，+16 个新增 makeHistory 条目；12 项 SSH 环境性不变）。开发者签名有效；尚未完成 Apple 公证。
