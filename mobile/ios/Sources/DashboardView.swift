import SwiftUI

/// 已配对后的工作面板。
///
/// v1.0.0 起:
/// - 显示已配对 Mac 元信息 + 长链接实时状态 (PairingLink.status)
/// - 提供"切项目""发送消息""最近会话"三类 P5 信息流入口 (走 JSON-RPC over TCP)
/// - 提供"取消配对""停止连接"两个状态变更动作
struct DashboardView: View {
    @EnvironmentObject var pairing: PairingStore
    @State private var sessionList: [SessionSummary] = []
    @State private var sessionListError: String?
    @State private var switchingProject = false
    @State private var newMessage: String = ""
    @State private var sendingMessage = false
    @State private var lastSentEcho: String?

    var body: some View {
        NavigationStack {
            List {
                macSection
                connectionSection
                actionsSection
                sessionsSection
            }
            .navigationTitle("点点够终端")
            .task { await refreshSessions() }
        }
    }

    // MARK: - Mac 元信息

    private var macSection: some View {
        Section("已配对 Mac") {
            if case .paired(let mac, _) = pairing.state {
                LabeledContent("设备 ID", value: mac.deviceId)
                LabeledContent("主机名", value: mac.hostname)
                LabeledContent("主机", value: mac.host)
                LabeledContent("端口", value: String(mac.port))
                LabeledContent("配对时间",
                               value: mac.pairedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    // MARK: - 连接状态

    private var connectionSection: some View {
        Section("连接状态") {
            HStack(spacing: 8) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 10, height: 10)
                Text(connectionText)
                    .font(.subheadline)
            }
            if let err = pairing.link.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Button("停止连接") { pairing.stopLink() }
                    .buttonStyle(.bordered)
                    .disabled(!isConnected)
                Button("取消配对", role: .destructive) { pairing.unpair() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - P5 信息流入口

    private var actionsSection: some View {
        Section("快捷动作") {
            HStack {
                Button {
                    Task { await switchProject() }
                } label: {
                    Label("切项目", systemImage: "folder.fill.badge.plus")
                }
                .disabled(!isConnected || switchingProject)
                Spacer()
                if switchingProject { ProgressView() }
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("发送消息给 Mac 当前会话…", text: $newMessage, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isConnected || sendingMessage)
                HStack {
                    Spacer()
                    Button {
                        Task { await sendMessage() }
                    } label: {
                        if sendingMessage {
                            ProgressView()
                        } else {
                            Label("发送", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isConnected || newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let echo = lastSentEcho {
                    Text(echo).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 最近会话

    private var sessionsSection: some View {
        Section("最近会话 (Mac 端)") {
            if let err = sessionListError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
            if sessionList.isEmpty && isConnected && sessionListError == nil {
                HStack {
                    ProgressView()
                    Text("加载中…").foregroundStyle(.secondary)
                }
            }
            ForEach(sessionList, id: \.id) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title ?? "(无标题)").font(.headline)
                    Text("\(s.project ?? "默认项目") · \(s.updatedAt ?? "未知时间")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await refreshSessions() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(!isConnected)
        }
    }

    // MARK: - Helpers

    private var isConnected: Bool {
        if case .connected = pairing.link.status { return true }
        return false
    }

    private var connectionColor: Color {
        switch pairing.link.status {
        case .connected: return .green
        case .connecting, .discovering: return .orange
        case .failed: return .red
        case .idle: return .gray
        }
    }

    private var connectionText: String {
        switch pairing.link.status {
        case .idle: return "未启用长链接"
        case .discovering: return "Bonjour 搜索中…"
        case .connecting(let hp): return "连接中…\(hp)"
        case .connected(let hp): return "已连接 · \(hp)"
        case .failed(let msg): return "异常 · \(msg)"
        }
    }

    // MARK: - JSON-RPC calls (P5 信息流)

    @MainActor
    private func refreshSessions() async {
        guard isConnected else {
            sessionList = []
            return
        }
        sessionListError = nil
        pairing.link.request(method: MobileRemoteLink.Method.listSessions) { result in
            switch result {
            case .success(let params):
                sessionList = parseSessionList(params)
            case .failure(let err):
                sessionListError = "加载会话失败: \(err.localizedDescription)"
            }
        }
    }

    @MainActor
    private func switchProject() async {
        switchingProject = true
        defer { switchingProject = false }
        var p = MobileRemoteLink.Params()
        p.set("path", .string("/Users/chanlaiyi/TapgoAICoding"))
        pairing.link.request(method: MobileRemoteLink.Method.switchProject, params: p) { result in
            switch result {
            case .success: lastSentEcho = "已请求切项目"
            case .failure(let err): lastSentEcho = "切项目失败: \(err.localizedDescription)"
            }
        }
    }

    @MainActor
    private func sendMessage() async {
        let msg = newMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        sendingMessage = true
        defer { sendingMessage = false }
        var p = MobileRemoteLink.Params()
        p.set("text", .string(msg))
        pairing.link.request(method: MobileRemoteLink.Method.sendMessage, params: p) { result in
            switch result {
            case .success:
                lastSentEcho = "已发送: \(msg.prefix(40))"
                newMessage = ""
            case .failure(let err):
                lastSentEcho = "发送失败: \(err.localizedDescription)"
            }
        }
    }

    private func parseSessionList(_ params: MobileRemoteLink.Params) -> [SessionSummary] {
        guard case .array(let arr) = params["sessions"] else { return [] }
        return arr.compactMap { v -> SessionSummary? in
            guard case .object(let obj) = v else { return nil }
            return SessionSummary(
                id: obj["id"]?.stringValue ?? UUID().uuidString,
                title: obj["title"]?.stringValue,
                project: obj["project"]?.stringValue,
                updatedAt: obj["updatedAt"]?.stringValue
            )
        }
    }
}

struct SessionSummary: Identifiable {
    let id: String
    let title: String?
    let project: String?
    let updatedAt: String?
}
