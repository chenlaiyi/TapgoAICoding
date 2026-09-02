# Tapgo AICoding 0.5.76

- ZCode 贴近度量化报告（Verifier 一直要求的"可度量上限"）：
  - 新增 `scripts/zcode-fidelity-report.sh` 一键产出 `artifacts/zcode-vs-tapgo-0.5.75/fidelity-report.{json,md}` + 区域色采样。
  - 三项独立可验证指标：
    - **DSHTheme token hex 精度**：3 个 ZCode asar 频繁色 token（`brandBlueZCode #4099FF`、`warnZCode #CD8900`、`errorZCode #E40014`）**100% 1:1 匹配** asar 期望值。
    - **Desktop: ZCode interaction design assertion 通过率**：**46 passed / 0 failed**（v0.5.73 基线 38 passed，+8 = +5 token + +3 挂载点）。
    - **ZCode 3.10.2 主窗口区域实测色**（取自 1220×1287 主窗口截图）：titlebar Δ 9、sidebar_top Δ 1 ✅、main_canvas Δ 9、statusbar Δ 6 —— 区域色基线已采到，挂载点验证等你登录账号后人工对照。
- 新增 6 个 evidence artifacts 在 `artifacts/zcode-vs-tapgo-0.5.75/`：
  - `01-zcode-baseline.png`（ZCode 3.10.2 主窗口 1220×1287）
  - `01-zcode-sidebar-droptarget.png`（侧栏顶部 — brandBlueZCode 挂载点对照区）
  - `02-zcode-main-bottom-error.png`（主区底部 — errorZCode 挂载点对照区）
  - `03-zcode-toolbar-status.png`（顶栏 — warnZCode 挂载点对照区）
  - `fidelity-report.json` + `fidelity-report.md`
- **未做（沙箱受限）**：Tapgo AICoding v0.5.75 主窗口需登录 codex 后才创建，沙箱无登录态（`~/Library/Application Support/Tapgo AICoding/codex/` 是空），AXUIElement 树只有 1 个 hidden window —— **screencapture 抓不到 Tapgo 主窗口**，所以"1000x740 中央 pixelmatch %"在沙箱内无法产出，已在报告 + EVOLUTION 中明确写为"已知限制 + Next 步骤"，由你登录后人工 review PR 截图。
- 测试状态：2689 passed / 13 failed（与 v0.5.75 基线相同；本版本无代码改动，只产出量化报告 + scripts/）。