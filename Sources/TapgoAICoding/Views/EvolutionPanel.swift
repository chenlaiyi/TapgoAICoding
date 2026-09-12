import SwiftUI
import Combine
import TapgoCore

/// 自进化会话的专属引导横幅（对话区顶部，位于消息列表之上）。
///
/// 只在 `thread.isEvolution` 时渲染。它把「独立入口 → 独立对话 →
/// 独立开发」闭环收在一条横幅里：
///   - 说明本会话是什么（独立于普通对话、固定工作在本项目根）；
///   - 「开始自进化」一键发出内置自进化指令，让 AI 独立完成一轮
///     「核对 → 选点 → 实现 → 全量回归 → 版本对齐」的开发循环；
///   - 「自进化日志」仍可查看历史版本记录。
struct EvolutionPanel: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let thread: TapgoCore.Thread
    /// 打开「自进化日志」sheet（sheet 挂在 ChatView 上）。
    let showLog: () -> Void
    @State private var progress: TapgoCore.EvolutionProgress? = nil
    @State private var showDiff = false

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var isRunning: Bool {
        thread.turns.last?.status == .running || thread.turns.last?.status == .awaitingApproval
    }

    /// 从项目根的 evolution/BACKLOG.md 读取顶部未完成项。
    private var topBacklog: TapgoCore.EvolutionBacklogItem? {
        guard let cwd = thread.cwd else { return nil }
        return TapgoCore.EvolutionBacklog.topOpen(projectRoot: URL(fileURLWithPath: cwd))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mainRow
            if let progress, shouldShowProgress(progress) {
                progressRow(progress)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DSHTheme.brand.opacity(0.08))
        .onAppear { refreshProgress() }
        .onReceive(timer) { _ in
            if isRunning || progress?.isActive == true { refreshProgress() }
        }
        .sheet(isPresented: $showDiff) {
            if let cwd = thread.cwd {
                EvolutionDiffSheet(projectRoot: URL(fileURLWithPath: cwd))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DSHTheme.brand.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                    .foregroundStyle(DSHTheme.brand)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("自进化 · 独立开发会话")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).bold())
                Text(hintText)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                showLog()
            } label: {
                Label("自进化日志", systemImage: "clock.arrow.circlepath")
            }
            .controlSize(.small)
            Button {
                showDiff = true
            } label: {
                Label("查看 diff", systemImage: "doc.text.magnifyingglass")
            }
            .controlSize(.small)
            .disabled(thread.cwd == nil)
            .help("查看上一 tag → 当前 HEAD 的改动统计与文件列表")
            Button {
                store.sendUserMessage(EvolutionWorkspace.kickoffPrompt(topBacklogItem: topBacklog))
            } label: {
                Label(isRunning ? "自进化执行中…" : "开始自进化",
                      systemImage: isRunning ? "gearshape.2" : "play.fill")
            }
            .controlSize(.small)
            .buttonStyle(DSHPrimaryButtonStyle())
            .disabled(isRunning)
            .help(isRunning ? "当前自进化回合仍在执行" : "发出自进化指令：核对仓库 → 选定改进点 → 实现 → 全量回归 → 版本对齐")
            .accessibilityLabel(isRunning ? "自进化执行中" : "开始自进化")
        }
    }

    private func shouldShowProgress(_ progress: TapgoCore.EvolutionProgress) -> Bool {
        progress.isActive || progress.status == "failed" || progress.status == "stopped" || progress.phase != "done"
    }

    private func progressRow(_ progress: TapgoCore.EvolutionProgress) -> some View {
        EvolutionProgressStrip(progress: progress, isRunning: isRunning, onStop: requestStop)
    }

    private func progressTint(_ progress: TapgoCore.EvolutionProgress) -> Color {
        switch progress.status {
        case "failed": return .red
        case "stopped": return .orange
        case "done": return .green
        default: return DSHTheme.brand
        }
    }

    private func requestStop() {
        try? TapgoCore.EvolutionProgress.requestStop(stateDirectory: stateDirectory)
        store.cancelTurn(threadID: thread.id)
        refreshProgress()
    }

    private var stateDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tapgo AICoding/state", isDirectory: true)
    }

    private func refreshProgress() {
        progress = TapgoCore.EvolutionProgress.load(stateDirectory: stateDirectory)
    }

    private func usageText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    private var hintText: String {
        let cwd = thread.cwd.map { " · \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? ""
        let count = thread.turns.count
        let rounds = count == 0 ? "尚未开始" : "已 \(count) 轮"
        let next = topBacklog.map { " · 下一项 \($0.id)" } ?? ""
        let usage = thread.usageTotal > 0 ? " · Token \(usageText(thread.usageTotal))" : ""
        let duration = thread.durationTotalText.map { " · 用时 \($0)" } ?? ""
        return "独立对话、独立开发\(cwd) · \(rounds)\(next)\(usage)\(duration)"
    }
}
