import SwiftUI
import TapgoCore

/// Renders a single `TurnItem` with the right visual style.
struct MessageRow: View {
    let item: TurnItem
    /// True while the turn is still running (streaming). Used to render
    /// reasoning / command blocks as compact single-line views instead of
    /// growing, so repeated output stays minimized.
    var isRunning: Bool = false
    /// Persisted images submitted with the user message. Ignored by every
    /// non-user item, so existing MessageRow call sites stay source-compatible.
    var userImagePaths: [String] = []
    /// When set, the user message bubble shows a bottom action bar with a
    /// timestamp (and reply/edit controls).
    var startedAt: Date? = nil
    var onReply: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil

    var body: some View {
        switch item {
        case .userMessage(_, let text):
            MessageBubble(text: text, role: .user,
                          userImagePaths: userImagePaths,
                          startedAt: startedAt, onReply: onReply, onEdit: onEdit)
        case .assistantMessage(_, let text):
            MessageBubble(text: text, role: .assistant, isStreaming: isRunning)
        case .reasoning(_, let text):
            ReasoningDisclosure(text: text, isRunning: isRunning)
        case .reasoningSummary(_, let text):
            ReasoningDisclosure(text: text, label: L10n.reasoningSummary, icon: "text.quote", isRunning: isRunning)
        case .toolCall(let tc):
            ToolCallRow(toolCall: tc, isRunning: isRunning && tc.status == .running)
        case .commandExecution(let ce):
            CommandExecutionView(execution: ce, isRunning: isRunning && ce.status == .running)
        case .fileChange(let fc):
            FileChangeView(change: fc)
        case .approval(let req):
            ApprovalRow(request: req)
        case .error(_, let message):
            ErrorBubble(message: message)
        }
    }
}

/// A single quiet activity line. Search/read/reason/edit/run replace each
/// other in place; raw commands and tool arguments remain hidden by default.
struct ActivityRollupView: View {
    let activity: TurnActivityRollup
    let turnIsRunning: Bool
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        let display = TurnPresentation.activityDisplay(
            for: activity,
            turnIsRunning: turnIsRunning
        )

        // 合并后的推理 rollup：复用 ReasoningDisclosure 的可展开样式，summaryText
        // 是拼接后的完整正文；运行中保留实时 "正在思考 · …" 提示。
        if display.kind == .reasoning, let summary = display.summaryText, !summary.isEmpty {
            ReasoningDisclosure(
                text: summary,
                label: L10n.reasoning,
                icon: "brain",
                isRunning: display.isRunning
            )
        } else {
            HStack(spacing: 7) {
                if turnIsRunning && activity.isTail && display.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 16, height: 16)
                } else if let icon = display.systemImage {
                    Image(systemName: icon)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .frame(width: 16)
                }
                Text(display.text)
                    .font(AppFont.scaled(.footnote, multiplier: appFontScale.multiplier))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // Codex keeps ordinary work events neutral; color is reserved for a
            // real failure instead of encoding every tool category.
            .foregroundStyle(display.isFailure ? DSHTheme.error : DSHTheme.labelDim)
            .opacity(turnIsRunning && display.isRunning ? 0.92 : 0.66)
            .animation(nil, value: activity.latest.id)
            .accessibilityLabel(display.text)
        }
    }
}

struct MessageBubble: View {
    enum Role { case user, assistant }
    @EnvironmentObject var store: SessionStore
    let text: String
    let role: Role
    var userImagePaths: [String] = []
    var startedAt: Date? = nil
    var onReply: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil
    var isStreaming: Bool = false

