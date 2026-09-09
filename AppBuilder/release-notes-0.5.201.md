# Tapgo AICoding 0.5.201

## + 菜单改为输入框正上方同宽 banner（对齐 Codex 桌面端）

- 弃用 NSPopover 自动定位（错位、贴边、点外部关闭后状态失步），改为 SwiftUI overlay：面板与 composer 卡片**同宽、左右边缘对齐、贴上沿 6pt**，就是输入框上面的 banner。
- 面板出现时点击面板外任意区域关闭（含消息流区域）；开合带 150ms 淡入动画。
- 修复：面板行图标贴左边缘被裁 — 行内容增加 12pt 水平内边距。
- 插件行图标按品牌着色（GitHub 白 / Cloudflare 橙 / Figma 紫 / Gmail 红 / Slack 蓝紫），对齐 Codex 彩色品牌图标。
- 移除 TapgoCore/PopoverPanel.swift（不再使用）。

## 测试

全量回归 + 构建/启动 + 本机自动化 UI 验证（AXPress 开面板截图比对）+ 三机安装回读。
