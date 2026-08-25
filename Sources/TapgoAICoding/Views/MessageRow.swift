import SwiftUI
import TapgoCore

/// Renders a single `TurnItem` with the right visual style.
struct MessageRow: View {
    let item: TurnItem
    /// True while the turn is still running (streaming). Used to render
    /// reasoning / command blocks as compact single-line views instead of
    /// growing, so repeated output stays minimized.
    var isRunning: Bool = false
    /// When set, the user message bubble shows a bottom action bar with a
    /// timestamp (and reply/edit controls).
    var startedAt: Date? = nil
    var onReply: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil

    var body: some View {
        switch item {
        case .userMessage(_, let text):
            MessageBubble(text: text, role: .user,
                          startedAt: startedAt, onReply: onReply, onEdit: onEdit)
        case .assistantMessage(_, let text):
            MessageBubble(text: text, role: .assistant)
        case .reasoning(_, let text):
            ReasoningDisclosure(text: text, isRunning: isRunning)
        case .reasoningSummary(_, let text):
            ReasoningDisclosure(text: text, label: L10n.reasoningSummary, icon: "text.quote", isRunning: isRunning)
        case .toolCall(let tc):
            ToolCallRow(toolCall: tc, isRunning: isRunning)
        case .commandExecution(let ce):
            CommandExecutionView(execution: ce, isRunning: isRunning)
        case .fileChange(let fc):
            FileChangeView(change: fc)
        case .approval(let req):
            ApprovalRow(request: req)
        case .error(_, let message):
            ErrorBubble(message: message)
        }
    }
}

struct MessageBubble: View {
    enum Role { case user, assistant }
    @EnvironmentObject var store: SessionStore
    let text: String
    let role: Role
    var startedAt: Date? = nil
    var onReply: (() -> Void)? = nil
    var onEdit: ((String) -> Void)? = nil

    @State private var showEditSheet = false
    @State private var editedText = ""

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
                HStack(alignment: .top) {
                    Spacer(minLength: 32)
                    Text(text)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            DSHTheme.brand,
                            in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
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
                userActionBar
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .sheet(isPresented: $showEditSheet) { editSheet }
        } else {
            // Assistant replies render as plain markdown text on the chat
            // background (like Codex) — no full-width card, so there's no
            // wasted space on the right. Copy lives in the context menu.
            HStack {
                HStack(alignment: .top, spacing: 6) {
                    MarkdownMessageView(text)
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
                Spacer(minLength: 1)
            }
        }
    }

    /// Bottom action bar for the user's question: timestamp + reply + edit +
    /// copy, mirroring the composer-adjacent quick actions.
    @ViewBuilder
    private var userActionBar: some View {
        HStack(spacing: 12) {
            if let startedAt {
                Text(timeText(startedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
    }

    private var editSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑并重发").font(.headline)
            TextEditor(text: $editedText)
                .font(.body)
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

struct ReasoningDisclosure: View {
    let text: String
    var label: String = L10n.reasoning
    var icon: String = "brain"
    var isRunning: Bool = false

    var body: some View {
        // Single-line activity row (no expand / no copy), like Codex's
        // "Think · <…>" summary line.
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Think")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if isRunning {
                ProgressView().controlSize(.mini)
            }
            Text(text.isEmpty ? (isRunning ? "思考中…" : "思考") : text)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .help(text)
        .accessibilityLabel("思考过程")
    }
}

struct ToolCallRow: View {
    let toolCall: ToolCall
    var isRunning: Bool = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Single-line activity row: "Read · <path>", "Edit · <path>", …
            HStack(spacing: 6) {
                Image(systemName: toolIcon)
                    .foregroundStyle(toolIconColor)
                Text(toolCall.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(toolCall.arguments)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isRunning {
                    ProgressView().controlSize(.mini)
                }
                StatusBadge(status: toolCall.status.rawValue)
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "折叠结果" : "展开结果")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))

            if isExpanded {
                Text(toolCall.arguments)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                if let r = toolCall.result, !r.isEmpty {
                    Text(r)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
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
        switch toolCall.name.lowercased() {
        case "read", "readfile": return .blue
        case "edit", "write", "writefile": return .orange
        case "shell", "bash", "command", "run": return .green
        case "watch", "grep", "search": return .indigo
        default: return .indigo
        }
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        let (label, icon, color): (String, String, Color) = {
            switch status {
            case "succeeded": return ("完成", "checkmark", .green)
            case "failed": return ("失败", "xmark", .red)
            case "denied": return ("已拒绝", "hand.raised.slash", .red)
            case "running": return ("运行中", "gearshape.2", .blue)
            case "awaitingApproval": return ("待批准", "hand.raised", .orange)
            default: return ("待执行", "clock", .secondary)
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2)
        }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel(label)
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
