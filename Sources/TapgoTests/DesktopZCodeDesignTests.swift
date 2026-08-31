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

    t.expect(sidebar.contains("menuItem(\"新建任务\""), "desktop-design: 新建任务位于一级导航")
    t.expect(sidebar.contains("menuItem(\"搜索\""), "desktop-design: 搜索位于一级导航")
    t.expect(sidebar.contains("menuItem(\"自动化\""), "desktop-design: 自动化位于一级导航")
    t.expect(sidebar.contains("menuItem(\"插件市场\""), "desktop-design: 插件市场位于一级导航")
    t.expect(sidebar.contains("case groups") && sidebar.contains("case projects"), "desktop-design: 分组与项目视图可切换")
    t.expect(sidebar.contains("relativeDate(for: t.updatedAt)"), "desktop-design: 任务行显示相对日期")
    t.expect(sidebar.contains("showConnectPhone = true"), "desktop-design: 连接手机入口保留")
    t.expect(sidebar.contains("updater.checkForUpdates()"), "desktop-design: 更新入口保留")
    t.expect(chat.contains("threadHeader(thread: thread)"), "desktop-design: 独立任务顶栏")
    t.expect(chat.contains("NotificationCenter.default.post(name: .tapgoToggleTrajectory"), "desktop-design: 轨迹栏切换可用")
    t.expect(chat.contains("activeThread == nil, let p = workspace.state.activeProject"), "desktop-design: 活跃任务输入器不重复项目入口")
    t.expect(message.contains("DSHTheme.surfaceRaised"), "desktop-design: 用户消息使用低对比灰色气泡")
    t.expect(theme.contains("sidebarBg") && theme.contains("titlebarBg"), "desktop-design: 桌面导航层级色完整")
    t.expect(app.contains("windowToolbarStyle(.unifiedCompact)"), "desktop-design: 紧凑统一标题栏")
}
