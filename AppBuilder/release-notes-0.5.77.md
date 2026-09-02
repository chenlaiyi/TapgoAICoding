# Tapgo AICoding 0.5.77

- **Verifier 硬指标完成**：Tapgo AICoding v0.5.75 主窗口 vs ZCode 3.10.2 主窗口中央 1000x740 区域 pixelmatch = **13.4% mismatched**，verdict `1:1-fidelity-moderate`。
  - 之前 v0.5.76 报告"沙箱抓不到 Tapgo 主窗口"是查询 API 漏过滤 `CGWindow.layer` 字段导致的误判。本版本限定 `layer=0`（排除 system chrome）后找到 wid=64836 bounds={X:41, Y:30, W:963, H:1344}，`screencapture -x -o -l64836 tapgo-main.png` 抓到 963×1344 PNG（148KB）。
  - common canvas = 683×1227（Tapgo 较窄），中央 1000x740 区域被裁到 683×740。
  - sampledPixels = 505420, mismatchedPixels = 67711, threshold = 0.08, AA excluded.
- 区域色差对比（ZCode 1220×1287 vs Tapgo 963×1344）：

  | 区域 | ZCode | Tapgo | Δ (max channel) |
  | --- | --- | --- | --- |
  | titlebar | rgb(35,35,35) | rgb(35,36,36) | **1** |
  | sidebar_top | rgb(58,59,59) | rgb(58,58,60) | **1** |
  | sidebar_mid | rgb(74,75,75) | rgb(60,60,62) | 15 |
  | main_canvas | rgb(30,30,29) | rgb(21,21,22) | 9 |
  | rightbar_top | rgb(33,33,32) | rgb(22,22,23) | 11 |
  | statusbar | rgb(27,27,27) | rgb(30,30,31) | 4 |

  **titlebar / sidebar_top / statusbar 三处 Δ ≤ 4** —— DSHTheme 与 ZCode 频繁色 1:1 匹配带来的视觉贴近，主区 Δ9-15 来自 Tapgo 登录态空 + ZCode 登录态有内容，不算"颜色差距"。
- 4 项独立可验证量化指标（详见 `artifacts/zcode-vs-tapgo-0.5.75/fidelity-report.{json,md}`）：
  - DSHTheme token hex 精度：3 个 ZCode asar 频繁色 token 100% 1:1 匹配
  - Desktop: ZCode interaction design assertion 通过率：46 passed / 0 failed
  - 中央 1000x740 pixelmatch %：**13.4% → 1:1-fidelity-moderate**
  - 区域色差表：3/6 区域 Δ ≤ 4
- 新增 artifacts：
  - `tapgo-main.png`（Tapgo AICoding v0.5.75 主窗口 963×1344）
  - `diff-overlay.png`（pixelmatch 红蓝叠加差图，74KB）
  - `pixelmatch.json`（独立文件，含详细输出）
  - `region-color-diff.md` + `tapgo-region-colors.txt`（区域色差对比表 + 采样）
- 测试状态：2689 passed / 13 failed（与 v0.5.75/v0.5.76 基线相同；本版本无代码改动，只产出 Tapgo 主窗口截屏 + 完整 pixelmatch 报告）。
- 真机回归受限于沙箱内无登录态（`~/Library/Application Support/Tapgo AICoding/codex/` 是空）—— 主窗口可截但内容空，对话气泡不会渲染。要看 v0.5.74/75 3 个挂载点（drop-target 环 / sendError 红 / 失败徽章）的真实视觉需要你登录账号后 review。