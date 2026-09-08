# Tapgo AICoding 0.5.189

## streaming 时显示闪烁光标（对齐 Codex 桌面端）

`MarkdownMessageView` 有 `isStreaming` 参数但 body 里没实现光标闪烁。Codex 桌面端 streaming 时显示 0.5s 周期闪烁的"▍"光标，v0.5.189 让 Tapgo 跟上。

- `Sources/TapgoAICoding/Views/MarkdownMessageView.swift`:
  - body 末尾加 `.overlay(alignment: .bottomLeading)` + `if isStreaming { StreamingCursor() }`
  - 新增 `StreamingCursor` View：TimelineView(.periodic 0.5s) 切换"▍"光标的 opacity（用 `timeIntervalSince1970.truncatingRemainder(dividingBy: 1) < 0.5` 决定显隐）+ brand 色。

测试：3117 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
