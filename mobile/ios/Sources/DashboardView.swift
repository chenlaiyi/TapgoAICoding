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
                        NavigationLink {
                            SessionDetailView(threadId: s.id, projectName: group.name, sessionTitle: s.title)
                        } label: {
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
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.leading, 62).padding(.trailing, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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


// MARK: - 会话详情 (v1.0.8 对齐 Codex 移动端对话页)

struct SessionDetailView: View {
    let threadId: String
    let projectName: String?
    let sessionTitle: String?
    @EnvironmentObject var pairing: PairingStore
    @StateObject private var relay = RelayLink()
    @State private var newMessage: String = ""
    @State private var elapsed: Int = 0     // 模拟运行秒数
    @State private var expandedTool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    ForEach(Self.mockTurns) { turn in
                        if turn.role == .user {
                            userBubble(turn.text)
                        } else {
                            aiBlock(turn)
                        }
                    }
                    runningStatusBlock
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 100)
            }
            inputBar
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(projectName ?? "默认项目").font(.caption2).foregroundStyle(.secondary)
                    Text(sessionTitle ?? "会话").font(.subheadline.weight(.medium)).lineLimit(1)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {} label: { Label("复制全部", systemImage: "doc.on.doc") }
                    Button {} label: { Label("分享", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {} label: { Label("删除会话", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { tick() }
    }

    // MARK: - 标题

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("正在运行").font(.caption2).foregroundStyle(.red)
            }
            Text(sessionTitle ?? "会话").font(.title2.weight(.semibold))
            Text("\(projectName ?? "默认项目") · JKMacMini")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Image(systemName: "doc.on.doc").font(.system(size: 18)).foregroundStyle(.secondary)
                Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(.secondary)
                Spacer()
            }.padding(.top, 6)
        }
    }

    // MARK: - 气泡

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.accentColor))
        }
    }

    private func aiBlock(_ turn: MockTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(turn.text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, para in
                Text(para)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            HStack(spacing: 22) {
                Image(systemName: "hand.thumbsup").font(.system(size: 14)).foregroundStyle(.tertiary)
                Image(systemName: "hand.thumbsdown").font(.system(size: 14)).foregroundStyle(.tertiary)
                Image(systemName: "doc.on.doc").font(.system(size: 14)).foregroundStyle(.tertiary)
                Image(systemName: "square.and.arrow.up").font(.system(size: 14)).foregroundStyle(.tertiary)
            }.padding(.top, 4)
        }
    }

    // MARK: - 状态行 (Codex 风格: 计时器 + 工具调用展开 + 思考)

    private var runningStatusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary)
                Text("已运行 \(formatTime(elapsed))").font(.caption).foregroundStyle(.secondary)
            }
            Button { expandedTool.toggle() } label: {
                HStack {
                    Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                    Text(expandedTool
                         ? "已浏览 4 个文件, 执行了 6 次搜索、1 次列表…"
                         : "已浏览 4 个文件, 执行了 6 次搜索…")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expandedTool ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 6) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                Text("正在思考").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 4)
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 底部粘性输入栏

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                HStack {
                    TextField("跟 Tapgo AICoding 继续…", text: $newMessage, axis: .vertical)
                        .lineLimit(1...4)
                    Spacer(minLength: 6)
                    Image(systemName: "mic.fill").font(.system(size: 16)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: Capsule())
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - helpers

    private func formatTime(_ s: Int) -> String {
        String(format: "%d 分 %d 秒", s/60, s%60)
    }
    private func tick() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            elapsed += 1
        }
    }
    private func send() async {
        let msg = newMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        if relay.isConfigured { try? await relay.send(text: msg) }
        newMessage = ""
    }

    // MARK: - Mock 数据 (下个版本接 /api/native/session/<id>)

    fileprivate struct MockTurn: Identifiable {
        fileprivate enum Role { case user, ai }
        let id = UUID()
        let role: Role
        let text: String
    }

    fileprivate static let mockTurns: [MockTurn] = [
        MockTurn(role: .user, text: "查询 88012088 实时数据"),
        MockTurn(role: .ai, text: """
你好,目前这台设备在小程序端无法使用起来 4000L 券。

券有效且未使用,但设备仍为时长套餐,系统限制"流量券仅适用于流量套餐设备"。

需要先将设备成功切换为流量套餐并回读确认,用户才能使用;此前后台切换未成功。
"""),
        MockTurn(role: .user, text: "请你问管理员能否增加这个套餐切换的开关功能"),
        MockTurn(role: .ai, text: """
我先核对远程 main 和现有套餐切换逻辑,在管理后台增加切换入口及确认结果展示,并完成针对性验证。

发现关键原因:旧的计费模式切换指令已被七云废弃,所以此前后台操作没有真正切换。我会把入口做成明确的套餐选择与确认,并采用保留滤芯寿命和现有额度的主板同步流程;只有主板回读一致才显示成功。
""")
    ]
}
