import SwiftUI
import TapgoCore

/// ZCode 桌面端对齐(2026-09-11,实据来源:ZCode.app app.asar 渲染层源码):
/// 欢迎页 = 时段问候语标题(六段,边界 5/9/12/14/18/23 点)+「开始在 X 项目
/// 新建任务」副行(项目名可点选)+ 小胶囊建议按钮横排(h-8 / rounded-lg / px-3),
/// 不再是图标 + 大标题 + 四张大卡网格。
struct CodexWelcomeView: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @Environment(\.tapgoFontScale) private var fontScale: AppFontScale
    @State private var choosingProject = false
    var contentWidth: CGFloat = 736

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    Text(Self.greetingText(for: Date()))
                        .font(.system(size: 24 * fontScale.multiplier, weight: .medium))
                        .foregroundStyle(DSHTheme.label)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    projectLine
                        .font(.system(size: 14 * fontScale.multiplier))
                        .foregroundStyle(DSHTheme.labelDim)
                        .multilineTextAlignment(.center)
                    suggestedPromptChips
                        .padding(.top, 10)
                }
                .frame(maxWidth: contentWidth)
                .padding(.horizontal, 28)
                .padding(.top, max(24, geometry.size.height * 0.25))
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 时段问候语(ZCode DQe() 的六段边界与文案)
    static func greetingText(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return "早上好呀，新的一天开始啦"
        case 9..<12: return "上午好呀，有什么想让我帮忙的吗"
        case 12..<14: return "中午好呀，要不要先休息一下"
        case 14..<18: return "下午好呀，接下来交给我吧"
        case 18..<23: return "晚上好呀，今天辛苦啦"
        default: return "夜深啦，别忘了照顾好自己哦"
        }
    }

    // MARK: - 项目副行(项目名可点击切换)
    @ViewBuilder
    private var projectLine: some View {
        if let project = workspace.state.activeProject {
            Button { choosingProject = true } label: {
                (Text("开始在 ") + Text(project.displayName).underline(color: DSHTheme.labelTertiary) + Text(" 项目新建任务"))
                    .lineLimit(2)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $choosingProject) {
                WelcomeProjectPicker { id in
                    choosingProject = false
                    NotificationCenter.default.post(name: .tapgoChooseStarterProject, object: id)
                }
            }
            .accessibilityLabel("在 \(project.displayName) 中开始新任务，点击切换项目")
        } else {
            Text("开始对话")
        }
    }

    // MARK: - 建议按钮(ZCode data-v4-draft-suggested-prompts:h-8 胶囊横排)
    private var suggestedPromptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(SuggestedPrompt.allCases) { prompt in
                    SuggestedPromptChip(prompt: prompt) {
                        NotificationCenter.default.post(name: .tapgoInsertStarter, object: prompt.prompt)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: contentWidth)
    }

    enum SuggestedPrompt: String, CaseIterable, Identifiable {
        case recentCommits, createPdf
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recentCommits: return "检查近 7 天的 commit"
            case .createPdf: return "制作一份 PDF"
            }
        }
        var prompt: String {
            switch self {
            case .recentCommits: return "检查当前工作区近 7 天的 Git commit，概括主要改动并指出潜在风险。"
            case .createPdf: return "根据当前工作区内容制作一份 PDF 文档。"
            }
        }
    }

    private struct SuggestedPromptChip: View {
        let prompt: SuggestedPrompt
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.tapgoFontScale) private var fontScale: AppFontScale

        var body: some View {
            Button(action: action) {
                Text(prompt.label)
                    .font(.system(size: 12 * fontScale.multiplier))
                    .foregroundStyle(DSHTheme.label)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 32 * max(1, fontScale.multiplier))
                    .background(hovering ? DSHTheme.welcomeHover : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(hovering ? DSHTheme.borderStrong : DSHTheme.welcomeBorder, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(prompt.prompt)
            .accessibilityLabel(prompt.label)
            .accessibilityHint("填入输入框，不会自动发送")
        }
    }
}

/// A SwiftUI popover keeps custom labels at their intended size on macOS.
struct WelcomeProjectPicker: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    var onSelect: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择项目").font(.headline).padding(.horizontal, 8)
            ScrollView {
                VStack(spacing: 2) {
                    row("无项目", icon: "folder", selected: workspace.state.activeProjectId == nil) { onSelect(nil) }
                    ForEach(workspace.state.projects.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })) { project in
                        row(project.displayName, icon: project.isRemote ? "globe" : "folder", selected: project.id == workspace.state.activeProjectId) { onSelect(project.id) }
                    }
                }
            }
            .frame(height: min(280, CGFloat(workspace.state.projects.count + 1) * 34))
            Divider()
            row("添加本地目录…", icon: "folder.badge.plus", selected: false) {
                dismiss()
                NotificationCenter.default.post(name: .tapgoRequestOpenLocalFolder, object: nil)
            }
            row("浏览远程目录与更多项目…", icon: "globe", selected: false) {
                dismiss()
                NotificationCenter.default.post(name: .tapgoRequestProjectPicker, object: nil)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func row(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark") }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
