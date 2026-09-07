# Tapgo AICoding 0.5.141

## Plan mode 深度集成（常驻模式 + Banner 关闭按钮）+ Composer + 菜单对齐 Codex 桌面端 + type-checker 超时修复

- `Sources/TapgoAICoding/Views/ChatView.swift`
  - **Composer "+" 菜单对齐 Codex 桌面端**：每个命令现在带"图标 + 标题 + 副标题描述"双行布局（截图对照：目标 / 计划模式 / 录制技能 等均补全描述；"附加 Tapgo AICoding"图标改为 `plus.app`；"录制技能"图标改为 `record.circle`，更贴近录音/录制语义）。
  - 抽出 `AddMenuItem` / `AddMenuAction` / `composerAddMenuRow` / `runAddMenuAction`，把菜单项配置和渲染分离。
  - 插件分组（5 项）从 `AgentCapabilities.skills` 切到本地静态 `addMenuPlugins`，便于未来直接换成 `PluginCatalogItem` 实时 Codex 插件目录。
  - **Plan mode 常驻模式**：`@AppStorage("tapgo.planModePersistent")`；开启后发送消息不再重置 `planningMode`，适合多轮规划。
  - `PlanModeBanner` 加 `isPersistent` / `onDismiss` 参数；右上角加 X 按钮；常驻模式时显示"Plan mode（常驻）"。
  - 拆出 `handleComposerAppear` / `handleComposerDisappear`，修 Swift type-checker 在 body 多语句闭包 + 大量 onReceive 上的 O(n²) 超时（之前 release build 卡 30+ 分钟，本次秒过）。
- `Sources/TapgoAICoding/App.swift`
  - 加 `Notification.Name.tapgoPlanModeBannerDidDismiss`，配合 `PlanModeBanner` 的 X 按钮。

测试：3117 passed / 12 failed（基线不变，12 项为 SSH 环境性问题）。开发者签名有效；尚未完成 Apple 公证。