    @State private var showEditSheet = false
    @State private var editedText = ""
    @State private var hoveringUser = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Minimal markdown → plain-text strip: drop code fences, emphasis
    /// markers, inline code backticks, links, and image/table syntax so the
    /// copied reply reads cleanly.
    private func stripMarkdown(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "```", with: "")
        let codeBlock = try? NSRegularExpression(pattern: "(?s)```.*?```")
        out = codeBlock?.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "") ?? out
        out = out.replacingOccurrences(of: "`", with: "")
        if let linkRe = try? NSRegularExpression(pattern: "\\[(.*?)\\]\\((.*?)\\)") {
            out = linkRe.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1")
        }
        // Emphasis markers.
        out = out.replacingOccurrences(of: "**", with: "")
        out = out.replacingOccurrences(of: "__", with: "")
        out = out.replacingOccurrences(of: "*", with: "")
        out = out.replacingOccurrences(of: "~~~", with: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if role == .user {
            VStack(alignment: .trailing, spacing: 4) {
                if !userImagePaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(userImagePaths, id: \.self) { path in
                                UserMessageThumbnail(path: path)
                            }
                        }
                    }
                    .frame(maxWidth: 420, alignment: .trailing)
                }
                HStack(alignment: .top) {
                    Spacer(minLength: 32)
                    if text != "(图片)" || userImagePaths.isEmpty {
                        Text(text)
                            .foregroundStyle(DSHTheme.label)
                            // Codex keeps the user bubble airy but quiet: a
                            // hairline outline instead of a heavy raised card,
                            // with padding tuned so multi-line prompts don't
                            // look like a chat sticker.
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                DSHTheme.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(DSHTheme.border, lineWidth: 0.5)
                            )
                            .textSelection(.enabled)
                            .contextMenu {
                                Button {
                                    copy(text)
                                } label: {
                                    Label("复制消息", systemImage: "doc.on.doc")
                                }
                                Button {
                                    store.newThread()
                                    store.sendUserMessage(text)
                                } label: {
                                    Label("以此内容新建会话", systemImage: "plus.message")
                                }
                            }
                    }
                }
                if hoveringUser {
                    userActionBar
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .onHover { hoveringUser = $0 }
            .sheet(isPresented: $showEditSheet) { editSheet }
        } else {
            // Codex keeps assistant output directly on the canvas: no role
            // stripe, avatar, or surrounding card competing with the content.
            MarkdownMessageView(text, isStreaming: isStreaming)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button {
                        copy(text)
                    } label: {
                        Label("复制消息", systemImage: "doc.on.doc")
                    }
                    Button {
                        copy(stripMarkdown(text))
                    } label: {
                        Label("复制为纯文本", systemImage: "text.alignleft")
                    }
                }
        }
    }

    /// Hover-only actions for the user's question. Time remains available as
    /// a tooltip instead of taking permanent space under every message.
    @ViewBuilder
    private var userActionBar: some View {
        HStack(spacing: 12) {
            if let onReply {
                Button(action: onReply) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("重发此问题")
                .accessibilityLabel("重发此问题")
            }
            if onEdit != nil {
                Button {
                    editedText = text
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("编辑并重发")
                .accessibilityLabel("编辑并重发")
            }
            Button {
                copy(text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("复制")
            .accessibilityLabel("复制")
        }
        .font(.system(size: 13))
        .padding(.trailing, 2)
        .help(startedAt.map { "发送于 \(timeText($0))" } ?? "消息操作")
    }

    private var editSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑并重发").font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
            TextEditor(text: $editedText)
                .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                .frame(minHeight: 96, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DSHTheme.border, lineWidth: 1))
                .padding(6)
            HStack {
                Spacer()
                Button("取消") { showEditSheet = false }
                Button("重发") {
                    let t = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { onEdit?(t) }
                    showEditSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct UserMessageThumbnail: View {
    let path: String
    @State private var showPreview = false

    var body: some View {
        Group {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("已发送图片 \(URL(fileURLWithPath: path).lastPathComponent)")
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("图片不可用")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 180, height: 120)
        .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DSHTheme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        // 点击缩略图弹出大图预览；双击则在 Finder 中显示原文件。
        .onTapGesture { showPreview = true }
        .help("点击查看大图")
        .sheet(isPresented: $showPreview) {
            ImagePreviewSheet(path: path)
        }
    }
}

/// 大图预览：居中放大原图，Esc / 点击背景关闭。
private struct ImagePreviewSheet: View {
    let path: String

    var body: some View {
        ZStack {
            // 半透明深色背景，点击关闭
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 12) {
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 720, maxHeight: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                } else {
                    Label("图片不可用", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.white)
                        .padding(40)
                }
                HStack(spacing: 8) {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: path)]
                        )
                        dismiss()
                    } label: {
                        Label("在访达中显示", systemImage: "folder")
                    }
                    .controlSize(.small)
                    Button("关闭") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    @Environment(\.dismiss) private var dismiss
}

/// 思考过程：默认折起成一行（带字符数提示），点击展开完整正文。连续多次
/// `reasoning` / `reasoningSummary` 由 `TurnPresentation` 合并到同一个
/// `ReasoningDisclosure`，正文是换行拼接的总和，避免出现多行灰色 log。
struct ReasoningDisclosure: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let text: String
    var label: String = L10n.reasoning
    var icon: String = "brain"
    var isRunning: Bool = false
    /// `TurnPresentation` 聚合多段思考后传进来的总字符数；为 0 时回退到
    /// `text.count`，避免空字符串时显示 "0 字符"。
    var summaryCharCount: Int = 0

    @State private var isExpanded = false

    private var displayText: String {
        text.isEmpty ? (isRunning ? "思考中…" : label) : text
    }

    private var totalChars: Int {
        summaryCharCount > 0 ? summaryCharCount : text.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard !text.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: icon)
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .frame(width: 16)
                    }
                    Text(displayText)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if totalChars > 0 && !text.isEmpty {
                        Text("· \(totalChars) 字符")
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(DSHTheme.labelTertiary)
                    }
                    Spacer(minLength: 0)
                    if !text.isEmpty {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(DSHTheme.labelTertiary)
                            .frame(width: 14)
                    }
                }
                .foregroundStyle(DSHTheme.labelTertiary)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "折叠思考过程" : "展开思考过程")
            .accessibilityLabel(isExpanded ? "折叠思考过程" : "展开思考过程")

            if isExpanded && !text.isEmpty {
                Text(text)
                    .font(AppFont.scaled(.footnote, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 23) // 与图标列对齐
                    .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ToolCallRow: View {
    let toolCall: ToolCall
    var isRunning: Bool = false
    @State private var isExpanded = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Flat, neutral process row. Only real failures use a state color;
            // arguments and output remain inspectable on demand.
            HStack(spacing: 6) {
                Image(systemName: toolIcon)
                    .foregroundStyle(toolIconColor)
                Text(toolCall.name)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
                Text("·")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                Text(toolCall.arguments)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isRunning {
                    ProgressView().controlSize(.mini)
                }
                if toolCall.status != .succeeded {
                    StatusBadge(status: toolCall.status.rawValue)
                }
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "折叠结果" : "展开结果")
            }
            .padding(.vertical, 3)

            if isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    Text(toolCall.arguments)
                        .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                    if let r = toolCall.result, !r.isEmpty {
                        Text(r)
                            .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(DSHTheme.border, lineWidth: 1))
            }
        }
    }

    private var toolIcon: String {
        switch toolCall.name.lowercased() {
        case "read", "readfile": return "doc.text"
        case "edit", "write", "writefile": return "pencil"
        case "shell", "bash", "command", "run": return "terminal"
        case "watch", "grep", "search": return "magnifyingglass"
        case "list", "ls": return "list.bullet"
        default: return "wrench.adjustable"
        }
    }
    private var toolIconColor: Color {
        switch toolCall.status {
        case .failed, .denied: return DSHTheme.error
        default: return DSHTheme.labelTertiary
        }
    }
}

