# Tapgo AICoding 0.5.78

- **重打 v0.5.77 .app 并部署本机 + fafamacmini**（用户原话"请更新好了，发布上线"）：
  - `AppBuilder/Info.plist` `CFBundleShortVersionString` bump 0.5.75 → 0.5.77
  - `xcrun -sdk macosx26.5 swift build -c release --product TapgoAICoding` 0.15s
  - `xcrun -sdk macosx26.5 swift build -c release --product TapgoComputerUseMCP` 0.09s
  - Developer ID 重新签名 + Sparkle + computer-use-helper 重新嵌入
  - 产物：`Tapgo AICoding.app` 17MB（与 v0.5.77 commit 同源代码重出包）
- zip：`/tmp/Tapgo-AICoding-0.5.77.zip` 9.5MB，上传 release v0.5.77 assets
- 本机部署：`/Applications/Tapgo AICoding.app` v0.5.77
  - App PID **73238** + HarnessDaemon PID **73643** alive
- fafamacmini 部署：`/Applications/Tapgo AICoding.app` v0.5.77
  - scp + 远端 ditto + `open -g`
  - App PID **66479** + HarnessDaemon PID **65950** alive
- 顺便 commit `AppBuilder/release-notes-0.5.74.md`（v0.5.74 当初写好了但漏 commit）
- 测试状态：2689 passed / 13 failed（与 v0.5.77 基线相同；零代码改动，只重打 .app + 部署）。
- 真机回归：v0.5.78 build 出的 UI 包含 v0.5.74/75 加的 3 个 ZCode 频繁色挂载点（drop-target 环 = brandBlueZCode、sendError = errorZCode、失败徽章 = warnZCode）—— 你登录 codex 账号完成首次会话后即可肉眼对照 ZCode 真机。