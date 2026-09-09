# Tapgo AICoding 0.5.200

## + 菜单二次对齐 Codex 桌面端 + 失败语义修正

### + 菜单单行紧凑布局（对照 Codex 真机截图）

- 行布局从「标题+副标题双行大卡片」改为 Codex 同款**单行紧凑行**：图标 + 标题 + 同行内联副标题（caption secondary，超长截断）。
- 行序对齐 Codex：文件和文件夹 → 附加 Tapgo AICoding → 目标 → 计划模式 → 录制技能（之前计划模式在最前）。
- 无副标题的行（文件和文件夹 / 附加 / 录制技能）只显示标题；目标 / 计划模式用内联副标题表达状态（如「已开启：下一条消息只给方案不执行工具」）。
- 抑制首行系统焦点蓝框（focusable(false)），面板高度按行数自适应。

### 「未完成」→「失败」

- 消息流命令/工具折叠行的「执行命令 · 未完成」改为「执行命令 · **失败**」：这些行都是已跑完但失败的命令，之前文案像「还在跑」，语义误导。
- 侧栏失败角标的辅助功能文案同步改为「失败」。轮次级「处理未完成」（整轮没跑完）保持不变。

## 改动

- `Sources/TapgoAICoding/Views/ChatView.swift`：composerAddMenuRow 单行化 + 行序 + focusable + 面板高度估算
- `Sources/TapgoCore/ConversationPresentation.swift`：activityTitle 失败后缀
- `Sources/TapgoAICoding/Views/SidebarComponents.swift`：failed 角标 accessibilityLabel
- `Sources/TapgoTests/ConversationPresentationTests.swift`：断言同步
- `AppBuilder/*`：bump 0.5.200

## 测试

`swift run TapgoTests` 全量回归 + App 构建启动验证 + 三机安装回读。
