import SwiftUI
import TapgoCore

/// Codex Desktop 新对话欢迎页(2026-09-11,实据来源:用户截屏):
/// 顶部居中八角形 Codex Logo + 大标题「你想让我们在 <项目> 中构建什么?」
/// (项目名下划线虚线,可点选切换)+ 四张建议卡(探索/构建/审查/修复,横排),
/// 删掉旧 ZCode 时段问候语 + 项目副行 + 胶囊横排的旧形态。
///
/// 交互:点建议卡 → 通过 `tapgoInsertStarter` 把 prompt 注入 ChatView 的
/// composer 输入框(沿用现有「填草稿、不发送」的语义,避免误发)。
struct CodexWelcomeView: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @Environment(\.tapgoFontScale) private var fontScale: AppFontScale
    @State private var choosingProject = false
    var contentWidth: CGFloat = 736

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    codexMark
                    title
                    suggestedCards
                        .padding(.top, 6)
                }
                .frame(maxWidth: contentWidth)
                .padding(.horizontal, 28)
                .padding(.top, max(28, geometry.size.height * 0.22))
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Codex 八角形 logo
    // 2026-09-11 实据截屏:深色细线八角章 + 内部一道下划线,呼应 `_` 字符。
    // 这里用 Canvas 画一个等价的几何符号,避免依赖外部资源;尺寸与描边
    // 粗细按截屏比例估读(章外径 ~44pt,边线 1.4pt,内线 1.4pt)。
    private var codexMark: some View {
        CodexWelcomeMark()
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }

    // MARK: - 标题(项目名下划线虚线 + 可点击切换)
    @ViewBuilder
    private var title: some View {
        if let project = workspace.state.activeProject {
            Button { choosingProject = true } label: {
                (Text("你想让我们在 ")
                 + Text(project.displayName)
                     .underline(pattern: .dot, color: DSHTheme.labelTertiary)
                 + Text(" 中构建什么?"))
                    .font(.system(size: 22 * fontScale.multiplier, weight: .regular))
                    .foregroundStyle(DSHTheme.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $choosingProject) {
                WelcomeProjectPicker { id in
                    choosingProject = false
                    NotificationCenter.default.post(name: .tapgoChooseStarterProject, object: id)
                }
            }
            .accessibilityLabel("在 \(project.displayName) 中构建什么,点击切换项目")
        } else {
            Text("你想让我们构建什么?")
                .font(.system(size: 22 * fontScale.multiplier, weight: .regular))
                .foregroundStyle(DSHTheme.label)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 四张建议卡
    private var suggestedCards: some View {
        // 截屏里 4 张卡横排,每张等宽;用 Grid 保证列宽一致,父容器限定
        // contentWidth,Grid 自动均分。
        Grid(horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                ForEach(SuggestedPrompt.allCases) { prompt in
                    SuggestedPromptCard(prompt: prompt) {
                        NotificationCenter.default.post(name: .tapgoInsertStarter, object: prompt.prompt)
                    }
                }
            }
        }
    }

    enum SuggestedPrompt: String, CaseIterable, Identifiable {
        case explore, build, review, fix
        var id: String { rawValue }
        var label: String {
            switch self {
            case .explore: return "探索并理解代码"
            case .build: return "构建新功能、应用或工具"
            case .review: return "审查代码并提出修改建议"
            case .fix: return "修复问题和失败"
            }
        }
        /// 点卡填入 composer 的草稿。措辞保持中文,与截屏 4 类意图一致。
        var prompt: String {
            switch self {
            case .explore: return "请先通读当前工作区,把模块划分、关键数据流和潜在风险整理一份导览,过程中如果需要查文件或命令请直接动手。"
            case .build: return "我要在当前工作区里做一个新功能或新工具。请先和我确认目标与边界,再列出实现步骤和受影响文件,然后开始动手。"
            case .review: return "请把当前工作区最近一次修改当作一次代码审查目标:挑出真正会影响正确性、可维护性或性能的问题,给出可执行的修改建议。"
            case .fix: return "当前工作区有报错或测试失败,请按现象定位根因,给出修复方案并直接动手改;改完跑相关测试确认没回归。"
            }
        }
    }

    private struct SuggestedPromptCard: View {
        let prompt: SuggestedPrompt
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.tapgoFontScale) private var fontScale: AppFontScale

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: prompt.symbol)
                        .font(.system(size: 18 * fontScale.multiplier, weight: .regular))
                        .foregroundStyle(prompt.tint)
                        .symbolRenderingMode(.hierarchical)
                    Text(prompt.label)
                        .font(.system(size: 13 * fontScale.multiplier, weight: .regular))
                        .foregroundStyle(DSHTheme.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .background(hovering ? DSHTheme.welcomeHover : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(hovering ? DSHTheme.borderStrong : DSHTheme.welcomeBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(prompt.prompt)
            .accessibilityLabel(prompt.label)
            .accessibilityHint("填入输入框,不会自动发送")
        }
    }
}

private extension CodexWelcomeView.SuggestedPrompt {
    /// 截屏里 4 类意图的图标 + hierarchical 着色。SF Symbol 选形
    /// 优先取本机 macOS 已有的 multi-color symbol。
    var symbol: String {
        switch self {
        case .explore: return "sparkle.magnifyingglass"
        case .build: return "hammer.fill"
        case .review: return "arrow.triangle.2.circlepath"
        case .fix: return "life.preserver"
        }
    }

    var tint: Color {
        switch self {
        case .explore: return DSHTheme.brandBlueAccent
        case .build: return DSHTheme.brandPurpleAccent
        case .review: return DSHTheme.success
        case .fix: return DSHTheme.warn
        }
    }
}

/// 顶部居中八角形 Codex Logo。Canvas 自绘:8 个顶点等角分布的圆角
/// 八边形 + 中心一道短横(代表截屏里的 `_` 字符)。
private struct CodexWelcomeMark: View {
    var body: some View {
        Canvas { ctx, size in
            let lineWidth: CGFloat = 1.4
            let inset = lineWidth / 2
            let rect = CGRect(x: inset, y: inset, width: size.width - lineWidth, height: size.height - lineWidth)
            let path = regularOctagonPath(in: rect)
            ctx.stroke(path, with: .color(DSHTheme.label.opacity(0.9)), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            // 中央下划线(短横),代表截屏里的 `_`。
            let midY = rect.midY
            let lineLen = rect.width * 0.20
            let underline = Path { p in
                p.move(to: CGPoint(x: rect.midX - lineLen, y: midY))
                p.addLine(to: CGPoint(x: rect.midX + lineLen, y: midY))
            }
            ctx.stroke(underline, with: .color(DSHTheme.label.opacity(0.9)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }

    /// 等角对称八边形(8 段等长边,顶点按 22.5° + 45°k 排布)。
    private func regularOctagonPath(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        var path = Path()
        // 起点偏移 22.5°(-π/8),让顶/底/左/右四段成为长边,符合截屏视觉。
        let startAngle: Double = -.pi / 8
        let step: Double = .pi / 4
        for i in 0..<8 {
            let angle = startAngle + step * Double(i)
            let x = cx + rx * Foundation.cos(angle)
            let y = cy + ry * Foundation.sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
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
