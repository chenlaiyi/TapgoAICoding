import SwiftUI
import TapgoCore

@main
struct TapgoAICodingApp: App {
    @StateObject private var updater = AppUpdateController()
    @StateObject private var workspace = WorkspaceStore()
    @StateObject private var threadStore: ThreadStore
    @StateObject private var store: SessionStore
    @StateObject private var remote: PhoneRemoteController
    @StateObject private var authStore: AdminAuthStore
    @StateObject private var scheduledBridge: ScheduledTaskBridge
    @AppStorage(TapgoConfig.appearanceKey) private var appearance = "system"
    @AppStorage(AppFontScale.userDefaultsKey) private var fontScaleRaw = "medium"
    private let forceAdminLoginPreview = ProcessInfo.processInfo.environment["TAPGO_ADMIN_LOGIN_PREVIEW"] == "1"

    init() {
        TapgoConfig.migratePersistedSettings()
        let workspace = WorkspaceStore()
        let threads = ThreadStore()
        _workspace = StateObject(wrappedValue: workspace)
        _threadStore = StateObject(wrappedValue: threads)
        let sessionStore = SessionStore(workspace: workspace, threads: threads)
        _store = StateObject(wrappedValue: sessionStore)
        // 扫码即开 H5 的移动端远程控制 (v0.5.16)。登录成功后在 body 的
        // .task 里 startIfNeeded()。
        _remote = StateObject(wrappedValue: PhoneRemoteController(store: sessionStore, workspace: workspace))
        _authStore = StateObject(wrappedValue: AdminAuthStore())
        _scheduledBridge = StateObject(wrappedValue: ScheduledTaskBridge())
        // Global hotkey monitor: 让命令面板的 11 个 action 快捷键
        // 在 dock 关闭时也能触发（SwiftUI keyboardShortcut 仅在 view focus
        // 时工作；NSEvent.addLocalMonitorForEvents 是 macOS app 范围的）。
        installGlobalHotkeyMonitor()
        // 监听命令面板开关 → 更新 PaletteState.isOpen，让 NSEvent 监听器决定是否消费
        NotificationCenter.default.addObserver(forName: .tapgoPaletteDidOpen, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PaletteState.isOpen = true }
        }
        NotificationCenter.default.addObserver(forName: .tapgoPaletteDidClose, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PaletteState.isOpen = false }
        }
        // Cross-device durable memory: pull any newer memory files from the
        // iCloud Drive mirror at startup so the user sees what they wrote on
        // their other Macs (JKmacmini / fafamacmini / laptop). Detached so a
        // slow filesystem never blocks the App init path.
        Task.detached(priority: .utility) {
            TapgoConfig.syncMemoryPullAll()
        }
        // 电脑控制 MCP server: 按设置总开关同步隔离 Codex home。
        // 开启时幂等注册，关闭时移除；新 harness/会话读取最新状态。
        // 文件 I/O 放 detached，避免阻塞启动。
        Task.detached(priority: .utility) {
            TapgoConfig.syncComputerUseMCPPreference()
        }
        // Run a deterministic Phase 2 consolidation pass on each memory
        // layer to dedup / enforce the per-file byte cap. Idempotent.
        Task.detached(priority: .utility) {
            await MemoryConsolidator.consolidate(url: TapgoConfig.userMemoryURL)
            await MemoryConsolidator.consolidate(url: TapgoConfig.globalMemoryURL)
        }
    }

    /// Wire the ScheduledTaskBridge to the SessionStore once both exist,
    /// and start the 60-second polling loop. Idempotent.
    @State private var didWireScheduledBridge = false
    private func wireScheduledBridgeOnce() {
        if didWireScheduledBridge { scheduledBridge.refresh(); return }
        didWireScheduledBridge = true
        scheduledBridge.inject = { [store] task in
            if let tid = task.targetThreadId {
                let ok = store.sendUserMessage(task.prompt, toThreadID: tid.uuidString)
                if !ok {
                    throw ScheduledTaskError.threadMissing(tid)
                }
            } else {
                store.newThread()
                store.sendUserMessage(task.prompt)
            }
        }
        scheduledBridge.start()
    }

    /// Resolve the pinned appearance (system / light / dark) from settings.
    private var resolvedFontScale: AppFontScale {
        AppFontScale(rawValue: fontScaleRaw) ?? .medium
    }

    private var resolvedScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authStore.isAuthenticated && !forceAdminLoginPreview {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(workspace)
                        .environmentObject(remote)
                        .environmentObject(updater)
                        .task { remote.startIfNeeded() }
                } else {
                    AdminLoginView(onComplete: {})
                        .task { await authStore.bootstrap() }
                }
            }
            .environmentObject(authStore)
                    .environmentObject(scheduledBridge)
                    .onAppear { wireScheduledBridgeOnce() }
            .preferredColorScheme(resolvedScheme)
            .appFontScale(resolvedFontScale)
            .frame(minWidth: 920, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 780)
        // ZCode paints its own split background all the way through the
        // traffic-light/titlebar area: the left navigation remains gray and
        // the right workspace remains the dark overlay.  A hidden native
        // titlebar lets our HSplitView own that full-height surface while the
        // toolbar controls and traffic lights stay available above it.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.newThreadCommand) { store.newThread() }
                    .keyboardShortcut("n", modifiers: [.command])
                Divider()
                Button(L10n.openLocalFolder) {
                    NotificationCenter.default.post(name: .tapgoRequestOpenLocalFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
                Button("新任务 (选目录)") {
                    NotificationCenter.default.post(name: .tapgoRequestOpenNewTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("打开项目目录") {
                    NotificationCenter.default.post(name: .tapgoOpenActiveProject, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(L10n.openSettings) {
                    NotificationCenter.default.post(name: .tapgoRequestOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandGroup(after: .windowList) {
                Button("切换侧边栏") {
                    NotificationCenter.default.post(name: .tapgoToggleSidebar, object: nil)
                }
                .keyboardShortcut("\\", modifiers: [.command])
                Button("检查更新…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                Divider()
                Button("切换侧边工作台") {
                    NotificationCenter.default.post(name: .tapgoToggleTrajectory, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("进入自进化会话") {
                    NotificationCenter.default.post(name: .tapgoOpenEvolution, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                Button("聚焦会话搜索") {
                    NotificationCenter.default.post(name: .tapgoFocusSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button("聚焦输入框") {
                    NotificationCenter.default.post(name: .tapgoFocusComposer, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("复制会话为 Markdown") {
                    NotificationCenter.default.post(name: .tapgoCopyConversation, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("上一个会话") {
                    NotificationCenter.default.post(name: .tapgoSelectPrevThread, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("下一个会话") {
                    NotificationCenter.default.post(name: .tapgoSelectNextThread, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                Button("在对话中查找") {
                    NotificationCenter.default.post(name: .tapgoFindInConversation, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("命令面板") {
                    NotificationCenter.default.post(name: .tapgoOpenCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("切换外观") {
                    let next: String
                    switch appearance {
                    case "dark": next = "light"
                    case "light": next = "system"
                    default: next = "dark"
                    }
                    appearance = next
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("发送消息") {
                    NotificationCenter.default.post(name: .tapgoInterjectAndFlush, object: nil)
                }
                .keyboardShortcut(KeyEquivalent("\r"), modifiers: [.command])
                Button("中断当前任务") {
                    store.cancelActiveTurn()
                }
                .keyboardShortcut(".", modifiers: [.command])
                Button("清空输入") {
                    NotificationCenter.default.post(name: .tapgoClearComposer, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                Button("重试上一回合") {
                    NotificationCenter.default.post(name: .tapgoRetryTurn, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let tapgoRequestOpenLocalFolder = Notification.Name("tapgo.openLocalFolder")
    static let tapgoRequestOpenSettings = Notification.Name("tapgo.openSettings")
    static let tapgoToggleTrajectory = Notification.Name("tapgo.toggleTrajectory")
    static let tapgoOpenWorkbenchTab = Notification.Name("tapgo.openWorkbenchTab")
    static let tapgoFocusSearch = Notification.Name("tapgo.focusSearch")
    static let tapgoFocusComposer = Notification.Name("tapgo.focusComposer")
    static let tapgoCopyConversation = Notification.Name("tapgo.copyConversation")
    static let tapgoSendMessage = Notification.Name("tapgo.sendMessage")
    static let tapgoInterjectAndFlush = Notification.Name("tapgo.interjectAndFlush")
    static let tapgoJumpToTurn = Notification.Name("tapgo.jumpToTurn")
    static let tapgoOpenGoalEditor = Notification.Name("tapgo.openGoalEditor")
    static let tapgoAddFiles = Notification.Name("tapgo.addFiles")
    static let tapgoAttachTapgo = Notification.Name("tapgo.attachTapgo")
    static let tapgoTogglePlanMode = Notification.Name("tapgo.togglePlanMode")
    static let tapgoOpenCommandPalette = Notification.Name("tapgo.openCommandPalette")
    static let tapgoToggleSidebar = Notification.Name("tapgo.toggleSidebar")
    static let tapgoRequestOpenNewTask = Notification.Name("tapgo.openNewTask")
    static let tapgoRetryTurn = Notification.Name("tapgo.retryTurn")
    static let tapgoClearComposer = Notification.Name("tapgo.clearComposer")
    static let tapgoFindInConversation = Notification.Name("tapgo.findInConversation")
    static let tapgoRequestScrollToBottom = Notification.Name("tapgo.requestScrollToBottom")
    static let tapgoInsertSkill = Notification.Name("tapgo.insertSkill")
    static let tapgoInsertStarter = Notification.Name("tapgo.insertStarter")
    static let tapgoChooseStarterProject = Notification.Name("tapgo.chooseStarterProject")
    static let tapgoRequestProjectPicker = Notification.Name("tapgo.requestProjectPicker")
    static let tapgoSelectPrevThread = Notification.Name("tapgo.selectPrevThread")
    static let tapgoSelectNextThread = Notification.Name("tapgo.selectNextThread")
    static let tapgoOpenActiveProject = Notification.Name("tapgo.openActiveProject")
    static let tapgoOpenEvolution = Notification.Name("tapgo.openEvolution")
}

/// 命令面板开关状态：让 NSEvent 监听器在 dock 打开时不消费事件，
/// 让 dock 内的 keyboardShortcut 正常处理 ↩ 选。
@MainActor
enum PaletteState {
    static var isOpen: Bool = false
}

// MARK: - 全局 hotkey monitor

/// 命令面板 11 个 action 的快捷键在 dock 关闭时也能触发。每个条目
/// 优先被自己 view 内的 keyboardShortcut 拦截（如果 dock 开着），否则
/// 走本 monitor post 对应 NotificationName 触发。
private func installGlobalHotkeyMonitor() {
    // 键码 + modifierFlags → NotificationName 映射。modifierFlags 包含 cmd
    // (1<<8)、shift (1<<9)、option (1<<11)、control (1<<12)。
    // 格式：[(keyCode, flags, Notification.Name)]
    let bindings: [(keyCode: UInt16, flags: NSEvent.ModifierFlags, name: Notification.Name)] = [
        // 环境
        (46, [.command, .control], .tapgoMcpStatus),  // ⌃⌘M MCP（先占位，下面加）
        (15, [.command, .control], .tapgoReviewThreadEmpty),  // ⌃⌘R 代码审查
        (1, [.command, .control, .option], .tapgoSideChat),  // ⌃⌥S 侧边
        (11, [.command, .control], .tapgoCreateBranchEmpty),  // ⌃⌘B 创建聊天分支
        (40, [.command, .control], .tapgoCompactEmpty),  // ⌃⌘K 压缩
        (3, [.command, .option], .tapgoFeedback),  // ⌥⌘F 反馈
        (51, [.command, .option], .tapgoArchiveEmpty),  // ⌥⌘⌫ 归档
        (34, [.command, .control], .tapgoStatusEmpty),  // ⌃⌘I 状态
        (35, [.command, .control], .tapgoTogglePlanMode),  // ⌃⌘P 计划模式
        (35, [.command, .option], .tapgoPinEmpty),  // ⌥⌘P 置顶
        (15, [.command, .shift], .tapgoOpenReleaseNotes),  // ⇧⌘R 更新日志
        (44, [.shift], .tapgoShowShortcutsGlobal),  // ⇧? 快捷键（问号需要 shift+/）
        // 触发 dock 自身
        (40, [.command], .tapgoOpenCommandPalette),  // ⌘K 关闭 dock
        (5, [.command, .shift], .tapgoOpenCommandPalette),  // ⌘⇧P 打开 dock
    ]
    let map: [String: Notification.Name] = Dictionary(uniqueKeysWithValues:
        bindings.map { (key: "\($0.keyCode):\($0.flags.rawValue)", value: $0.name) }
    )
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        let key = "\(event.keyCode):\(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)"
        if let name = map[key] {
            // dock 开着时不消费事件，让 dock 内的 keyboardShortcut 正常处理 ↩ 选
            if MainActor.assumeIsolated({ PaletteState.isOpen }) {
                return event
            }
            NotificationCenter.default.post(name: name, object: nil)
            return nil  // 消费事件
        }
        return event
    }
}

extension Notification.Name {
    static let tapgoMcpStatus = Notification.Name("tapgo.mcpStatus")
    static let tapgoReviewThreadEmpty = Notification.Name("tapgo.reviewThreadEmpty")
    static let tapgoSideChat = Notification.Name("tapgo.sideChat")
    static let tapgoCreateBranchEmpty = Notification.Name("tapgo.createBranchEmpty")
    static let tapgoCompactEmpty = Notification.Name("tapgo.compactEmpty")
    static let tapgoFeedback = Notification.Name("tapgo.feedback")
    static let tapgoArchiveEmpty = Notification.Name("tapgo.archiveEmpty")
    static let tapgoStatusEmpty = Notification.Name("tapgo.statusEmpty")
    static let tapgoPinEmpty = Notification.Name("tapgo.pinEmpty")
    static let tapgoOpenReleaseNotes = Notification.Name("tapgo.openReleaseNotes")
    static let tapgoShowShortcutsGlobal = Notification.Name("tapgo.showShortcutsGlobal")
    static let tapgoPaletteDidOpen = Notification.Name("tapgo.paletteDidOpen")
    static let tapgoPaletteDidClose = Notification.Name("tapgo.paletteDidClose")
}
