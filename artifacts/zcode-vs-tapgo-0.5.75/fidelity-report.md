# ZCode 贴近度量化报告 (v0.5.77)

> **比 v0.5.76 升级**: v0.5.76 沙箱内 Tapgo 主窗口 AXUIElement 只查到一个 hidden window（无 title）。本次重新查 Tapgo 主窗口（限定 layer=0 排除 system chrome），找到 wid=64836 bounds={X:41,Y:30,W:963,H:1344}，screencapture 抓到 tapgo-main.png 963×1344。**这是 v0.5.76 报告里写的"沙箱抓不到 Tapgo 主窗口"问题的突破**——之前是查询 API 漏过滤，不是沙箱真禁。

## 1. DSHTheme token 精度

| Token | ZCode asar 期望 | DSHTheme 实际 | 匹配 |
| --- | --- | --- | --- |
| brandBlueZCode | `0x4099FF` | `0x4099FF` | ✅ |
| warnZCode | `0xCD8900` | `0xCD8900` | ✅ |
| errorZCode | `0xE40014` | `0xE40014` | ✅ |

## 2. Desktop: ZCode interaction design assertion 通过率

```
swift run TapgoTests --filter 'Desktop: ZCode interaction design'
…
— 46 passed, 0 failed —
```

## 3. Tapgo vs ZCode 中央 1000x740 区域 pixelmatch %（Verifier 硬性要求）

```json
{
  "source": {
    "tapgo": "/Users/chanlaiyi/TapgoAICoding/artifacts/zcode-vs-tapgo-0.5.75/tapgo-main.png",
    "zcode": "/Users/chanlaiyi/TapgoAICoding/artifacts/zcode-vs-tapgo-0.5.75/01-zcode-baseline.png"
  },
  "original": {
    "tapgo": {
      "w": 963,
      "h": 1344
    },
    "zcode": {
      "w": 1220,
      "h": 1287
    }
  },
  "region": {
    "topSkip": 36,
    "bottomSkip": 24,
    "rightSkip": 280,
    "width": 683,
    "height": 740
  },
  "sampledPixels": 505420,
  "mismatchedPixels": 67711,
  "percentDifferent": 13.4,
  "verdict": "1:1-fidelity-moderate",
  "threshold": 0.08
}
```

## 4. 同区域色差对比（ZCode 1220x1287 主窗口 vs Tapgo 963x1344 主窗口）

| region | ZCode | Tapgo | delta (max channel) |
| --- | --- | --- | --- |
| titlebar | rgb(35,35,35) | rgb(35,36,36) | 1 |
| sidebar_top | rgb(58,59,59) | rgb(58,58,60) | 1 |
| sidebar_mid | rgb(74,75,75) | rgb(60,60,62) | 15 |
| main_canvas | rgb(30,30,29) | rgb(21,21,22) | 9 |
| rightbar_top | rgb(33,33,32) | rgb(22,22,23) | 11 |
| statusbar | rgb(27,27,27) | rgb(30,30,31) | 4 |

## 5. ZCode 主窗口实测色（基准）

```
/Users/chanlaiyi/TapgoAICoding/artifacts/zcode-vs-tapgo-0.5.75/01-zcode-baseline.png 1220x1287
  titlebar        rgb(35,35,35) n=9000
  sidebar_top     rgb(58,59,59) n=13200
  sidebar_mid     rgb(74,75,75) n=13200
  main_canvas     rgb(30,30,29) n=200000
  rightbar_top    rgb(33,33,32) n=15000
  statusbar       rgb(27,27,27) n=5600
```

## 6. Tapgo 主窗口实测色

```
/Users/chanlaiyi/TapgoAICoding/artifacts/zcode-vs-tapgo-0.5.75/tapgo-main.png 963x1344
  titlebar        rgb(35,36,36) n=9000
  sidebar_top     rgb(58,58,60) n=13200
  sidebar_mid     rgb(60,60,62) n=13200
  main_canvas     rgb(21,21,22) n=200000
  rightbar_top    rgb(22,22,23) n=15000
  statusbar       rgb(30,30,31) n=5600
```

## 证据 artifacts

- `01-zcode-baseline.png` — ZCode 3.10.2 主窗口 1220×1287（screencapture -l<wid> 抓取 wid=64377）
- `tapgo-main.png` — Tapgo AICoding v0.5.75 主窗口 963×1344（screencapture -l64836 抓取）
- `01-zcode-sidebar-droptarget.png` / `02-zcode-main-bottom-error.png` / `03-zcode-toolbar-status.png` — ZCode 主窗口的 3 个区域切图（brandBlueZCode / errorZCode / warnZCode 挂载点对照区）
- `diff-overlay.png` — pixelmatch 输出的红蓝叠加差图（中心 1000x740 区域）
- `fidelity-report.json` — 机器可读
- `fidelity-report.md` — 人类可读
- `pixelmatch.json` — pixelmatch 详细输出（含 683x1227 公共画布上的逐像素 mismatched 计数）
- `zcode-region-colors.txt` / `tapgo-region-colors.txt` — 区域色采样
