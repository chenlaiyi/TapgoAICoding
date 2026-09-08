# Tapgo AICoding 0.5.164

## SidebarTaskLabel 选中时加左侧 accent border 提示

之前 sidebar 选中项只靠背景色区分（dark mode `sidebarSelection` 0x383839 vs `sidebarHover` 0x303032 颜色相近），不够明显。加左侧 3pt accent-color border 提示。

- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 选中时（`.overlay(alignment: .leading)`）加 `Color.accentColor` 3pt 圆角矩形（垂直 padding 4pt，水平 2pt）。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
