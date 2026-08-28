import SwiftUI
import TapgoCore

/// Settings sheet. Three tabs:
///   1. Projects — add / rename / remove / "open in Finder" / "Open in Terminal"
///   2. Remote Hosts — add / edit / test / remove
///   3. About — version, CODEX_HOME, log dir
struct SettingsView: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @EnvironmentObject var authStore: AdminAuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .projects
    @State private var addHostSheet = false
    @State private var testingHostId: String?
    @State private var testingOutput: String?
    @State private var memoryStatus: MemoryFileStatus?
    @State private var globalMemoryStatus: MemoryFileStatus?
    @State private var codexMemoryStatus: MemoryFileStatus?
    @State private var memoryCopyMessage: String?

    @AppStorage(TapgoConfig.approvalPolicyKey) private var approvalPolicyRaw =
        TapgoConfig.ApprovalPolicy.never.rawValue
    @AppStorage(TapgoConfig.sandboxKey) private var sandboxRaw =
        TapgoConfig.SandboxMode.dangerFullAccess.rawValue
    @AppStorage("tapgo.baseURL") private var baseURL = ""
    @AppStorage(TapgoConfig.reasoningEffortKey) private var reasoningEffort = ""
    @AppStorage(TapgoConfig.appearanceKey) private var appearanceRaw = "system"
    @AppStorage(AppFontScale.userDefaultsKey) private var fontScaleRaw = "medium"
    @AppStorage(TapgoConfig.memoryEnabledKey) private var memoryEnabled = true
    @AppStorage(TapgoConfig.memoryReadEnabledKey) private var memoryReadEnabled = true
    @AppStorage(TapgoConfig.memoryWriteEnabledKey) private var memoryWriteEnabled = true
    @AppStorage("tapgo.memory.cloudSync") private var cloudSyncEnabled = true
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    enum Tab: String, CaseIterable, Identifiable {
        case account = "账户"
        case projects = "项目"
        case remote = "远程主机"
        case runtime = "运行"
        case appearance = "外观"
        case about = "关于"
        case memory = "记忆"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier)).bold()
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).accessibilityLabel("关闭")
            }.padding(20)
            Divider()
            HStack(spacing: 0) {
                List(Tab.allCases, selection: $tab) { t in
                    Text(t.rawValue).tag(t)
                }
                .listStyle(.sidebar)
                .frame(width: 140)
                Divider()
                Group {
                    switch tab {
                    case .account:    accountTab
                    case .projects:   projectsTab
                    case .remote:     remoteTab
                    case .runtime:    runtimeTab
                    case .appearance: appearanceTab
                    case .about:      aboutTab
                    case .memory:     memoryTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(isPresented: $addHostSheet) {
            AddRemoteHostSheet { host in
                workspace.addRemoteHost(host)
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

    // MARK: - Runtime tab

    @ViewBuilder
    private var runtimeTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("运行行为").font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
            Form {
                Picker(L10n.approvalPolicyTitle, selection: $approvalPolicyRaw) {
                    ForEach(TapgoConfig.ApprovalPolicy.allCases) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }
                Picker(L10n.sandboxModeTitle, selection: $sandboxRaw) {
                    ForEach(TapgoConfig.SandboxMode.allCases) { m in
                        Text(m.displayName).tag(m.rawValue)
                    }
                }
                Picker(L10n.reasoningEffortTitle, selection: $reasoningEffort) {
                    Text("默认 (模型定)").tag("")
                    Text("无 (none)").tag("none")
                    Text("高 (high)").tag("high")
                }
                TextField("Endpoint (Base URL)", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                HStack {
                    Button(L10n.apply) {
                        try? TapgoConfig.applyBaseURL(baseURL)
                    }
                    Button(L10n.resetDefault) {
                        baseURL = ""
                        try? TapgoConfig.applyBaseURL("")
                    }
                }
            }
            .formStyle(.grouped)
            Text(L10n.approvalPolicyHint)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            Text("留空则使用默认端点：\(TapgoConfig.defaultRegion.baseURL)")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
            Spacer()
        }
        .padding(.top, 20)
    }

    // MARK: - Appearance tab

    @ViewBuilder
    private var appearanceTab: some View {
        let scale = AppFontScale(rawValue: fontScaleRaw) ?? .medium
        VStack(alignment: .leading, spacing: 14) {
            Text("外观").font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
            Form {
                Section("字体大小") {
                    Picker("字体大小", selection: $fontScaleRaw) {
                        ForEach(AppFontScale.allCases) { s in
                            Text(s.displayName).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("全局生效：聊天、侧栏、设置、提示等所有文本。会话内菜单（⋮ → 字体大小）也是同一选项。")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                }
                Section("预览") {
                    previewRow(scale: scale)
                }
            }
            .formStyle(.grouped)
            Spacer()
        }
        .padding(.top, 20)
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
            Text("固定模型: \(TapgoConfig.modelName)")
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
            Text("记忆").font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
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
        .padding(.top, 20)
        .task { refreshMemoryStatus() }
    }

    @ViewBuilder
    private var iCloudStatusRow: some View {
        let available = MemoryCloudSync.isICloudAvailable
        let path = MemoryCloudSync.iCloudMirrorURL?.path ?? "(iCloud Drive 未配置)"
        return VStack(alignment: .leading, spacing: 2) {
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
            "模型: \(TapgoConfig.modelName)",
            "区域: \(TapgoConfig.defaultRegion.displayName)",
            "端点: \(TapgoConfig.effectiveBaseURL)",
            "Codex home: \(TapgoConfig.codexHome.path)",
            "日志: \(TapgoConfig.logFileURL.path)",
        ].joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

/// Modal for adding a remote host.
private struct AddRemoteHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCommit: (RemoteHost) -> Void
    @State private var alias = ""
    @State private var host = ""
    @State private var user = NSUserName()
    @State private var port: Int = 22
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
            Form {
                TextField(L10n.hostAlias, text: $alias)
                TextField(L10n.hostHost, text: $host)
                TextField(L10n.hostUser, text: $user)
                TextField(L10n.hostPort, value: $port, format: .number)
                TextField(L10n.hostIdentity, text: $identity)
                if let err = error {
                    Text(err).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(alias.isEmpty || host.isEmpty || user.isEmpty)
            }.padding(20)
        }
        .frame(width: 460, height: 360)
    }
    private func commit() {
        guard RemoteCommandBuilder.validateHost(host) != nil else { error = "主机不合法"; return }
        guard RemoteCommandBuilder.validateUser(user) != nil else { error = "用户不合法"; return }
        let h = RemoteHost(
            id: "host-" + UUID().uuidString,
            alias: alias,
            host: host,
            user: user,
            port: port,
            identityHint: identity.isEmpty ? "default" : identity,
            addedAt: Date(),
            lastTestedAt: nil, lastTestedOK: nil, lastTestOutput: nil
        )
        onCommit(h)
        dismiss()
    }
}
