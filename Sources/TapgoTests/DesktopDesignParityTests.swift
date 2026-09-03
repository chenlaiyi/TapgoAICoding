import Foundation

private func desktopDesignFile(_ relativePath: String) -> String {
    let root = FileManager.default.currentDirectoryPath
    return (try? String(contentsOfFile: root + "/" + relativePath, encoding: .utf8)) ?? ""
}

@MainActor
func runDesktopZCodeDesign(_ t: TestRunner) {
    let sidebar = desktopDesignFile("Sources/TapgoAICoding/Views/SidebarView.swift")
    let chat = desktopDesignFile("Sources/TapgoAICoding/Views/ChatView.swift")
    let message = desktopDesignFile("Sources/TapgoAICoding/Views/MessageRow.swift")
    let theme = desktopDesignFile("Sources/TapgoAICoding/Resources/DSHTheme.swift")
    let app = desktopDesignFile("Sources/TapgoAICoding/App.swift")
    let content = desktopDesignFile("Sources/TapgoAICoding/Views/ContentView.swift")
    let workbench = desktopDesignFile("Sources/TapgoAICoding/Views/RightWorkbenchView.swift")
    let fileChangeView = desktopDesignFile("Sources/TapgoAICoding/Views/FileChangeView.swift")

    t.expect(sidebar.contains("menuItem(\"新建任务\""), "desktop-design: 新建任务位于一级导航")
    t.expect(sidebar.contains("menuItem(\"搜索\""), "desktop-design: 搜索位于一级导航")
    t.expect(!sidebar.contains("menuItem(\"自进化日志\""), "desktop-design: 自进化日志不在一级导航")
    t.expect(sidebar.contains("menuItem(\"插件市场\""), "desktop-design: 插件市场位于一级导航")
    t.expect(sidebar.contains("case groups") && sidebar.contains("case projects"), "desktop-design: 分组与项目视图可切换")
    t.expect(sidebar.contains("flattenedThreads") && sidebar.contains("flatTaskThreads"), "desktop-design: 分组扁平列表与项目层级分别渲染")
    t.expect(sidebar.contains("sidebarSectionHeading(\"项目\"") && sidebar.contains("sidebarSectionHeading(\"任务\""), "desktop-design: 项目模式具有项目与任务双分区")
    t.expect(sidebar.contains("ScrollView") && sidebar.contains("LazyVStack"), "desktop-design: 侧栏使用无系统玻璃材质的平面滚动容器")
    t.expect(sidebar.contains("relativeDate(for: t.updatedAt)"), "desktop-design: 任务行显示相对日期")
    t.expect(sidebar.contains("showConnectPhone = true"), "desktop-design: 连接手机入口保留")
    t.expect(sidebar.contains("updater.checkForUpdates()"), "desktop-design: 更新入口保留")
    t.expect(sidebar.contains("Label(\"连接手机\""), "desktop-design: 连接手机收进账户菜单")
    t.expect(sidebar.contains("Label(\"自进化日志\""), "desktop-design: 自进化日志收进账户菜单")
    t.expect(!sidebar.contains("Label(\"检查更新\", systemImage"), "desktop-design: 账户菜单不再放检查更新项（改为昵称右侧常驻徽章）")
    t.expect(sidebar.contains("updateBadgeButton") && sidebar.contains("arrow.down.circle.fill") && sidebar.contains("arrow.up.circle"),
             "desktop-design: 昵称右侧常驻更新徽章（有新版蓝色实心 / 无新版灰色向上箭头）")
    t.expect(sidebar.contains("updater.updateFound"), "desktop-design: 徽章状态由 AppUpdateController.updateFound 驱动")
    // 徽章与 Menu 同处一个 HStack（头像/姓名/更新按钮同一行），而不是 VStack 里的独立一行
    t.expect(sidebar.contains("HStack(alignment: .center, spacing: 6) {\n            Menu {"),
             "desktop-design: 头像姓名与更新徽章同一行（Menu+徽章共 HStack）")
    t.expect(sidebar.contains("Label(\"设置\""), "desktop-design: 设置收进账户菜单")
    t.expect(!sidebar.contains(".help(\"连接手机与应用工具\""), "desktop-design: 底部工具菜单移除")
    t.expect(!sidebar.contains(".help(L10n.tooltipSettings)\n            .accessibilityLabel(L10n.tooltipSettings)"), "desktop-design: 底部设置按钮移除")
    t.expect(chat.contains("threadHeader(thread: thread)"), "desktop-design: 独立任务顶栏")
    t.expect(chat.contains("NotificationCenter.default.post(name: .tapgoToggleTrajectory"), "desktop-design: 轨迹栏切换可用")
    t.expect(chat.contains("activeThread == nil, let p = workspace.state.activeProject"), "desktop-design: 活跃任务输入器不重复项目入口")
    t.expect(chat.contains("ComposerView(contentWidth: wideContent ? 980 : 800)"), "desktop-design: 输入器宽度对齐 ZCode 桌面端")
    t.expect(!chat.contains("if hasConversation {\n                Divider()"), "desktop-design: 输入器上方没有贯穿会话区的分隔线")
    t.expect(message.contains("DSHTheme.surfaceRaised"), "desktop-design: 用户消息使用低对比灰色气泡")
    t.expect(theme.contains("sidebarBg") && theme.contains("titlebarBg"), "desktop-design: 桌面导航层级色完整")
    t.expect(content.contains("HSplitView") && content.contains("UnevenRoundedRectangle"), "desktop-design: 灰色整窗底板承载右侧圆角覆盖层")
    t.expect(content.contains("ignoresSafeArea(.container, edges: .top)"), "desktop-design: 右侧覆盖层贯穿标题栏顶部")
    t.expect(content.contains("AdaptiveEnvironmentLayout.shouldShow") && content.contains("manualDetailVisible: showTrajectory"), "desktop-design: 自适应环境卡在宽窗口自动出现且不与工作台共存")
    t.expect(content.contains("RightWorkbenchView") && content.contains("HSplitView"), "desktop-design: 右侧工作台是独立可拖拽分栏")
    t.expect(content.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"), "desktop-design: 打开工作台后主画布保持全窗口高度")
    t.expect(workbench.contains("搜索标签页") && workbench.contains("新增标签"), "desktop-design: 工作台具有 ZCode 标签检索和新增入口")
    t.expect(workbench.contains("WorkbenchReview") && workbench.contains("WorkbenchTerminal") && workbench.contains("WorkbenchBrowser"), "desktop-design: 审查终端浏览器均为真实工作台内容")
    t.expect(workbench.contains("向右拖动展开环境信息") && workbench.contains("workbench-environment-drawer"), "desktop-design: 右缘拖拽可展开环境信息")
    t.expect(workbench.contains("onTapGesture { layout.isEnvironmentVisible = true }") && workbench.contains("translation.width > 3"), "desktop-design: 贴边窗口下手柄点击或小位移拖拽都能展开环境信息")
    t.expect(workbench.contains("requestEnvironmentReveal") && content.contains("widenRevealThreshold"), "desktop-design: 分隔条拖宽工作台到阈值直接触发环境抽屉弹出（自绘分隔条手势）")
    t.expect(workbench.contains("layout.isEnvironmentVisible ? 590 : 340") && workbench.contains("ensureHostWindowFitsEnvironment"), "desktop-design: 环境展开时窗口与两级右栏保持可读最小宽度")
    t.expect(workbench.contains("关闭其他标签") && workbench.contains("closePanel"), "desktop-design: 标签关闭与面板关闭是两级动作")
    t.expect(app.contains("windowStyle(.hiddenTitleBar)"), "desktop-design: 自绘分层背景贯穿窗口标题栏")
    t.expect(app.contains("windowToolbarStyle(.unifiedCompact)"), "desktop-design: 紧凑统一标题栏")

    // v0.5.74 — ZCode asar baseline accents are tracked as named constants so
    // any drift in the upstream renderer is caught at test time. Frequencies
    // measured against /Applications/ZCode.app/Contents/Resources/app.asar's
    // compiled stylesheet (the most frequent non-trivial brand colour is
    // #4099ff at 28 hits; warning #cd8900 at 16 hits; danger #e40014 at 26).

    t.expect(theme.contains("brandBlueAccent") && theme.contains("0x4099FF"), "desktop-design: ZCode 频繁蓝 #4099ff 已固化为 brandBlueAccent")
    t.expect(theme.contains("warnAccent") && theme.contains("0xCD8900"), "desktop-design: ZCode 频繁警告色 #cd8900 已固化为 warnAccent")
    t.expect(theme.contains("errorAccent") && theme.contains("0xE40014"), "desktop-design: ZCode 频繁危险色 #e40014 已固化为 errorAccent")
    t.expect(theme.contains("sidebarBg") && theme.contains("titlebarBg") && theme.contains("brandBlueAccent"),
             "desktop-design: 桌面层 + ZCode 频繁色 token 全部就位")
    t.expect(app.contains("windowStyle(.hiddenTitleBar)") && app.contains("windowToolbarStyle(.unifiedCompact)"),
             "desktop-design: macOS 标题栏自绘 + 紧凑工具栏配置持久（v0.5.65 起的承诺，未被 v0.5.74 改动回退）")

    // v0.5.74 — ZCode asar 频繁色 token 真正挂到 UI 上
    t.expect(sidebar.contains("DSHTheme.brandBlueAccent") && sidebar.contains("stroke"),
             "desktop-design: 侧栏 drop-target 虚线环用 brandBlueAccent（取代 DSHTheme.brand）")
    t.expect(workbench.contains("DSHTheme.errorAccent") && workbench.contains("sendError"),
             "desktop-design: 辅助对话 sendError 用 errorAccent 高饱和红")
    t.expect(fileChangeView.contains("DSHTheme.warnAccent") && fileChangeView.contains("执行失败"),
             "desktop-design: 文件变更「执行失败」用 warnAccent 替代 .tertiary 灰")

    // v0.5.80 — ZCode 工作过程行按事件类型着色（--color-trajectory-*）
    t.expect(theme.contains("trajectoryReasoning") && theme.contains("0x7C3AED") && theme.contains("0xA78BFA"),
             "desktop-design: 思考行 trajectoryReasoning 紫（light 0x7C3AED / dark 0xA78BFA）")
    t.expect(theme.contains("trajectoryToolCall") && theme.contains("0xD97706"),
             "desktop-design: 工具调用 trajectoryToolCall 琥珀")
    t.expect(theme.contains("trajectoryToolResult") && theme.contains("0x0284C7"),
             "desktop-design: 工具结果 trajectoryToolResult 天蓝")
    t.expect(message.contains("trajectoryReasoning.opacity(0.8)") && message.contains("trajectoryColor(for: display.kind)"),
             "desktop-design: 思考行与汇总行按事件类型着色（80% 不透明度对齐上游）")
}
