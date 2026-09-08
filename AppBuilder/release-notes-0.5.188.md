# Tapgo AICoding 0.5.188

## 运行中 work 过程 assistantMessage 改为紧凑单行可展开

v0.5.187 让 running 时显示 work items 单行（对齐 Codex 桌面端），但 work 过程中的 assistantMessage（reasoning 提示文本）以完整 MarkdownMessageView 渲染——这是「重复显示」的来源之一（assistant 阶段性提示以完整 Markdown 展示，跟最终答案/其他 activity 重复）。

- `Sources/TapgoAICoding/Views/ConversationResponseView.swift`:
  - 新增 `ConversationWorkAssistantRow` view：单行显示 assistantMessage 文本前 60 字 + 折叠箭头，点击展开完整 Markdown。
  - `ConversationWorkDisclosure.expanded` 里 `.item(.assistantMessage)` 改用 `ConversationWorkAssistantRow` 替代 `MarkdownMessageView`。

效果：运行中每条 work item 都是紧凑单行（包括 assistant 阶段性提示），用户点击展开查看完整内容，跟 Codex 桌面端 UI 行为一致。

测试：3117 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
