# Tapgo AICoding 0.5.215

## 工具活动行标签对齐 Codex 实机（使用工具 · → 使用 ）

- Codex 截图实证活动行默认 fallback 格式为「已使用 <tool-name>」/「正在使用 <tool-name>」。
- 此前 Tapgo 默认工具行显示「使用工具 · <name>」/「正在使用工具 · <name>」——对齐后改为「使用 <name>」/「正在使用 <name>」（去掉「工具 · 」前缀）。
- 同步更新 ConversationPresentation 的 .tool 折叠标题，与 TurnPresentation 保持一致。

## 测试

全量回归 3122 通过 + 三机安装回读。
