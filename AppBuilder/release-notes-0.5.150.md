# Tapgo AICoding 0.5.150

## PlanModeBanner 副文精简（28 → 10 字符）+ 完整说明放 tooltip

banner 副文从 "下一条消息会让 Codex 先出方案不执行工具" 精简到 "先出方案不执行工具"，避免 banner 过高。完整说明放 `.help(...)` tooltip（persistent 模式 vs single-shot 文案区分）。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner` 副文精简。
  - 给整个 banner 加 `.help(...)` tooltip：persistent 模式"Plan mode 常驻：所有消息都会让 Codex 先出方案不执行工具"；single-shot "Plan mode：下一条消息会让 Codex 先出方案不执行工具"。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
