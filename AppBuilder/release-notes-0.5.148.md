# Tapgo AICoding 0.5.148

## Composer placeholder 文案对齐 Codex 桌面端

- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `composerPlaceholder` 默认文案 `"随心输入"` → `"发消息 / 添加文件 / @ 插件"`。
  - 理由：Codex 桌面端 placeholder 是 "添加文件等内容 @ 人/项目" 提示 composer 能做什么。TapgoAICoding 不支持 @ 人/@ 项目 reference（仅支持 v0.5.147 接通的 @ 插件），所以 hint 改成"发消息 / 添加文件 / @ 插件"，更贴近实际能力。
  - 自进化会话仍走特殊文案 `"向自进化下达本轮指令…"` 不变（v0.5.33 用户实测踩坑后加的覆盖逻辑）。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
