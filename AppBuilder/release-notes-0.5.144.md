# Tapgo AICoding 0.5.144

## 修复：Plan mode 强调色误用 brandPrimary（dark mode 下变白条 / 白色按钮）

用户报告：点 Plan 按钮后顶部出现白条，按钮本身也变白色块。根因：`DSHTheme.brandPrimary` 名字误导——它不是品牌蓝，而是「主前景色」（light: `0x0F1115` 近黑 / dark: `0xF9FAFB` 近白）。PlanModeBanner / Plan toggle / Stop 按钮 / ApprovalRow 批准按钮 之前都把它当强调背景色，在 dark mode 下变成白底。

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner.background`: `DSHTheme.brandPrimary` → `DSHTheme.brand`（真品牌蓝，light `0x4176E6` / dark `0x5686FE`）。
  - Plan toggle button background: 同上。
  - Stop 按钮圆形背景: 同上。
- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 批准按钮 `.tint()`: 同上。
- `Sources/TapgoAICoding/Views/ContentView.swift`:
  - 顺手修 `onReceive(tapgoOpenCommandPalette)` 的 toggle bug：之前 `showCommandPalette = true` 没 toggle，⌘K 不管 dock 开闭都会"打开"，违背 Codex 桌面端 toggle 语义；改成 `toggle()` 并同步发 `paletteDidOpen` / `paletteDidClose` 让 App.swift 的 `PaletteState` 跟踪正确状态。

测试：3116 passed / 13 failed（比 baseline 3117/12 多 1 个 SSH 网络性 fail，与改动无关）。开发者签名有效；尚未完成 Apple 公证。
