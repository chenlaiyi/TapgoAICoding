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


// MARK: - 会话详情 (v1.0.9 对齐 Codex 移动端: 文件改动标签 + stats 卡片 + 时间戳 + 互动图标)

struct SessionDetailView: View {
    let threadId: String
    let projectName: String?
    let sessionTitle: String?
    @EnvironmentObject var pairing: PairingStore
    @StateObject private var relay = RelayLink()
    @State private var newMessage: String = ""
    @State private var elapsed: Int = 0
    @State private var expandedTool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    ForEach(Self.mockTurns) { turn in
                        if turn.role == .user { userBubble(turn.text) }
                        else { aiBlock(turn) }
                    }
                    Spacer().frame(height: 8)
                    statsCard                       // 项目级 diff 摘要
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 110)
            }
            .task { await loadModels() }
            .sheet(isPresented: $showModelSheet) { modelSheet }
            inputBar
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await tick() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(sessionTitle ?? "会话").font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(projectName ?? "默认项目") · JKMacMini").font(.caption2).foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                Button {} label: { Image(systemName: "square.and.pencil").font(.system(size: 15)) }
                Menu {} label: { Image(systemName: "ellipsis.circle").font(.system(size: 17)) }
            }
        }
    }

    // MARK: - 标题 / 计时

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sessionTitle ?? "会话").font(.title2.weight(.semibold))
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.caption).foregroundStyle(.secondary)
                Text("用时 \(formatTime(elapsed))").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 用户气泡

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

    // MARK: - AI 卡片 (带文件改动标签 + 互动图标 + 时间戳)

    private func aiBlock(_ turn: MockTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 文件改动标签 (Codex 风格)
            HStack(spacing: 6) {
                Text("已更新 1 个文件")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color(.tertiarySystemBackground)))
                Text("+97")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Text("-0")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.red)
            }
            if !turn.filePath.isEmpty {
                Text(turn.filePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // 正文
            ForEach(Array(turn.text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, para in
                Text(para)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            // 时间戳
            Text(turn.timestamp).font(.caption2).foregroundStyle(.tertiary)
            // 互动图标
            HStack(spacing: 20) {
                Image(systemName: "doc.on.doc").font(.system(size: 14)).foregroundStyle(.tertiary)
                Image(systemName: "hand.thumbsup").font(.system(size: 14)).foregroundStyle(.tertiary)
                Image(systemName: "hand.thumbsdown").font(.system(size: 14)).foregroundStyle(.tertiary)
                Image(systemName: "square.and.arrow.up").font(.system(size: 14)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 项目级 stats 摘要卡片 (粘在输入栏上方)

    private var statsCard: some View {
        HStack(spacing: 12) {
            Text("648 个文件").font(.caption)
            HStack(spacing: 6) {
                Text("+2万").font(.caption.weight(.semibold)).foregroundStyle(.green)
                Text("-2626").font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Capsule().fill(Color(.tertiarySystemBackground)))
    }

    // MARK: - 模型选择 (Codex 移动端核心)

    @State private var currentModel: String = ""
    @State private var modelOptions: [ModelOption] = []
    @State private var showModelSheet = false

    private var modelPicker: some View {
        Button {
            showModelSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkle").font(.caption2)
                Text(currentModel.isEmpty ? "选择模型" : currentModel)
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color(.tertiarySystemBackground)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .task { await loadModels() }
        .sheet(isPresented: $showModelSheet) { modelSheet }
    }

    private func loadModels() async {
        guard relay.isConfigured else { return }
        do {
            let s = try await relay.fetchState()
            currentModel = s.current
            modelOptions = s.options
        } catch {}
    }

    private func pickModel(_ m: ModelOption) async {
        do {
            try await relay.selectModel(providerId: m.providerId, modelId: m.modelId)
            currentModel = m.modelName
            for i in modelOptions.indices {
                if modelOptions[i].id == m.id { modelOptions[i].selected = true }
                else { modelOptions[i].selected = false }
            }
            showModelSheet = false
        } catch {
            currentModel = "切换失败"
        }
    }

    private var modelSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(modelOptions) { m in
                        Button(action: { Task { await pickModel(m) } }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.modelName).font(.system(size: 15, weight: .medium))
                                    Text(m.providerName).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if m.selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                if !m.configured { Text("未配置").font(.caption2).foregroundStyle(.tertiary) }
                            }
                            .padding(.vertical, 10).padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .disabled(!m.configured)
                        Divider()
                    }
                }
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showModelSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

        // MARK: - 输入栏 (Codex 风格: + / "在 X 上工作" / 麦克风 / 发送)

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button {} label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                // 模型 chip 内嵌在输入框左侧 (Codex 移动端风格)
                Button { showModelSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle").font(.system(size: 10, weight: .semibold))
                        Text(currentModel.isEmpty ? "选择模型" : shortModel(currentModel))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                HStack {
                    TextField("在 \(projectName ?? "Mac") 上工作", text: $newMessage, axis: .vertical)
                        .lineLimit(1...3)
                    Spacer(minLength: 6)
                    Image(systemName: "mic.fill").font(.system(size: 16)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: Capsule())
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold))
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

    /// 把"智谱 GLM-5.3-Flash"压缩为"GLM-5.3-Flash"等短名, 避免输入框拥挤。
    private func shortModel(_ s: String) -> String {
        if let i = s.firstIndex(of: " ") { return String(s[s.index(after: i)...]) }
        return s
    }

    private func formatTime(_ s: Int) -> String { String(format: "%d 分 %d 秒", s/60, s%60) }
    private func tick() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            elapsed += 1
        }
    }
    private func send() async {
        let msg = newMessage.trimmingCharacters(in: .whitespaces); guard !msg.isEmpty else { return }
        if relay.isConfigured { try? await relay.send(text: msg) }
        newMessage = ""
    }

    fileprivate struct MockTurn: Identifiable {
        fileprivate enum Role { case user, ai }
        let id = UUID()
        let role: Role
        let text: String
        let filePath: String
        let timestamp: String
    }

    // MARK: - Mock 数据 (下个版本接 /api/native/session/<id>)


    fileprivate static let mockTurns: [MockTurn] = [
        MockTurn(role: .user, text: "戴丽萍的也是测试机,从表里删除", filePath: "", timestamp: "星期三 13:01"),
        MockTurn(role: .ai, text: "已从 Excel 删除戴丽萍的 88035235,现剩 17 台,其条资料已核对并保持一致。\n\n本次仅修改表格,生产台账未变动。", filePath: "/Users/chanlaiyi/YTB/outputs/01a07ea7-44e4-7ba0-a2e2-0427f8501f8a/build-active18.mjs", timestamp: "星期三 13:01")
    ]
}
