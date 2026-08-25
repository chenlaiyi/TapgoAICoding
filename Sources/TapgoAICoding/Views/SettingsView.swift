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

    @AppStorage(TapgoConfig.approvalPolicyKey) private var approvalPolicyRaw =
        TapgoConfig.ApprovalPolicy.never.rawValue
    @AppStorage(TapgoConfig.sandboxKey) private var sandboxRaw =
        TapgoConfig.SandboxMode.dangerFullAccess.rawValue
    @AppStorage("tapgo.baseURL") private var baseURL = ""
    @AppStorage(TapgoConfig.reasoningEffortKey) private var reasoningEffort = ""
    @AppStorage(TapgoConfig.appearanceKey) private var appearanceRaw = "system"
    @AppStorage("tapgo.fontScale") private var fontScale = "medium"

    enum Tab: String, CaseIterable, Identifiable {
        case account = "账户"
        case projects = "项目"
        case remote = "远程主机"
        case runtime = "运行"
        case appearance = "外观"
        case about = "关于"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.title3).bold()
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
                    case .account:  accountTab
                    case .projects: projectsTab
                    case .remote:   remoteTab
                    case .runtime:  runtimeTab
                    case .appearance: appearanceTab
                    case .about:    aboutTab
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
                Text("项目 (\(workspace.state.projects.count))").font(.headline)
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
                        .font(.caption).foregroundStyle(.tertiary)
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
                Text(p.displayName).font(.subheadline)
                Text(p.displayPath)
                    .font(.caption2)
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
                Text("远程主机 (\(workspace.state.remoteHosts.count))").font(.headline)
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
                        .font(.caption).foregroundStyle(.tertiary)
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
                Text(h.alias).font(.subheadline).bold()
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if h.lastTestedAt != nil {
                    Image(systemName: (h.lastTestedOK ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle((h.lastTestedOK ?? false) ? .green : .red)
                    Text(h.lastTestedOK ?? false ? "已通过" : "失败")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let out = h.lastTestOutput, !(h.lastTestedOK ?? false) {
                Text(out)
                    .font(.caption2)
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
            Text("运行行为").font(.headline)
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
                    Text("低 (low)").tag("low")
                    Text("中 (medium)").tag("medium")
                    Text("高 (high)").tag("high")
                }
                Picker(L10n.appearanceTitle, selection: $appearanceRaw) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            Text("留空则使用默认端点：\(TapgoConfig.defaultRegion.baseURL)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
            Spacer()
        }
        .padding(.top, 20)
    }

    // MARK: - Appearance tab

    @ViewBuilder
    private var appearanceTab: some View {
        Form {
            Section("字体大小") {
                Picker("字体大小", selection: $fontScale) {
                    Text("小").tag("small")
                    Text("中").tag("medium")
                    Text("大").tag("large")
                }
                .pickerStyle(.segmented)
                Text("全局生效：聊天、会话列表、设置、提示等所有文字。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("预览") {
                Text("你好，Tapgo AICoding。今天适合写代码。")
                    .dynamicTypeSize(previewTypeSize)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewTypeSize: DynamicTypeSize {
        switch fontScale {
        case "small": return .medium
        case "large": return .xxLarge
        default: return .xLarge
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
                            .font(.title3).bold()
                            .textSelection(.enabled)
                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(user.wechatNickname ?? user.roleText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("登录身份: \(user.roleText)")
                    .font(.caption)
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
                .font(.caption)
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
            Text("Tapgo AICoding \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.3")")
                .font(.title3).bold()
                .textSelection(.enabled)
            Text("固定模型: \(TapgoConfig.modelName)")
                .font(.subheadline)
                .textSelection(.enabled)
            Text("独立 Codex home: \(TapgoConfig.codexHome.path)")
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("日志: \(TapgoConfig.logFileURL.path)")
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Endpoint: \(TapgoConfig.defaultRegion.baseURL)")
                .font(.caption).foregroundStyle(.secondary)
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
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(20)
    }

    private func revealInFinder(_ url: URL, fallbackDir: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(fallbackDir)
        }
    }

    private func copyDiagnostics() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.3"
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加远程主机").font(.title3).bold()
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
                    Text(err).font(.caption).foregroundStyle(.red)
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
