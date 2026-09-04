import SwiftUI
import TapgoCore
import AppKit

/// ZCode-style settings workspace: grouped navigation on the left and a
/// task-focused, scrollable settings page on the right.  Each control still
/// uses Tapgo AICoding's existing source of truth; the layout does not invent
/// switches for capabilities that the app cannot actually persist or apply.
struct SettingsView: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @EnvironmentObject var authStore: AdminAuthStore
    @Environment(\.dismiss) private var dismiss
    private let onDismiss: (() -> Void)?
    @State private var tab: Tab = .general
    @State private var addHostSheet = false
    @State private var testingHostId: String?
    @State private var testingOutput: String?
    @State private var memoryStatus: MemoryFileStatus?
    @State private var globalMemoryStatus: MemoryFileStatus?
    @State private var codexMemoryStatus: MemoryFileStatus?
    @State private var memoryCopyMessage: String?
    @State private var computerPermissionRefresh = 0
    @State private var computerPermissionState = ComputerUsePermissionState.loading
    @State private var computerUseMessage: String?

    @AppStorage(TapgoConfig.approvalPolicyKey) private var approvalPolicyRaw =
        TapgoConfig.ApprovalPolicy.never.rawValue
    @AppStorage(TapgoConfig.sandboxKey) private var sandboxRaw =
        TapgoConfig.SandboxMode.dangerFullAccess.rawValue
    @AppStorage("tapgo.baseURL") private var baseURL = ""
    @AppStorage(TapgoConfig.reasoningEffortKey) private var reasoningEffort = ""
    @AppStorage(TapgoConfig.selectedModelKey) private var selectedModelRaw =
        TapgoModel.minimaxM3.rawValue
    @State private var deleteCandidate: TapgoConfig.ResolvedModel?
    @AppStorage(TapgoConfig.appearanceKey) private var appearanceRaw = "system"
    @AppStorage(AppFontScale.userDefaultsKey) private var fontScaleRaw = "medium"
    @AppStorage(TapgoConfig.memoryEnabledKey) private var memoryEnabled = true
    @AppStorage(TapgoConfig.memoryReadEnabledKey) private var memoryReadEnabled = true
    @AppStorage(TapgoConfig.memoryWriteEnabledKey) private var memoryWriteEnabled = true
    @AppStorage("tapgo.memory.cloudSync") private var cloudSyncEnabled = true
    @AppStorage(TapgoConfig.computerUseEnabledKey) private var computerUseEnabled = true
    @AppStorage(TapgoConfig.computerUseShowInComposerKey) private var computerUseShowInComposer = true
    /// Global toggle for the ZCode-style "工作过程" work log (thinking,
    /// terminal, file edit, file read cards inside a turn). Default off —
    /// see `ChatView.showWorkProcess` for the matching flag. Kept here
    /// so users can flip it back on without digging through a hidden
    /// settings path.
    @AppStorage("tapgo.showWorkProcess") private var showWorkProcess = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    init(initialTab: Tab = .general, onDismiss: (() -> Void)? = nil) {
        _tab = State(initialValue: initialTab)
        self.onDismiss = onDismiss
    }

    enum Tab: String, CaseIterable, Identifiable {
        case general = "常规"
        case appearance = "外观"
        case model = "模型设置"
        case computer = "电脑控制"
        case memory = "记忆"
        case plugins = "插件"
        case account = "账户"
        case projects = "项目"
        case remote = "远程主机"
        case about = "关于"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .appearance: return "paintpalette"
            case .model: return "cube"
            case .computer: return "display"
            case .memory: return "brain.head.profile"
            case .plugins: return "puzzlepiece.extension"
            case .account: return "person.crop.circle"
            case .projects: return "folder"
            case .remote: return "network"
            case .about: return "info.circle"
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "审批、安全与 Agent 运行方式"
            case .appearance: return "主题、字号与实时预览"
            case .model: return "选择、添加并维护模型供应商"
            case .computer: return "工具注册与 macOS 权限状态"
            case .memory: return "跨会话记忆与跨设备同步"
            case .plugins: return "安装、启停与管理扩展能力"
            case .account: return "当前 Tapgo 登录身份"
            case .projects: return "本地工作区与项目列表"
            case .remote: return "SSH 开发主机与连接检测"
            case .about: return "版本、配置目录与诊断信息"
            }
        }
    }

    private struct NavigationSection: Identifiable {
        let title: String
        let tabs: [Tab]
        var id: String { title }
    }

    private let navigationSections = [
        NavigationSection(title: "基础设置", tabs: [.general, .appearance, .model, .computer]),
        NavigationSection(title: "工作区", tabs: [.projects, .remote]),
        NavigationSection(title: "Agent 能力", tabs: [.memory, .plugins]),
        NavigationSection(title: "账户与支持", tabs: [.account, .about]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 315)
            Divider()
            VStack(spacing: 0) {
                pageHeader
                Divider()
                pageContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSHTheme.bg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 1080, minHeight: 720)
        .background(DSHTheme.moduleBg)
        .sheet(isPresented: $addHostSheet) {
            AddRemoteHostSheet { host in
                workspace.addRemoteHost(host)
            }
        }
        .confirmationDialog(
            "删除模型 \(deleteCandidate?.displayName ?? "")？",
            isPresented: .init(get: { deleteCandidate != nil },
                               set: { if !$0 { deleteCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.delete, role: .destructive) {
                if let row = deleteCandidate { deleteModel(row) }
                deleteCandidate = nil
            }
            Button(L10n.cancel, role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("仅删除 App 内的模型配置，不影响上游账号。")
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { closeSettings() } label: {
                Label("返回工作区", systemImage: "chevron.left")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(navigationSections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                                .foregroundStyle(DSHTheme.labelTertiary)
                                .padding(.horizontal, 12)
                                .textCase(.uppercase)
                            ForEach(section.tabs) { item in
                                sidebarButton(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 18)
            }

            Divider()
            HStack(spacing: 10) {
                if let user = authStore.currentUser {
                    UserAvatar(url: user.avatarURL, name: user.displayName, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.displayName)
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                            .lineLimit(1)
                        Text("Tapgo AICoding")
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(DSHTheme.brand)
                    Text("Tapgo AICoding")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                }
                Spacer()
            }
            .padding(14)
        }
        .background(DSHTheme.moduleBg)
    }

    private func sidebarButton(_ item: Tab) -> some View {
        Button {
            tab = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .frame(width: 17)
                Text(item.rawValue)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
            .foregroundStyle(tab == item ? DSHTheme.label : DSHTheme.labelDim)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                tab == item ? DSHTheme.interactiveHoverStrong : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.rawValue)
                    .font(AppFont.scaled(.title2, multiplier: appFontScale.multiplier).weight(.semibold))
                    .foregroundStyle(DSHTheme.label)
                Text(tab.subtitle)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
            }
            Spacer()
            Button { closeSettings() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭设置")
        }
        .padding(.horizontal, 58)
        .padding(.vertical, 22)
        .background(DSHTheme.bg)
    }

    private func closeSettings() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch tab {
        case .projects:
            projectsTab
        case .remote:
            remoteTab
        case .plugins:
            PluginManagerView(isEmbedded: true)
        default:
            ScrollView {
                Group {
                    switch tab {
                    case .general: generalTab
                    case .appearance: appearanceTab
                    case .model: modelTab
                    case .computer: computerTab
                    case .memory: memoryTab
                    case .account: accountTab
                    case .about: aboutTab
                    case .projects, .remote, .plugins: EmptyView()
                    }
                }
                .frame(maxWidth: 990, alignment: .topLeading)
                .padding(.horizontal, 50)
                .padding(.vertical, 72)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Projects tab

    @ViewBuilder
    private var projectsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("项目 (\(workspace.state.projects.count))").font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                Spacer()
                Button {
                    pickAndAddLocal()
                } label: {
                    Label(L10n.addLocal, systemImage: "plus")
                }
                .accessibilityLabel(L10n.addLocal)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
            if workspace.state.projects.isEmpty {
                VStack(spacing: 8) {
                    Text("还没有项目").foregroundStyle(.secondary)
                    Text("点击右上角 “添加本地目录” 或新建任务时选目录。")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(workspace.state.projects) { p in
                        projectRow(p)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ p: Project) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: p.isRemote ? "globe" : "folder.fill")
                .foregroundStyle(p.isRemote ? .blue : .accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.displayName).font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                Text(p.displayPath)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Menu {
                if p.kind == .local {
                    Button(L10n.openInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting([p.worktreeRoot])
                    }
                }
                if p.isRemote {
                    Button(L10n.openInTerminal) {
                        let host = workspace.remoteHost(byId: p.remoteHostId ?? "")
                        let cmd = "ssh \(host?.user ?? "")@\(host?.host ?? "")"
                        NSWorkspace.shared.open(URL(string: "ssh://" + cmd) ?? URL(fileURLWithPath: "/"))
                    }
                }
                Button(L10n.rename) {
                    // Inline rename via alert below.
                }
                .disabled(true) // simplified — display name shown above
                Divider()
                Button(L10n.removeFromList, role: .destructive) {
                    workspace.removeProject(p.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .accessibilityLabel("项目 \(p.displayName), 路径 \(p.displayPath)")
    }

    private func pickAndAddLocal() {
        do {
            let result = try LocalDirectoryPicker.pickDirectory()
            let project = Project(
                id: "local-" + UUID().uuidString,
                displayName: result.url.lastPathComponent.isEmpty ? result.url.path : result.url.lastPathComponent,
                kind: .local,
                addedAt: Date(),
                lastUsedAt: Date(),
                worktreeRoot: result.url,
                bookmark: result.bookmark,
                remoteHostId: nil,
                remotePath: nil
            )
            workspace.addProject(project)
        } catch {
            NSLog("[SettingsView] pickAndAddLocal: \(error.localizedDescription)")
        }
    }

    // MARK: - Remote hosts tab

    @ViewBuilder
    private var remoteTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("远程主机 (\(workspace.state.remoteHosts.count))").font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                Spacer()
                Button { addHostSheet = true } label: {
                    Label(L10n.addRemoteHost, systemImage: "plus")
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            if workspace.state.remoteHosts.isEmpty {
                VStack(spacing: 8) {
                    Text("还没有远程主机").foregroundStyle(.secondary)
                    Text("添加 SSH 主机后,可以在新建任务时选择它作为远程项目。")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(workspace.state.remoteHosts) { h in
                        hostRow(h)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hostRow(_ h: RemoteHost) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "globe.americas.fill").foregroundStyle(.blue)
                Text(h.alias).font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier)).bold()
                Spacer()
                if testingHostId == h.id {
                    ProgressView().controlSize(.mini)
                }
                Button(L10n.testConnection) {
                    Task { await testHost(h) }
                }
                .controlSize(.small)
                Menu {
                    Button("删除", role: .destructive) {
                        workspace.removeRemoteHost(h.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            HStack(spacing: 4) {
                Text("\(h.user)@\(h.host):\(h.port)")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                if h.lastTestedAt != nil {
                    Image(systemName: (h.lastTestedOK ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle((h.lastTestedOK ?? false) ? .green : .red)
                    Text(h.lastTestedOK ?? false ? "已通过" : "失败")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                }
            }
            if let out = h.lastTestOutput, !(h.lastTestedOK ?? false) {
                Text(out)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(6)
                    .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 4))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("远程主机 \(h.alias), \(h.user)@\(h.host):\(h.port)")
    }

    private func testHost(_ host: RemoteHost) async {
        testingHostId = host.id
        let sshPath = SessionStore.findSSH()
        let argv: [String]
        do {
            argv = try RemoteCommandBuilder.buildProbeArgv(sshPath: sshPath, host: host)
        } catch {
            var h = host
            h.lastTestedAt = Date()
            h.lastTestedOK = false
            h.lastTestOutput = "参数构造失败: \(error.localizedDescription)"
            workspace.updateRemoteHost(h)
            testingHostId = nil
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: argv[0])
        proc.arguments = Array(argv.dropFirst())
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle(forReadingAtPath: "/dev/null") ?? FileHandle.nullDevice
        do { try proc.run() } catch {
            var h = host
            h.lastTestedAt = Date()
            h.lastTestedOK = false
            h.lastTestOutput = "启动失败: \(error.localizedDescription)"
            workspace.updateRemoteHost(h)
            testingHostId = nil
            return
        }
        proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let ok = proc.terminationStatus == 0
        var h = host
        h.lastTestedAt = Date()
        h.lastTestedOK = ok
        h.lastTestOutput = ok ? out : (err.isEmpty ? out : err)
        workspace.updateRemoteHost(h)
        testingHostId = nil
    }

    // MARK: - Model tab (v0.5.53 起：仿造 ZCode，独立 ModelSettingsView)

    @ViewBuilder
    private var modelTab: some View {
        ModelSettingsView()
    }

    /// 删除自定义模型（v0.5.53 起删除路径仍在 SettingsView 内，因为
    /// confirmationDialog 与 chat 选中等还有少量耦合，但实际数据流
    /// 走 ProviderRegistry）。
    private func deleteModel(_ row: TapgoConfig.ResolvedModel) {
        guard row.builtIn == nil else { return }
        let wasSelected = TapgoConfig.isSelectedCustomModel(id: row.id)
        let removed = TapgoConfig.deleteCustomModel(id: row.id)
        guard removed else { return }
        if wasSelected {
            let fallback = "builtin:\(TapgoModel.minimaxM3.rawValue)"
            selectedModelRaw = fallback
        }
    }

    // MARK: - General tab

    @ViewBuilder
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "权限与安全",
                description: "控制 Agent 何时请求批准，以及命令可访问的本机范围。",
                icon: "lock.shield"
            ) {
                VStack(spacing: 0) {
                    settingsControlRow(
                        title: L10n.approvalPolicyTitle,
                        description: "新建会话使用；进行中的会话保持创建时策略。"
                    ) {
                        Picker(L10n.approvalPolicyTitle, selection: $approvalPolicyRaw) {
                            ForEach(TapgoConfig.ApprovalPolicy.allCases) { policy in
                                Text(policy.displayName).tag(policy.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }

                    Divider()

                    settingsControlRow(
                        title: L10n.sandboxModeTitle,
                        description: "权限越宽，Agent 越能自主执行；同时也应更谨慎审核高风险动作。"
                    ) {
                        Picker(L10n.sandboxModeTitle, selection: $sandboxRaw) {
                            ForEach(TapgoConfig.SandboxMode.allCases) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }
            }

            SettingsCard(
                title: "设置生效范围",
                description: "像 ZCode 一样把“现在生效”与“新会话生效”明确区分，避免误判。",
                icon: "arrow.triangle.2.circlepath"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("外观、字号与记忆开关会立即应用。", systemImage: "bolt.fill")
                    Label("模型、审批与沙箱策略从新会话开始应用。", systemImage: "plus.bubble")
                    Label("电脑控制 MCP 注册后需重启 Harness 或新建会话。", systemImage: "terminal")
                }
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.labelDim)
            }
        }
    }

    // MARK: - Appearance tab

    @ViewBuilder
    private var appearanceTab: some View {
        let scale = AppFontScale(rawValue: fontScaleRaw) ?? .medium
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "界面设置",
                description: "主题和文字大小立即应用到整个 App。",
                icon: "circle.lefthalf.filled"
            ) {
                VStack(spacing: 0) {
                    settingsControlRow(
                        title: "界面主题",
                        description: "选择浅色、深色或跟随 macOS 系统外观。"
                    ) {
                        Picker("界面主题", selection: $appearanceRaw) {
                            Text("跟随系统").tag("system")
                            Text("浅色").tag("light")
                            Text("深色").tag("dark")
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }

                    Divider()

                    settingsControlRow(
                        title: "界面字号",
                        description: "聊天、侧栏、设置与提示文字统一缩放。"
                    ) {
                        Picker("界面字号", selection: $fontScaleRaw) {
                            ForEach(AppFontScale.allCases) { option in
                                Text(option.displayName).tag(option.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }

                    Divider()

                    settingsControlRow(
                        title: "显示工作过程",
                        description: "关闭后已完成回合只保留最终回复与文件修改摘要；每条思考、终端、读取、编辑卡片默认隐藏。"
                    ) {
                        Toggle("显示工作过程", isOn: $showWorkProcess)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            SettingsCard(
                title: "实时预览",
                description: "预览与聊天、侧栏使用同一套字体缩放。",
                icon: "textformat.size"
            ) {
                previewRow(scale: scale)
                    .padding(4)
            }
        }
    }

    // MARK: - Computer control tab

    @ViewBuilder
    private var computerTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "电脑控制",
                description: "控制 Agent 是否获得截屏、鼠标、键盘与启动应用等本机操作能力。",
                icon: "display"
            ) {
                VStack(spacing: 0) {
                    settingsControlRow(
                        title: "启用电脑控制",
                        description: "开启后注册电脑控制 MCP；新会话或重启 Harness 后生效。"
                    ) {
                        Toggle("启用电脑控制", isOn: $computerUseEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Divider()
                    settingsControlRow(
                        title: "在输入框底部显示电脑操作",
                        description: "关闭后仅隐藏快捷入口，不改变电脑控制的启用状态。"
                    ) {
                        Toggle("显示电脑操作入口", isOn: $computerUseShowInComposer)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            if computerUseEnabled {
                SettingsCard(
                    title: "可用状态",
                    description: "三项全部授权并注册后，Agent 才能可靠地观察和操作这台 Mac。",
                    icon: "checkmark.shield"
                ) {
                    VStack(spacing: 0) {
                        computerStatusRow(
                            title: "辅助功能 (Accessibility)",
                            description: "读取与驱动界面元素、合成键盘和鼠标输入。",
                            ready: computerPermissionState.accessibility,
                            readyText: "已授权",
                            notReadyText: "未授权",
                            actionTitle: ComputerUsePermissionKind.accessibility.settingsButtonTitle,
                            action: { openPermissionSettings(.accessibility) }
                        )
                        Divider()
                        computerStatusRow(
                            title: "屏幕录制 (Screen Recording)",
                            description: "让 Agent 在操作前读取当前屏幕。",
                            ready: computerPermissionState.screenRecording,
                            readyText: "已授权",
                            notReadyText: "未授权",
                            actionTitle: ComputerUsePermissionKind.screenRecording.settingsButtonTitle,
                            action: { openPermissionSettings(.screenRecording) }
                        )
                        Divider()
                        computerStatusRow(
                            title: "电脑控制 MCP",
                            description: computerUseConfigRegistered
                                ? "已指向 Tapgo Computer Use Helper；新会话或重启 Harness 后生效。"
                                : "尚未在隔离 Codex home 中找到注册段。",
                            ready: computerUseConfigRegistered,
                            readyText: "已注册",
                            notReadyText: "未注册"
                        )
                    }
                }

                SettingsCard(
                    title: "检测与修复",
                    description: "重新检测不会申请权限；重新注册只更新 Tapgo AICoding 自己的隔离配置。",
                    icon: "wrench.and.screwdriver"
                ) {
                    HStack(spacing: 12) {
                        Button {
                            computerPermissionRefresh += 1
                            computerUseMessage = "已重新读取当前权限与配置状态。"
                        } label: {
                            Label("重新检测", systemImage: "arrow.clockwise")
                        }
                        Button {
                            let ok = TapgoConfig.ensureComputerUseMCPSection()
                            computerPermissionRefresh += 1
                            computerUseMessage = ok
                                ? "电脑控制 MCP 已注册；请新建会话或重启 Harness。"
                                : "未找到随 App 分发的电脑控制二进制，未修改配置。"
                        } label: {
                            Label("重新注册 MCP", systemImage: "terminal")
                        }
                        Spacer(minLength: 0)
                    }
                }

                Text("权限属于真正执行电脑控制的 Tapgo Computer Use Helper。点击对应入口后，把浮动面板里的 Helper 拖进系统允许列表。")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            } else {
                Label("电脑控制已关闭。输入框快捷入口仍可按你的显示偏好保留，并以灰色状态显示。",
                      systemImage: "pause.circle")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
                    .padding(.horizontal, 2)
            }

            if let computerUseMessage {
                Label(computerUseMessage, systemImage: "info.circle")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: computerUseEnabled) { _, enabled in
            let ok = TapgoConfig.syncComputerUseMCPPreference()
            computerPermissionRefresh += 1
            if ok {
                computerUseMessage = enabled
                    ? "电脑控制已启用；请新建会话或重启 Harness。"
                    : "电脑控制已关闭；新会话不再加载相关工具。"
            } else {
                computerUseMessage = "设置已保存，但 MCP 配置更新失败；请检查隔离配置目录权限。"
            }
        }
        .task(id: computerPermissionRefresh) {
            computerPermissionState = .loading
            computerPermissionState = await ComputerUsePermissionProbe.read(
                helperAppURL: TapgoConfig.computerUseHelperAppURL()
            )
            if let error = computerPermissionState.error {
                computerUseMessage = error
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            computerPermissionRefresh += 1
        }
    }

    private var computerUseConfigRegistered: Bool {
        guard let config = try? String(contentsOf: TapgoConfig.configPath, encoding: .utf8) else {
            return false
        }
        return config.contains("[mcp_servers.\(ComputerUseMCP.configServerKey)]")
    }

    private func computerStatusRow(
        title: String,
        description: String,
        ready: Bool?,
        readyText: String = "已就绪",
        notReadyText: String = "未就绪",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.medium))
                    .foregroundStyle(DSHTheme.label)
                Text(description)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
            }
            Spacer(minLength: 24)
            if ready == false, let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.medium))
                .foregroundStyle(DSHTheme.brand)
            }
            let statusText = ready == nil ? "检测中" : (ready == true ? readyText : notReadyText)
            let statusIcon = ready == nil ? "clock" : (ready == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Label(statusText, systemImage: statusIcon)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                .foregroundStyle(ready == nil ? DSHTheme.labelTertiary : (ready == true ? DSHTheme.success : DSHTheme.warn))
        }
        .padding(.vertical, 14)
    }

    private func openPermissionSettings(_ permission: ComputerUsePermissionKind) {
        guard let helperAppURL = TapgoConfig.computerUseHelperAppURL() else {
            computerUseMessage = "未找到 Tapgo Computer Use Helper；请重新安装最新版 App。"
            return
        }
        guard let settingsURL = permission.settingsURL,
              NSWorkspace.shared.open(settingsURL) else {
            computerUseMessage = "无法打开 macOS 的\(permission.title)设置。"
            return
        }
        ComputerUsePermissionGuideController.shared.present(
            permission: permission,
            helperAppURL: helperAppURL,
            completion: {
                computerPermissionRefresh += 1
                computerUseMessage = "已返回 App，请重新检测并确认\(permission.title)状态。"
            }
        )
        computerUseMessage = "请把浮动面板中的 Tapgo Computer Use 拖进\(permission.title)允许列表。"
    }

    private func settingsControlRow<Control: View>(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.medium))
                    .foregroundStyle(DSHTheme.label)
                Text(description)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
            }
            Spacer(minLength: 20)
            control()
        }
        .padding(.vertical, 14)
    }

    /// Tiny live-preview that uses the same `AppFont` helper the rest of
    /// the app uses, so what the user sees here is exactly what they'll
    /// see in the chat / sidebar.
    @ViewBuilder
    private func previewRow(scale: AppFontScale) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tapgo AICoding")
                .font(AppFont.scaled(.title3, multiplier: scale.multiplier))
            Text("给 MiniMax-M3 发条任务…")
                .font(AppFont.scaled(.body, multiplier: scale.multiplier))
                .foregroundStyle(.secondary)
            Text("已批准 · 思考摘要 · 3 个回合")
                .font(AppFont.scaled(.caption, multiplier: scale.multiplier))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Account tab

    @ViewBuilder
    private var accountTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user = authStore.currentUser {
                HStack(spacing: 14) {
                    UserAvatar(url: user.avatarURL, name: user.displayName, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier)).bold()
                            .textSelection(.enabled)
                        Text("@\(user.username)")
                            .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(user.wechatNickname ?? user.roleText)
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("登录身份: \(user.roleText)")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            } else {
                Text("未登录")
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button(role: .destructive) {
                authStore.logout()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .help("清除本机登录状态，下次启动需重新扫码")
            Text("退出后需重新微信扫码才能进入。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - About tab

    @ViewBuilder
    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tapgo AICoding \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0")")
                .font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier)).bold()
                .textSelection(.enabled)
            Text("当前模型: \(TapgoConfig.resolveSelected().displayName)（composer 弹窗可切换，新会话生效）")
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .textSelection(.enabled)
            Text("独立 Codex home: \(TapgoConfig.codexHome.path)")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("日志: \(TapgoConfig.logFileURL.path)")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Endpoint: \(TapgoConfig.defaultRegion.baseURL)")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    revealInFinder(TapgoConfig.logFileURL, fallbackDir: TapgoConfig.logFileURL.deletingLastPathComponent())
                } label: {
                    Label("在 Finder 中显示日志", systemImage: "doc.text")
                }
                Button {
                    revealInFinder(TapgoConfig.codexHome, fallbackDir: TapgoConfig.codexHome)
                } label: {
                    Label("显示配置目录", systemImage: "folder")
                }
                Button {
                    copyDiagnostics()
                } label: {
                    Label("复制诊断信息", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            Divider()
            Text("不会读取或修改官方 ~/.codex/ 任何文件。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Memory tab

    @ViewBuilder
    private var memoryTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                Section("跨会话记忆 · 三层架构") {
                    Toggle(isOn: $memoryEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("启用跨会话记忆（总开关）")
                                .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                            Text("关闭后，下面两个细粒度开关也会被强制关闭。开启后，再分别控制“读”和“写”。")
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    Toggle(isOn: $memoryReadEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("读：注入摘要到新会话（use_memories）")
                                .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                            Text("开启后，新会话的 baseInstructions 会包含三层记忆摘要。关闭后模型看不到任何记忆。")
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!memoryEnabled)
                    Toggle(isOn: $memoryWriteEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("写：每轮完成后提炼要点（generate_memories）")
                                .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                            Text("开启后，每轮完成会调用模型抽取 1-3 条要点写入对应层；关闭后不再写入但仍可读取现有记忆。")
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!memoryEnabled)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("分层与文件路径：")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.secondary)
                        Text("USER   层（跨项目用户偏好）：\(TapgoConfig.userMemoryURL.path)")
                        Text("GLOBAL 层（环境 / 工具 / 定制轮）：\(TapgoConfig.globalMemoryURL.path)")
                        Text("KEY    层（per-git-branch 项目记忆）：\(TapgoConfig.memoryDirectory.appendingPathComponent("keys").path)")
                    }
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                }

                Section("跨设备同步（iCloud Drive）") {
                    Toggle(isOn: $cloudSyncEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("启用跨设备同步")
                                .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                            Text("记忆文件镜像到 iCloud Drive，当前 Apple ID 登录的其他 Mac（JKmacmini / fafamacmini 等）可以自动同步。只上传记忆文件，不会上传 API key / 代码 / 会话内容。")
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    iCloudStatusRow
                    HStack(spacing: 8) {
                        Button { TapgoConfig.syncMemoryPullAll(); refreshMemoryStatus() } label: {
                            Label("从 iCloud 拉取现在", systemImage: "arrow.down.circle")
                        }
                        Button { TapgoConfig.syncMemoryPushAll(); refreshMemoryStatus() } label: {
                            Label("推送到 iCloud 现在", systemImage: "arrow.up.circle")
                        }
                        Button { refreshMemoryStatus() } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                Section("跨会话记忆文件状态") {
                    memoryFileRow(title: "USER layer", status: memoryStatus)
                    memoryFileRow(title: "GLOBAL layer", status: globalMemoryStatus)
                    HStack(spacing: 8) {
                        Button {
                            revealInFinder(
                                TapgoConfig.memoryDirectory,
                                fallbackDir: TapgoConfig.memoryDirectory
                            )
                        } label: {
                            Label("在 Finder 中显示", systemImage: "folder")
                        }
                        Button { copyUserMemory() } label: {
                            Label("复制 USER 层内容", systemImage: "doc.on.doc")
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    if let msg = memoryCopyMessage {
                        Text(msg)
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Codex 内部记忆库") {
                    Text("Codex 服务端按线程将模型生成的记忆条目持久化到 memories_1.sqlite，仅供查阅；本 App 不修改此文件。")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                    memoryFileRow(title: "codex memories", status: codexMemoryStatus)
                    HStack(spacing: 8) {
                        Button {
                            let url = TapgoConfig.codexHome.appendingPathComponent("memories_1.sqlite")
                            revealInFinder(url, fallbackDir: TapgoConfig.codexHome)
                        } label: {
                            Label("在 Finder 中显示", systemImage: "folder")
                        }
                        Button {
                            revealInFinder(TapgoConfig.codexHome, fallbackDir: TapgoConfig.codexHome)
                        } label: {
                            Label("显示 Codex home", systemImage: "externaldrive")
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .formStyle(.grouped)
            Text("App 不会读取或修改 ~/.codex/ 任何文件。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .task { refreshMemoryStatus() }
    }

    @ViewBuilder
    private var iCloudStatusRow: some View {
        let available = MemoryCloudSync.isICloudAvailable
        let path = MemoryCloudSync.iCloudMirrorURL?.path ?? "(iCloud Drive 未配置)"
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(available ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(available ? "iCloud Drive 可用" : "iCloud Drive 未配置")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            }
            Text(path)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func memoryFileRow(title: String, status: MemoryFileStatus?) -> some View {
        if let s = status, s.exists {
            LabeledContent("大小", value: MemoryFileStatus.formatBytes(s.size))
            LabeledContent("行数", value: "\(s.lines)")
            LabeledContent("最近修改", value: MemoryFileStatus.formatDate(s.modifiedAt))
        } else {
            Text("\(title)：尚未生成")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
        }
    }

    private func refreshMemoryStatus() {
        memoryStatus = MemoryFileStatus.collect(at: TapgoConfig.userMemoryURL)
        globalMemoryStatus = MemoryFileStatus.collect(at: TapgoConfig.globalMemoryURL)
        codexMemoryStatus = MemoryFileStatus.collect(
            at: TapgoConfig.codexHome.appendingPathComponent("memories_1.sqlite")
        )
    }

    private func copyUserMemory() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let body = try? String(contentsOf: TapgoConfig.userMemoryURL, encoding: .utf8) {
            pb.setString(body, forType: .string)
            memoryCopyMessage = "已复制 \(body.count) 个字符到剪贴板"
        } else {
            pb.setString("(memory.md 尚未生成)", forType: .string)
            memoryCopyMessage = "memory.md 尚未生成；剪贴板放入占位提示"
        }
    }

    /// Snapshot of an on-disk file relevant to memory: existence, size,
    /// line count, and last-modified time. Pure value type so SwiftUI can
    /// diff it cheaply.
    struct MemoryFileStatus: Equatable {
        let exists: Bool
        let size: Int64
        let lines: Int
        let modifiedAt: Date?

        static func collect(at url: URL) -> MemoryFileStatus {
            let fm = FileManager.default
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = (attrs[.size] as? NSNumber)?.int64Value,
                  let mtime = (attrs[.modificationDate] as? Date)
            else {
                return MemoryFileStatus(exists: false, size: 0, lines: 0, modifiedAt: nil)
            }
            let lineCount: Int = {
                guard let body = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
                if body.isEmpty { return 0 }
                return body.reduce(into: 1) { acc, ch in if ch == "\n" { acc += 1 } }
            }()
            return MemoryFileStatus(exists: true, size: size, lines: lineCount, modifiedAt: mtime)
        }

        static func formatBytes(_ n: Int64) -> String {
            let f = ByteCountFormatter()
            f.allowedUnits = [.useKB, .useMB]
            f.countStyle = .file
            return f.string(fromByteCount: n)
        }

        static func formatDate(_ d: Date?) -> String {
            guard let d else { return "-" }
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: d)
        }
    }

    private func revealInFinder(_ url: URL, fallbackDir: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(fallbackDir)
        }
    }

    private func copyDiagnostics() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0"
        let text = [
            "Tapgo AICoding \(version)",
            "模型: \(TapgoConfig.resolveSelected().displayName)",
            "区域: \(TapgoConfig.defaultRegion.displayName)",
            "端点: \(TapgoConfig.resolveSelected().baseURL)",
            "Codex home: \(TapgoConfig.codexHome.path)",
            "日志: \(TapgoConfig.logFileURL.path)",
        ].joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

/// Shared card surface for settings pages. It owns only presentation;
/// persistence remains in the controls supplied by each tab.
private struct SettingsCard<Content: View>: View {
    let title: String
    let description: String
    let icon: String
    @ViewBuilder let content: Content

    init(
        title: String,
        description: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DSHTheme.brand)
                    .frame(width: 32, height: 32)
                    .background(DSHTheme.brandSoft, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(DSHTheme.label)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(DSHTheme.labelDim)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(18)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
                .stroke(DSHTheme.border, lineWidth: 1)
        )
        .shadow(color: DSHTheme.cardShadow, radius: 8, y: 2)
    }
}

/// Modal for adding a remote host.
private struct AddRemoteHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCommit: (RemoteHost) -> Void
    @State private var alias: String = ""
    @State private var host: String = ""
    @State private var user: String = NSUserName()
    @State private var portText: String = "22"
    @State private var identity: String = "default"
    @State private var error: String?
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加远程主机").font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier)).bold()
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }.padding(20)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                field(L10n.hostAlias, text: $alias)
                field(L10n.hostHost, text: $host)
                field(L10n.hostUser, text: $user)
                field(L10n.hostPort, text: $portText)
                field(L10n.hostIdentity, text: $identity)
                Text("说明：私钥路径留空或填 default 表示走 ~/.ssh/config + ssh-agent；填绝对路径等价于 ssh -i。")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                if let err = error {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }.padding(20)
        }
        .frame(width: 480, height: 420)
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 78, alignment: .leading)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.monoScaled(size: 13, multiplier: appFontScale.multiplier))
        }
    }

    private var canSave: Bool {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty, !trimmedHost.isEmpty, !trimmedUser.isEmpty else { return false }
        guard RemoteCommandBuilder.validateAlias(trimmedAlias) != nil else { return false }
        guard RemoteCommandBuilder.validateHost(trimmedHost) != nil else { return false }
        guard RemoteCommandBuilder.validateUser(trimmedUser) != nil else { return false }
        guard let portValue = Int(portText.trimmingCharacters(in: .whitespaces)),
              portValue > 0, portValue < 65536 else { return false }
        return true
    }

    private func commit() {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteCommandBuilder.validateAlias(trimmedAlias) != nil else {
            error = "别名只允许字母/数字/点/下划线/连字符"
            return
        }
        guard RemoteCommandBuilder.validateHost(trimmedHost) != nil else {
            error = "主机(IP/域名)含非法字符"
            return
        }
        guard RemoteCommandBuilder.validateUser(trimmedUser) != nil else {
            error = "用户只允许字母/数字/点/下划线/连字符"
            return
        }
        guard let portValue = Int(portText.trimmingCharacters(in: .whitespaces)),
              portValue > 0, portValue < 65536 else {
            error = "端口需为 1–65535 之间的整数"
            return
        }
        let h = RemoteHost(
            id: "host-" + UUID().uuidString,
            alias: trimmedAlias,
            host: trimmedHost,
            user: trimmedUser,
            port: portValue,
            identityHint: identity.isEmpty ? "default" : identity,
            addedAt: Date(),
            lastTestedAt: nil, lastTestedOK: nil, lastTestOutput: nil
        )
        onCommit(h)
        dismiss()
    }
}

// v0.5.53 起 ModelFormSheet / BuiltinKeySheet 移到独立 ModelSettingsView.swift，
// 仿造 ZCode 「Provider / ProviderModel」双层结构。保留说明：
//   * v0.5.42 起的「CustomModel 新增/编辑」单层表单已不再被 SettingsView 引用
//   * 删除路径走 confirmationDialog 由 SettingsView 触发，业务流走 ProviderRegistry
