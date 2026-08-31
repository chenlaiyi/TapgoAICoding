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

    t.expect(sidebar.contains("menuItem(\"新建任务\""), "desktop-design: 新建任务位于一级导航")
    t.expect(sidebar.contains("menuItem(\"搜索\""), "desktop-design: 搜索位于一级导航")
    t.expect(sidebar.contains("menuItem(\"自动化\""), "desktop-design: 自动化位于一级导航")
    t.expect(sidebar.contains("menuItem(\"插件市场\""), "desktop-design: 插件市场位于一级导航")
    t.expect(sidebar.contains("case groups") && sidebar.contains("case projects"), "desktop-design: 分组与项目视图可切换")
    t.expect(sidebar.contains("flattenedThreads") && sidebar.contains("flatTaskThreads"), "desktop-design: 分组扁平列表与项目层级分别渲染")
    t.expect(sidebar.contains("sidebarSectionHeading(\"项目\"") && sidebar.contains("sidebarSectionHeading(\"任务\""), "desktop-design: 项目模式具有项目与任务双分区")
    t.expect(sidebar.contains("ScrollView") && sidebar.contains("LazyVStack"), "desktop-design: 侧栏使用无系统玻璃材质的平面滚动容器")
    t.expect(sidebar.contains("relativeDate(for: t.updatedAt)"), "desktop-design: 任务行显示相对日期")
    t.expect(sidebar.contains("showConnectPhone = true"), "desktop-design: 连接手机入口保留")
    t.expect(sidebar.contains("updater.checkForUpdates()"), "desktop-design: 更新入口保留")
    t.expect(chat.contains("threadHeader(thread: thread)"), "desktop-design: 独立任务顶栏")
    t.expect(chat.contains("NotificationCenter.default.post(name: .tapgoToggleTrajectory"), "desktop-design: 轨迹栏切换可用")
    t.expect(chat.contains("activeThread == nil, let p = workspace.state.activeProject"), "desktop-design: 活跃任务输入器不重复项目入口")
    t.expect(chat.contains("ComposerView(contentWidth: wideContent ? 980 : 800)"), "desktop-design: 输入器宽度对齐 ZCode 桌面端")
    t.expect(!chat.contains("if hasConversation {\n                Divider()"), "desktop-design: 输入器上方没有贯穿会话区的分隔线")
    t.expect(message.contains("DSHTheme.surfaceRaised"), "desktop-design: 用户消息使用低对比灰色气泡")
    t.expect(theme.contains("sidebarBg") && theme.contains("titlebarBg"), "desktop-design: 桌面导航层级色完整")
    t.expect(content.contains("HSplitView") && content.contains("UnevenRoundedRectangle"), "desktop-design: 灰色整窗底板承载右侧圆角覆盖层")
    t.expect(content.contains("ignoresSafeArea(.container, edges: .top)"), "desktop-design: 右侧覆盖层贯穿标题栏顶部")
    t.expect(content.contains("let showAdaptiveEnvironment = false"), "desktop-design: 环境卡仅由用户主动打开，不挤压 ZCode 主画布")
    t.expect(content.contains("RightWorkbenchView") && content.contains("HSplitView"), "desktop-design: 右侧工作台是独立可拖拽分栏")
    t.expect(content.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"), "desktop-design: 打开工作台后主画布保持全窗口高度")
    t.expect(workbench.contains("搜索标签页") && workbench.contains("新增标签"), "desktop-design: 工作台具有 ZCode 标签检索和新增入口")
    t.expect(workbench.contains("WorkbenchReview") && workbench.contains("WorkbenchTerminal") && workbench.contains("WorkbenchBrowser"), "desktop-design: 审查终端浏览器均为真实工作台内容")
    t.expect(workbench.contains("向右拖动展开环境信息") && workbench.contains("workbench-environment-drawer"), "desktop-design: 右缘拖拽可展开环境信息")
    t.expect(workbench.contains("layout.isEnvironmentVisible ? 590 : 340") && workbench.contains("ensureHostWindowFitsEnvironment"), "desktop-design: 环境展开时窗口与两级右栏保持可读最小宽度")
    t.expect(workbench.contains("关闭其他标签") && workbench.contains("closePanel"), "desktop-design: 标签关闭与面板关闭是两级动作")
    t.expect(app.contains("windowStyle(.hiddenTitleBar)"), "desktop-design: 自绘分层背景贯穿窗口标题栏")
    t.expect(app.contains("windowToolbarStyle(.unifiedCompact)"), "desktop-design: 紧凑统一标题栏")
}
