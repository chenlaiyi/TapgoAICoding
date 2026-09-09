# Tapgo AICoding 0.5.203

## 修复：welcome / 自进化指令态不显示模型额度

- Composer 底栏的模型额度环（`contextMeterChip`）此前被 `if !isWelcome` 排除——新会话与自进化指令屏看不到额度。
- 额度数据来自全局 `rateLimits`（与是否已有会话无关），现改为**任何输入器状态下恒显**；hover/点击仍弹出套餐与余额明细。
- 顺带确认 0.5.202 生效：底栏模型 chip 已是 Codex 式纯文本（`GLM-5.3-Flash`）。

## 测试

构建 + 实机截图验证（welcome 态额度环显示 61%）+ 全量回归 + 三机安装回读。
