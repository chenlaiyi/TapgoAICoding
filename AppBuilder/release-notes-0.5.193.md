# Tapgo AICoding 0.5.193

## 流式输出对齐 Codex 桌面端：assistant streaming 时显示"生成中"指示行

v0.5.192 改了 ConversationWorkingIndicator 用 3 跳动 dots，但 streaming 消息本身的 AssistantResponseText 没显示"生成中"指示。Codex 桌面端 streaming 时消息下方有 subtle "生成中..." 行。

- `Sources/TapgoAICoding/Views/ConversationResponseView.swift`:
  - `AssistantResponseText` 加 `@Environment(\.tapgoFontScale) private var scale: AppFontScale`
  - `body` 用 VStack 包 MarkdownMessageView + streaming 时显示 `ProgressView + "生成中…"` 行
  - `if isStreaming { HStack { ProgressView + Text } }`

测试：未跑（build 卡住）；纯 UI 改动不影响逻辑。开发者签名有效；尚未完成 Apple 公证。
