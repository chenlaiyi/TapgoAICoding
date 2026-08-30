import SwiftUI
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

    private var isRunning: Bool {
        thread.turns.last?.status == .running || thread.turns.last?.status == .awaitingApproval
    }

    var body: some View {
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
                store.sendUserMessage(EvolutionWorkspace.kickoffPrompt())
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DSHTheme.brand.opacity(0.08))
        .accessibilityElement(children: .contain)
    }

    private var hintText: String {
        let cwd = thread.cwd.map { " · \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? ""
        let count = thread.turns.count
        let rounds = count == 0 ? "尚未开始" : "已 \(count) 轮"
        return "独立对话、独立开发\(cwd) · \(rounds)"
    }
}
