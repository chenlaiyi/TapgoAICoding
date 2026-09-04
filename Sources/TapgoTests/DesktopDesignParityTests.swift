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
    let markdown = desktopDesignFile("Sources/TapgoAICoding/Views/MarkdownMessageView.swift")

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
    t.expect(chat.contains("ComposerView(contentWidth: wideContent ? 980 : 760)"), "desktop-design: 标准输入器与 Codex 消息列同宽")
    t.expect(!chat.contains("if hasConversation {\n                Divider()"), "desktop-design: 输入器上方没有贯穿会话区的分隔线")
    t.expect(message.contains("DSHTheme.surfaceRaised"), "desktop-design: 用户消息使用低对比灰色气泡")
    t.expect(theme.contains("sidebarBg") && theme.contains("titlebarBg"), "desktop-design: 桌面导航层级色完整")
    t.expect(content.contains("HSplitView") && content.contains("UnevenRoundedRectangle"), "desktop-design: 灰色整窗底板承载右侧圆角覆盖层")
    t.expect(content.contains("idealWidth: 292, maxWidth: 292"), "desktop-design: 侧栏默认宽度锁定 Codex 同视口比例")
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

    // Historical trajectory tokens remain available for other surfaces, but
    // Codex message-process rows must not use category colours.
    t.expect(theme.contains("trajectoryReasoning") && theme.contains("0x7C3AED") && theme.contains("0xA78BFA"),
             "desktop-design: 思考行 trajectoryReasoning 紫（light 0x7C3AED / dark 0xA78BFA）")
    t.expect(theme.contains("trajectoryToolCall") && theme.contains("0xD97706"),
             "desktop-design: 工具调用 trajectoryToolCall 琥珀")
    t.expect(theme.contains("trajectoryToolResult") && theme.contains("0x0284C7"),
             "desktop-design: 工具结果 trajectoryToolResult 天蓝")
    t.expect(message.contains("ProgressView()") && message.contains("display.isFailure ? DSHTheme.error : DSHTheme.labelDim")
             && !message.contains("trajectoryColor(for: display.kind)"),
             "desktop-design: Codex 工作过程使用中性文字与尾部进度环，仅失败着色")
    t.expect(!message.contains("runningTextShimmer")
             && !message.contains("DSHTheme.trajectoryReasoning")
             && !message.contains("toolCallAccent"),
             "desktop-design: 流式与工具过程无扫光和类别色")
    // v0.5.92 — current Codex Desktop reference capture locks the navigation,
    // selection and canvas planes. Source is recorded in design-qa.md.
    t.expect(theme.contains("fidelityTitlebar")    && theme.contains("0x171717"),
             "desktop-design: Codex 标题栏锁定 #171717")
    t.expect(theme.contains("fidelitySidebarTop")  && theme.contains("0x272728"),
             "desktop-design: Codex 侧栏锁定 #272728")
    t.expect(theme.contains("fidelitySidebarMid")  && theme.contains("0x303031"),
             "desktop-design: Codex 侧栏控件锁定 #303031")
    t.expect(theme.contains("fidelityMainCanvas")  && theme.contains("0x171717"),
             "desktop-design: Codex 消息画布锁定 #171717")
    t.expect(theme.contains("sidebarSelection") && theme.contains("0x383839"),
             "desktop-design: Codex 任务选中态保持低对比")
    // v0.5.87 — fidelity patch 3/3: main_canvas / rightbar_top 切到 DSHTheme.fidelityMainCanvas / fidelityRightbarTop
    t.expect(chat.contains("DSHTheme.fidelityMainCanvas"),
             "desktop-design: ChatView 主体背景切到 fidelityMainCanvas token")
    t.expect(workbench.contains("DSHTheme.fidelityRightbarTop"),
             "desktop-design: RightWorkbenchView 外层 + 顶栏背景切到 fidelityRightbarTop token (>=2 处)")
    // Message canvas follows the current Codex Desktop evidence:
    // user = quiet raised bubble, assistant = unadorned markdown on canvas.
    t.expect(sidebar.contains("DSHTheme.fidelitySidebarMid"),
             "desktop-design: SidebarView 视图模式切换器背景切到 fidelitySidebarMid token (closes sidebar_mid -15/255)")
    t.expect(!message.contains(".fill(DSHTheme.trajectoryUser"),
             "desktop-design: 用户消息不再叠加角色色条")
    t.expect(!message.contains(".fill(DSHTheme.trajectoryAssistant"),
             "desktop-design: 助手正文无色条与外层卡片")
    t.expect(message.contains("MarkdownMessageView(text, isStreaming: isStreaming)"),
             "desktop-design: 流式状态由正文内轻量光标承担")
    t.expect(!chat.contains("Text(turnTime(turn.startedAt))") && chat.contains("turnMetadataHelp(turn)"),
             "desktop-design: 完成态页脚只显示图标，时间与 token 收入 tooltip")
    t.expect(chat.contains("Image(systemName: \"arrow.turn.up.right\")")
             && !chat.contains("Label(\"以此输入开新任务\", systemImage:"),
             "desktop-design: 新任务动作使用 Codex 式图标，不常驻长标签")
    t.expect(chat.contains("Text(\"已处理 \\(localizedWorkDuration(turn.duration))\")"),
             "desktop-design: 完成过程使用 Codex 的已处理时长文案")
    t.expect(chat.contains("FileEditBatchView(files: fileChanges)"),
             "desktop-design: 完成态保留独立文件变更摘要卡")
    t.expect(fileChangeView.contains("@State private var selectedReviewPath: String?")
             && fileChangeView.contains("selectedReviewPath == nil ? \"审核\" : \"收起\"")
             && fileChangeView.contains("DiffView(change: file)"),
             "desktop-design: 文件结果卡默认收起并提供真实差异审核")
    t.expect(chat.contains(".background(DSHTheme.brandPrimary, in: Circle())")
             && chat.contains("currentPermission.id == PermissionChoice.full.id")
             && chat.contains("minHeight: 38"),
             "desktop-design: composer 使用紧凑输入高度、圆形主动作与纯文本权限状态")
    t.expect(markdown.contains("inlineSegments(_ text: String)")
             && markdown.contains("MarkdownMessageView.inlineSegments(i < row.count ? row[i] : \"\")"),
             "desktop-design: 表格单元格渲染行内 Markdown 而非暴露标记源码")
    t.expect(!markdown.contains(".background(idx % 2 == 1")
             && markdown.contains(".overlay(alignment: .top) { Divider() }"),
             "desktop-design: 表格改为 Codex 式平面分隔，不再使用连续卡片底色")
    // v0.5.93 — user-provided Codex/Tapgo crops exposed message-renderer
    // drift that shell/layout parity alone could not catch.
    t.expect(markdown.contains("VStack(alignment: .leading, spacing: 8)")
             && markdown.contains("appendText(text, to: &out, accumulator: &acc)")
             && markdown.contains("trimmingCharacters(in: .newlines)"),
             "desktop-design: Markdown 空行归一化且块间距收紧为 Codex 节奏")
    t.expect(markdown.contains("AppFont.pointSize(for: .body, multiplier: appFontScale.multiplier)")
             && !markdown.contains("multiplier: appFontScale.multiplier) + 0.5")
             && markdown.contains("foregroundStyle(DSHTheme.messageText)"),
             "desktop-design: 正文使用 Codex 密度字号与高对比文字")
    t.expect(chat.contains(".frame(maxWidth: wideContent ? 980 : 760")
             && chat.contains(".padding(.horizontal, 12)"),
             "desktop-design: 标准消息列为 760pt 且内边距 12pt")
    t.expect(fileChangeView.contains("ForEach(Array(visibleFiles.enumerated())")
             && fileChangeView.contains("再显示 \\(files.count - Self.foldThreshold) 个文件")
             && fileChangeView.contains("lineDelta(for: file)"),
             "desktop-design: 多文件结果卡默认展示三行路径和右对齐增删统计")
    t.expect(theme.contains("fileChangeCardBg") && theme.contains("0x222222")
             && theme.contains("fileChangeRowBg") && theme.contains("0x1A1A1A"),
             "desktop-design: 文件结果卡使用 Codex 实测深色层级")
    // v0.5.89 — ⌘\\ sidebar toggle + command palette 接入
    t.expect(content.contains("tapgoToggleSidebar") && content.contains("切换侧边栏"),
             "desktop-design: ContentView 接入 ⌘\\ 侧边栏切换（notification 模式 + command palette 双入口）")
    t.expect(app.contains("keyboardShortcut(\"\\\\\"") && app.contains("tapgoToggleSidebar"),
             "desktop-design: App.swift 菜单层声明 ⌘\\ 切换侧边栏")
    // v0.5.86 — fidelity patch 2/2: 视图 .background 切到 DSHTheme.fidelityTitlebar
    t.expect(chat.contains("DSHTheme.fidelityTitlebar"),
             "desktop-design: ChatView composer 工具栏背景切到 fidelityTitlebar token")
    t.expect(sidebar.contains("DSHTheme.fidelityTitlebar"),
             "desktop-design: SidebarView 底栏背景切到 fidelityTitlebar token")
    t.expect(workbench.contains("DSHTheme.fidelityTitlebar"),
             "desktop-design: RightWorkbenchView 工具栏背景切到 fidelityTitlebar token")
}
