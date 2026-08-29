import SwiftUI
import TapgoCore

@main
struct TapgoAICodingApp: App {
    @StateObject private var workspace = WorkspaceStore()
    @StateObject private var threadStore: ThreadStore
    @StateObject private var store: SessionStore
    @StateObject private var remote: PhoneRemoteController
    @StateObject private var authStore: AdminAuthStore
    @AppStorage(TapgoConfig.appearanceKey) private var appearance = "system"
    @AppStorage(AppFontScale.userDefaultsKey) private var fontScaleRaw = "medium"

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
        _remote = StateObject(wrappedValue: PhoneRemoteController(store: sessionStore))
        _authStore = StateObject(wrappedValue: AdminAuthStore())
        // Cross-device durable memory: pull any newer memory files from the
        // iCloud Drive mirror at startup so the user sees what they wrote on
        // their other Macs (JKmacmini / fafamacmini / laptop). Detached so a
        // slow filesystem never blocks the App init path.
        Task.detached(priority: .utility) {
            TapgoConfig.syncMemoryPullAll()
        }
        // Run a deterministic Phase 2 consolidation pass on each memory
        // layer to dedup / enforce the per-file byte cap. Idempotent.
        Task.detached(priority: .utility) {
            await MemoryConsolidator.consolidate(url: TapgoConfig.userMemoryURL)
            await MemoryConsolidator.consolidate(url: TapgoConfig.globalMemoryURL)
        }
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
                if authStore.isAuthenticated {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(workspace)
                        .environmentObject(remote)
                        .task { remote.startIfNeeded() }
                } else {
                    AdminLoginView(onComplete: {})
                        .task { await authStore.bootstrap() }
                }
            }
            .environmentObject(authStore)
            .preferredColorScheme(resolvedScheme)
            .appFontScale(resolvedFontScale)
            .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 860)
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
                Button("切换轨迹栏") {
                    NotificationCenter.default.post(name: .tapgoToggleTrajectory, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
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
    static let tapgoFocusSearch = Notification.Name("tapgo.focusSearch")
    static let tapgoFocusComposer = Notification.Name("tapgo.focusComposer")
    static let tapgoCopyConversation = Notification.Name("tapgo.copyConversation")
    static let tapgoSendMessage = Notification.Name("tapgo.sendMessage")
    static let tapgoInterjectAndFlush = Notification.Name("tapgo.interjectAndFlush")
    static let tapgoJumpToTurn = Notification.Name("tapgo.jumpToTurn")
    static let tapgoOpenCommandPalette = Notification.Name("tapgo.openCommandPalette")
    static let tapgoRequestOpenNewTask = Notification.Name("tapgo.openNewTask")
    static let tapgoRetryTurn = Notification.Name("tapgo.retryTurn")
    static let tapgoClearComposer = Notification.Name("tapgo.clearComposer")
    static let tapgoFindInConversation = Notification.Name("tapgo.findInConversation")
    static let tapgoRequestScrollToBottom = Notification.Name("tapgo.requestScrollToBottom")
    static let tapgoInsertSkill = Notification.Name("tapgo.insertSkill")
    static let tapgoSelectPrevThread = Notification.Name("tapgo.selectPrevThread")
    static let tapgoSelectNextThread = Notification.Name("tapgo.selectNextThread")
    static let tapgoOpenActiveProject = Notification.Name("tapgo.openActiveProject")
}
