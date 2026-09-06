import SwiftUI
import TapgoCore

/// The supplied Codex reference: one calm heading, four editable task starters,
/// and generous open space above the bottom-anchored composer.
struct CodexWelcomeView: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @Environment(\.tapgoFontScale) private var fontScale: AppFontScale
    @State private var choosingProject = false
    var contentWidth: CGFloat = 736

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    Image(systemName: "terminal")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(DSHTheme.labelTertiary)
                        .accessibilityHidden(true)
                    heading
                        .font(.system(size: 27 * fontScale.multiplier, weight: .regular))
                        .foregroundStyle(DSHTheme.label)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: geometry.size.width >= 650 ? 4 : 2), spacing: 10) {
                        ForEach(Starter.allCases) { starter in
                            StarterCard(starter: starter) {
                                NotificationCenter.default.post(name: .tapgoInsertStarter, object: starter.prompt)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: contentWidth)
                .padding(.horizontal, 28)
                .padding(.top, max(24, geometry.size.height * 0.25))
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var heading: some View {
        if let project = workspace.state.activeProject {
            Button { choosingProject = true } label: {
                (Text("我们应该在 ") + Text(project.displayName).underline(color: DSHTheme.labelTertiary) + Text(" 中做些什么？"))
                    .font(.system(size: 27 * fontScale.multiplier, weight: .regular))
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
            Text("我们应该做些什么？")
        }
    }

    enum Starter: String, CaseIterable, Identifiable {
        case explore, build, review, fix
        var id: String { rawValue }
        var title: String {
            switch self {
            case .explore: return "探索并理解代码"
            case .build: return "构建新功能、应用或工具"
            case .review: return "审查代码并提出修改建议"
            case .fix: return "修复问题和失败"
            }
        }
        var icon: String {
            switch self {
            case .explore: return "binoculars"
            case .build: return "hammer"
            case .review: return "arrow.triangle.2.circlepath"
            case .fix: return "ladybug"
            }
        }
        var color: Color {
            switch self {
            case .explore: return .blue
            case .build: return .purple
            case .review: return .green
            case .fix: return .orange
            }
        }
        var prompt: String {
            switch self {
            case .explore: return "请探索当前项目的代码，说明整体结构、关键模块与运行方式。"
            case .build: return "请帮我在当前项目中构建一个新功能："
            case .review: return "请审查当前项目的改动，指出具体问题、影响与修改建议。"
            case .fix: return "请帮我定位并修复这个问题："
            }
        }
    }

    private struct StarterCard: View {
        let starter: Starter
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.tapgoFontScale) private var fontScale: AppFontScale

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: starter.icon)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(starter.color)
                    Spacer(minLength: 0)
                    Text(starter.title)
                        .font(.system(size: 13 * fontScale.multiplier, weight: .medium))
                        .foregroundStyle(DSHTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 106 * max(1, fontScale.multiplier), maxHeight: 106 * max(1, fontScale.multiplier))
                .background(hovering ? DSHTheme.welcomeHover : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(hovering ? DSHTheme.borderStrong : DSHTheme.welcomeBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("填入任务草稿，编辑后发送")
            .accessibilityLabel(starter.title)
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
