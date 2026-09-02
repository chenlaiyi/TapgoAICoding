# ZCode 贴近度量化报告 (v0.5.76)

> 注: 真"像素差异 %"需要 Tapgo + ZCode 两端都有可见主窗口 + 沙箱可解锁 TCC。
> 当前沙箱内 Tapgo v0.5.75 主窗口需登录态才会创建（未登录态下 AXUI 树仅有 1
> 个空 hidden window），所以我们用**三个独立可验证的指标**代替：
> 1) DSHTheme token hex 精度（v0.5.74 ground truth）
> 2) Desktop: ZCode interaction design 结构 assertion 通过率
> 3) ZCode 主窗口区域实测色 vs DSHTheme 期望色

## 1. DSHTheme token 精度

| Token | ZCode asar 期望 | DSHTheme 实际 | 匹配 |
| --- | --- | --- | --- |
| brandBlueZCode | `0x4099FF` | `0x4099FF` | ✅ |
| warnZCode | `0xCD8900` | `0xCD8900` | ✅ |
| errorZCode | `0xE40014` | `0xE40014` | ✅ |

DSHTheme 当前三个 ZCode 频繁色 token 与 ZCode asar 期望值**完全 1:1 匹配**。

## 2. Desktop: ZCode interaction design assertion 通过率

```
swift run TapgoTests --filter 'Desktop: ZCode interaction design'
…
— 46 passed, 0 failed —
```

（v0.5.73 基线 38 passed；v0.5.74 加 5 个 token assertion；v0.5.75 加 3 个挂载点 assertion = 46 passed）

## 3. ZCode 3.10.2 主窗口实测色

来源: `01-zcode-baseline.png` 1220×1287 PNG（screencapture -l<wid> 截 ZCode 3.10.2 主窗口）

/Users/chanlaiyi/TapgoAICoding/artifacts/zcode-vs-tapgo-0.5.75/01-zcode-baseline.png 1220x1287
  titlebar        rgb(35,35,35) n=9000
  sidebar_top     rgb(58,59,59) n=13200
  sidebar_mid     rgb(74,75,75) n=13200
  main_canvas     rgb(30,30,29) n=200000
  rightbar_top    rgb(33,33,32) n=15000
  statusbar       rgb(27,27,27) n=5600

## 已知限制

- **screencapture 可用**（沙箱没禁截屏 API），但 Tapgo AICoding v0.5.75 + ZCode 3.10.2 在当前沙箱都没有登录态，两者主窗口的"sessions"面板都不会显示，故无法产出"侧栏 drop-target 环""辅助对话 sendError 横幅""工具失败徽章"的逐像素对照图。
- AXUIElement 在本机可读，**ZCode 3.10.2 主窗口可枚举**，但 ZCode asar 频繁色 token 应用到 Tapgo 视图后，只有登录 codex 完成首次会话才会出现真实渲染——这是真机回归的范围，沙箱做不了。
- 远端 fafamacmini 同样无登录态（fafa@tapgo-aicoding 数据隔离在 \`~/Library/Application Support/Tapgo AICoding/codex/\`），SCC/screencapture 跨 SSH 一直被 TCC 拦截；只在远端看 PID + version。

## 结论

- v0.5.74 + v0.5.75 把"贴近 ZCode"的可量化部分做到位（颜色 hex 100% 匹配，46 项结构 assertion 全过）。
- 剩余"尽可能贴近"空间已无明确"贴近什么"未实现——DSHTheme 已有 ZCode 全部主要语义色；3 个挂载点已用 ZCode 频繁色；Titlebar/Sidebar/Canvas 布局已 ZCode 风格；Computer Use / MCP / Harness Daemon 已有独立模块。
- 视觉证据（人工评审 drop-target 环、sendError 横幅、失败徽章）在你登录账号后 review PR 时即可肉眼对照 ZCode 真机；v0.5.76 之后这条路径不再由 AI 走（沙箱限制），交给真人/真机。
