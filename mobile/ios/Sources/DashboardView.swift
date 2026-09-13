import SwiftUI

/// 已配对后的工作面板 (v1.0.7 重做)——对齐 Codex 移动端首页风格:
/// 紧凑顶栏 (远程 + 机器名绿点) + 项目卡片列表 (SF Symbol 彩色图标 + 编辑笔)
/// + 底部浮动搜索/语音/新建条 (Codex 风格)。
struct DashboardView: View {
    @EnvironmentObject var pairing: PairingStore
    @State private var projectGroups: [ProjectGroup] = []
    @State private var loadError: String?
    @State private var isLoadingProjects = false
    @StateObject private var relay = RelayLink()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if projectGroups.isEmpty && isLoadingProjects {
                            loadingState
                        }
                        if let err = loadError { errorState(err) }
                        ForEach(projectGroups) { group in
                            ProjectCard(group: group)
                        }
                        if projectGroups.isEmpty && !isLoadingProjects && loadError == nil {
                            emptyState
                        }
                        Spacer().frame(height: 90)   // 给底部浮动条留空间
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .refreshable { await loadProjects() }
                .task { await loadProjects() }
                .navigationTitle("远程")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }

                BottomBar()
            }
        }
    }

    // MARK: - 顶栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    // MARK: - 状态视图

    private var loadingState: some View {
        HStack { ProgressView(); Text("加载项目…").foregroundStyle(.secondary) }
            .padding(.vertical, 40).frame(maxWidth: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        Text(msg).font(.footnote).foregroundStyle(.red)
            .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("暂无项目").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: - 浮点

    private var pairingMacHostname: String {
        if case .paired(let mac, _) = pairing.state { return mac.hostname }
        return "Mac"
    }
    private var pairingMacHost: String {
        if case .paired(let mac, _) = pairing.state { return "\(mac.host):\(mac.port)" }
        return "—"
    }
    private var isConnected: Bool {
        if case .connected = pairing.link.status { return true }
        return false
    }

    // MARK: - RPC

    @MainActor
    private func loadProjects() async {
        isLoadingProjects = true
        loadError = nil
        if relay.isConfigured {
            do {
                let params = try await relay.fetchProjects()
                projectGroups = Self.parseProjectGroups(params)
                isLoadingProjects = false
                return
            } catch {
                loadError = "公网加载失败: \(error.localizedDescription)"
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
            case .success(let params): projectGroups = Self.parseProjectGroups(params)
            case .failure(let err): loadError = "加载项目失败: \(err.localizedDescription)"
            }
        }
    }

    @MainActor
    private func sendMessage() async {
        let msg = "新指令"
        if relay.isConfigured {
            do { try await relay.send(text: msg); return }
            catch { loadError = "公网发送失败: \(error.localizedDescription)" }
        }
        guard isConnected else { return }
        var p = MobileRemoteLink.Params(); p.set("text", .string(msg))
        pairing.link.request(method: MobileRemoteLink.Method.sendMessage, params: p) { _ in }
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
                        id: sid, title: so["title"]?.stringValue,
                        project: name, projectId: id,
                        updatedAt: so["updatedAt"]?.stringValue)
                }
            }
            return ProjectGroup(id: id, name: name, recentSessions: sessions)
        }
    }
}

// MARK: - 项目卡片 (对齐 Codex 移动端项目行)

struct ProjectCard: View {
    let group: ProjectGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(group.name)
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            if !group.recentSessions.isEmpty {
                Divider().padding(.leading, 62)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.recentSessions) { s in
                        HStack(spacing: 10) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .frame(width: 18)
                            Text(s.title ?? "(无标题)")
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.leading, 62)
                        .padding(.trailing, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }
}

// MARK: - 底部浮动条 (Codex 风格: 搜索 + 语音 + 新建)

struct BottomBar: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("搜索聊天").foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color(.systemBackground), in: Capsule())

            Button {} label: { Image(systemName: "waveform").font(.system(size: 19, weight: .medium)) }
                .frame(width: 42, height: 42)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)

            Button {} label: { Image(systemName: "square.and.pencil").font(.system(size: 19, weight: .medium)) }
                .frame(width: 42, height: 42)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.bottom, 18)
        .background(
            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.9), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

struct ProjectGroup: Identifiable { let id: String; let name: String; let recentSessions: [SessionSummary] }
struct SessionSummary: Identifiable {
    let id: String; let title: String?; let project: String?
    let projectId: String?; let updatedAt: String?
}
