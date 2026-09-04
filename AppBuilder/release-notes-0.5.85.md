# Tapgo AICoding 0.5.85

- 「参照目标 IDE 风格」fidelity region token 化（patch）：
  - `DSHTheme.swift` 新增 6 个 `fidelityXxx` 静态常量，对应目标 IDE 主窗口 6 处实测区域色：
    - `fidelityTitlebar` = `#232323` (rgb 35,35,35)
    - `fidelitySidebarTop` = `#3A3B3B` (rgb 58,59,59)
    - `fidelitySidebarMid` = `#4A4B4B` (rgb 74,75,75) — 旧无对应 token，新提供
    - `fidelityMainCanvas` = `#1E1E1D` (rgb 30,30,29)
    - `fidelityRightbarTop` = `#212120` (rgb 33,33,32)
    - `fidelityStatusbar` = `#1B1B1B` (rgb 27,27,27) — 旧无对应 token，新提供
  - **本次不改任何视图 `.background(...)`** — 仅 token 化 + 锁定值。目的：让后续 patch 调色只动 DSHTheme 6 行常量，不需要 grep 全文找 hardcode；同时把当前与目标 IDE 的差异范围固化下来（titlebar 旧 0x1A1A1C 偏暗、main_canvas 旧 0x151517 偏暗、sidebar_mid / statusbar 旧无 token）。
  - `DesktopDesignParityTests.swift` 新增 6 个 `t.expect` 断言：未来谁误删/误改这 6 个 token 或 hex，CI 立即失败。
- 测试：2719 通过 / 13 失败（新增 6 个 fidelity token 断言；13 个失败仍为预存在远程 SSH 集成 + auth.json 缺失，零新回归）。
- 已知限制：token 化是 patch 1/2，patch 2/2 将把 4 处视图的 `.background` 切换到新 token，并验证 pixelmatch < 0.08 的目标 IDE 阈值。
