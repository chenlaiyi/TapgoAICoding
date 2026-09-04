# Tapgo AICoding 0.5.86

- 「参照目标 IDE 风格」fidelity patch 2/2：3 处视图背景切到 `fidelityTitlebar` token：
  - `ChatView.swift` L691 composer 工具栏 `.background(DSHTheme.titlebarBg)` → `.background(DSHTheme.fidelityTitlebar)`
  - `SidebarView.swift` L1036 底栏 `.background(DSHTheme.titlebarBg.opacity(0.45))` → `.background(DSHTheme.fidelityTitlebar.opacity(0.45))`
  - `RightWorkbenchView.swift` L864 工具栏 `.background(DSHTheme.titlebarBg)` → `.background(DSHTheme.fidelityTitlebar)`
  - 颜色由 DSHTheme 旧值 `#1A1A1C` (rgb 26,28) 切到目标 IDE 实测色 `#232323` (rgb 35,35,35)，3 处背景同步提亮 9 个等级，跟 `artifacts/zcode-vs-tapgo-0.5.75/fidelity-report.md` 标题栏实测色对齐。
  - `DesktopDesignParityTests.swift` 新增 3 个 `t.expect` 断言锁定 3 处视图对 `fidelityTitlebar` 的引用，未来谁退回 `titlebarBg` CI 立即失败。
- 配套：v0.5.85 引入的 6 个 `fidelityXxx` token 全部生效（titlebar/sidebarTop/sidebarMid/mainCanvas/rightbarTop/statusbar），本次只切 3 处主窗口高频可见背景；其余 4 个 token 留待后续 patch 视情况切换。
- 测试：2683 通过 / 13 失败（新增 3 个 view-tied 断言；13 个失败仍为预存在远程 SSH 集成 + auth.json 缺失，零新回归）。
- 已知限制：未跑自动 pixelmatch 验证（需要 screencapture + ImageMagick 链路，下次 patch 接入）；用户可对比本地 main canvas 区域色是否更接近目标 IDE 1220x1287 实机截图。
