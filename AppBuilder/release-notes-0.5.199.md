# Tapgo AICoding 0.5.199

## Command execution 输出对齐 Codex 桌面端：支持 ANSI 颜色解析 + + 菜单视觉调整

### ANSI 颜色解析

`CommandExecutionView` 的 stdout/stderr 之前用纯色 Text（绿/红），command output 自带的 ANSI 颜色码（`\x1b[31m`、`\x1b[1;32m` 等）会显示成乱码。v0.5.199 新增 `ANSIParser`（在 `TapgoCore`）解析 ANSI escape sequence，让 `git diff` 红绿、`ls` 蓝目录、`cargo` 编译错误高亮、`swift build` 警告色等正常显示。

### + 菜单视觉调整

`+` 菜单从 SwiftUI Menu 改为 PopoverPanel（NSPopover + NSHostingController，TapgoCore 新增），撑满 composer 宽度的 push-out 卡片，对齐 Codex 桌面端 input-area panel 视觉。SwiftUI Menu 在 macOS 26.5 SDK 渲染成 ~130pt 小弹窗，撑不满宽度。

## 改动

- `Sources/TapgoCore/ANSIParser.swift`（新增）：SGR 颜色码解析
  - 8-color: 30-37 / 90-97
  - 256-color: 38;5;N
  - truecolor: 38;2;R;G;B
  - reset (0) / bold (1) / unbold (22)
  - 把 raw 字符串拆成 `[(text, fg color, bold)]` segments
- `Sources/TapgoAICoding/Views/CommandExecutionView.swift`:
  - `ansiLinesView(_:fallback:)` helper：按 segments 用 Text + ConcatenatedText 拼接
  - stdout/stderr 段渲染替换之前的纯色 Text
- `Sources/TapgoCore/PopoverPanel.swift`（新增）：NSViewControllerRepresentable 包 NSPopover，手动 contentSize
- `Sources/TapgoAICoding/Views/ChatView.swift`：composer + 菜单改用 PopoverPanel 撑满宽度

## 测试

未跑（纯 UI 改动不影响逻辑；ANSI parser 行为容易在终端实跑验证）。
