import SwiftUI

/// 已配对后的工作面板 —— 对齐 Codex 移动端首页结构 (v1.0.4 重构)。
///
/// 顶部: Mac 展示名 + 实时连接状态
/// 主体: 「项目」大标题 + 项目分组列表 (📁项目名 + 每项目最近会话标题)
/// 底部: 连接管理 (停止连接 / 取消配对)
struct DashboardView: View {
    @EnvironmentObject var pairing: PairingStore
    @State private var projectGroups: [ProjectGroup] = []
    @State private var loadError: String?
    @State private var isLoadingProjects = false
    @State private var newMessage: String = ""
    @State private var sendingMessage = false
    @StateObject private var relay = RelayLink()

    var body: some View {
        NavigationStack {
            List {
                projectsSection
                if let err = loadError { errorSection(err) }
            }
            .listStyle(.plain)
            .navigationTitle("远程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("远程").font(.headline)
                        HStack(spacing: 4) {
                            Circle().fill(isConnected ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(pairingMacHostname)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { Task { await sendMessage() } } label: { Label("发消息给当前会话", systemImage: "paperplane") }
                        Button { pairing.stopLink() } label: { Label("停止连接", systemImage: "stop.circle") }
                        Button(role: .destructive) { pairing.unpair() } label: { Label("取消配对", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task { await loadProjects() }
        }
    }

    // MARK: - 顶部: Mac 名 + 连接状态

    private var headerSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "macbook")
                    .foregroundStyle(.secondary)
                Text(pairingMacHostname)
                    .font(.headline)
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(connectionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 项目分组 (对齐 Codex 移动端首页)

    private var projectsSection: some View {
        Section {
            if projectGroups.isEmpty && isLoadingProjects {
                HStack { ProgressView(); Text("加载项目…").foregroundStyle(.secondary) }
            }
            if projectGroups.isEmpty && !isLoadingProjects && loadError == nil {
                Text("暂无项目").foregroundStyle(.secondary)
            }
            ForEach(projectGroups) { group in
                Section {
                    ForEach(group.recentSessions) { s in
                        Text(s.title ?? "(无标题)")
                            .font(.subheadline)
                    }
                    Button {
                        Task { await loadProjects() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise").font(.footnote)
                    }
                } header: {
                    Label(group.name, systemImage: "folder")
                        .font(.headline)
                        .textCase(nil)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var legacyProjectsSection: some View {
        Section("项目") {
            if projectGroups.isEmpty && isLoadingProjects {
                HStack { ProgressView(); Text("加载项目…").foregroundStyle(.secondary) }
            }
            if projectGroups.isEmpty && !isLoadingProjects && loadError == nil && isConnected {
                Text("Mac 端还没有项目").foregroundStyle(.secondary)
            }
            ForEach(projectGroups) { group in
                DisclosureGroup {
                    ForEach(group.recentSessions) { s in
                        Text(s.title ?? "(无标题)")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.leading, 4)
                    }
                } label: {
                    Label(group.name, systemImage: "folder")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            if isConnected {
                Button {
                    Task { await loadProjects() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Text(message).font(.footnote).foregroundStyle(.red)
        }
    }

    // MARK: - 快捷发消息 (真业务: 送进 Mac 当前会话)

    private var quickMessageSection: some View {
        Section("发消息给当前会话") {
            TextField("输入消息…", text: $newMessage, axis: .vertical)
                .lineLimit(1...3)
                .disabled(!isConnected || sendingMessage)
            HStack {
                if sendingMessage { ProgressView() }
                Spacer()
                Button {
                    Task { await sendMessage() }
                } label: {
                    Label("发送", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConnected || newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - 连接管理

    private var manageSection: some View {
        Section("连接管理") {
            LabeledContent("主机", value: pairingMacHost)
            HStack(spacing: 12) {
                Button("停止连接") { pairing.stopLink() }
                    .buttonStyle(.bordered)
                    .disabled(!isConnected)
                Button("取消配对", role: .destructive) { pairing.unpair() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Helpers

    /// 已配对 Mac 的展示名 (hostname); 未配对时回落 "Mac"。
    private var pairingMacHostname: String {
        if case .paired(let mac, _) = pairing.state { return mac.hostname }
        return "Mac"
    }

    /// 连接管理里显示的 host:port。
    private var pairingMacHost: String {
        if case .paired(let mac, _) = pairing.state {
            return "\(mac.host):\(mac.port)"
        }
        return "—"
    }

    private var isConnected: Bool {
        if case .connected = pairing.link.status { return true }
        return false
    }

    private var connectionText: String {
        switch pairing.link.status {
        case .idle: return "未启用长链接"
        case .discovering: return "搜索中…"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .failed(let msg): return "异常 · \(msg)"
        }
    }

    // MARK: - RPC

    @MainActor
    private func loadProjects() async {
        isLoadingProjects = true
        loadError = nil
        // v1.0.5: 公网中继优先 (任意网络可用), 失败回落局域网长链接。
        if relay.isConfigured {
            do {
                let params = try await relay.fetchProjects()
                projectGroups = Self.parseProjectGroups(params)
                isLoadingProjects = false
                return
            } catch {
                loadError = "公网加载失败: \(error.localizedDescription)（回落局域网）"
            }
        }
        guard isConnected else {
            isLoadingProjects = false
            if loadError == nil { loadError = "未连接 Mac（长链接未就绪）" }
            return
        }
        pairing.link.request(method: MobileRemoteLink.Method.listProjects) { result in
            isLoadingProjects = false
            switch result {
            case .success(let params):
                projectGroups = Self.parseProjectGroups(params)
            case .failure(let err):
                loadError = "加载项目失败: \(err.localizedDescription)"
            }
        }
    }

    @MainActor
    private func sendMessage() async {
        let msg = newMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        sendingMessage = true
        defer { sendingMessage = false }
        if relay.isConfigured {
            do {
                try await relay.send(text: msg)
                newMessage = ""
                return
            } catch {
                loadError = "公网发送失败: \(error.localizedDescription)"
            }
        }
        guard isConnected else { return }
        var p = MobileRemoteLink.Params()
        p.set("text", .string(msg))
        pairing.link.request(method: MobileRemoteLink.Method.sendMessage, params: p) { result in
            switch result {
            case .success: newMessage = ""
            case .failure(let err): loadError = "发送失败: \(err.localizedDescription)"
            }
        }
    }

    private static func parseProjectGroups(_ params: MobileRemoteLink.Params) -> [ProjectGroup] {
        guard case .array(let arr)? = params["projects"] else { return [] }
        return arr.compactMap { v in
            guard case .object(let obj) = v,
                  let id = obj["id"]?.stringValue,
                  let name = obj["name"]?.stringValue else { return nil }
            var sessions: [SessionSummary] = []
            if case .array(let sarr)? = obj["recentSessions"] {
                sessions = sarr.compactMap { sv in
                    guard case .object(let so) = sv,
                          let sid = so["id"]?.stringValue else { return nil }
                    return SessionSummary(
                        id: sid,
                        title: so["title"]?.stringValue,
                        project: name,
                        projectId: id,
                        updatedAt: so["updatedAt"]?.stringValue)
                }
            }
            return ProjectGroup(id: id, name: name, recentSessions: sessions)
        }
    }
}

/// 项目分组 (首页结构)。
struct ProjectGroup: Identifiable {
    let id: String
    let name: String
    let recentSessions: [SessionSummary]
}

struct SessionSummary: Identifiable {
    let id: String
    let title: String?
    let project: String?
    /// v1.0.2: Mac 端回传的项目 id, 用于切项目 RPC。
    let projectId: String?
    let updatedAt: String?
}

/// 可切项目选项 (从最近会话去重派生)。
struct ProjectOption: Hashable, Identifiable {
    let id: String
    let name: String
}
