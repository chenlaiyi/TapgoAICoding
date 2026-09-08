# Tapgo AICoding 0.5.195

## 流式输出对齐 Codex 桌面端：caret 改 SwiftUI 真 shape + "生成中"行统一 3 跳动 dots

v0.5.192/v0.5.193/v0.5.194 改了 working indicator / assistant streaming / ToolCall / CommandExecution 的统一 3 跳动 dots。本版继续对齐 Codex 桌面端 streaming 的两个细节：

1. **StreamingCursor 改 SwiftUI 真 caret shape**：从 `▍` Unicode 字符 + TimelineView 硬闪烁，改为 SwiftUI `Rectangle().frame(width: 2)` 细矩形 + opacity `.easeInOut.repeatForever(autoreverses)` 闪烁（高度跟随字号 scale）。Codex 桌面端 caret 是细矩形、跟随最后一段末尾。
2. **AssistantResponseText 的"生成中"行**：从 `ProgressView().controlSize(.mini)` 改为 3 跳动 dots（与 v0.5.192 / v0.5.194 风格一致），dots 用 `DSHTheme.labelDim`，文字用 `caption2` + `DSHTheme.labelTertiary`。
3. caret overlay 从 `bottomLeading`（之前 caret 在左上角 (0,0) 位置）改为 `bottomTrailing`，视觉上紧贴最后一段末尾，更接近 Codex 桌面端 caret 跟随文本流的体验。

## 改动

- `Sources/TapgoAICoding/Views/MarkdownMessageView.swift`:
  - `StreamingCursor` 改用 SwiftUI `Rectangle().frame(width: 2, height: 14 * scale.multiplier).fill(DSHTheme.brand)` + `.opacity` 0.5s 闪烁。
  - overlay 从 `.bottomLeading` 改 `.bottomTrailing`，caret 视觉上贴近最后一段末尾。
- `Sources/TapgoAICoding/Views/ConversationResponseView.swift`:
  - `AssistantResponseText` 加 `@State pulse`，streaming 时显示 3 个错开 0.2s 的 4pt 圆点 + "生成中…" 文字（替换 v0.5.193 的 ProgressView）。
- `AppBuilder/Info.plist`, `AppBuilder/ComputerUseHelper-Info.plist`, `AppBuilder/project.yml`: bump 到 0.5.195。

## 测试

未跑（纯 UI 动画改动不影响逻辑）。