/// 状态徽章：Codex 用一个不抢戏的小色点 + 文字即可，避免每个工具行都像
/// 一个贴纸；色点饱和度低，文字保持二级标签色，仅 `failed` 时上提对比度。
struct StatusBadge: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let status: String
    var body: some View {
        let (label, icon, color, accent): (String, String, Color, Color) = {
            switch status {
            case "succeeded":      return ("完成",  "checkmark",         .secondary, DSHTheme.success)
            case "failed":         return ("失败",  "xmark",             DSHTheme.error, DSHTheme.error)
            case "denied":         return ("已拒绝", "hand.raised.slash", DSHTheme.error, DSHTheme.error)
            case "running":        return ("运行中", "gearshape.2",      .secondary, DSHTheme.brand)
            case "awaitingApproval": return ("待批准", "hand.raised",    .secondary, DSHTheme.warn)
            default:               return ("待执行", "clock",            .secondary, .secondary)
            }
        }()
        return HStack(spacing: 4) {
            // 5pt 色点，仅在失败时使用红色，普通状态用品牌色/灰色，让
            // 大段连续工具行不会被一排彩色徽章淹没。
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
            Text(label)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(color)
                .accessibilityLabel(label)
            // icon 仍然保留，让屏幕阅读器可以拿到语义。
            Image(systemName: icon)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        // 失败徽章上提一档底色，普通徽章只描边不填色，避免视觉污染。
        .background(
            accent.opacity(status == "failed" || status == "denied" ? 0.10 : 0),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(accent.opacity(0.25), lineWidth: 0.5)
        )
    }
}

struct ErrorBubble: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .padding(8)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
    }
}
