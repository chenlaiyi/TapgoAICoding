import SwiftUI
import TapgoCore

struct CommandExecutionView: View {
    let execution: CommandExecution
    // Codex-style: short command output stays expanded so the user
    // can see the result immediately; long output defaults to
    // collapsed so a runaway `cat` or `npm install` doesn't push
    // the next user message off the screen. The user can still
    // tap the chevron to expand.
    let isRunning: Bool
    @EnvironmentObject var store: SessionStore
    @State private var isExpanded = false

    init(execution: CommandExecution, isRunning: Bool = false) {
        self.execution = execution
        self.isRunning = isRunning
    }

    var body: some View {
        if isRunning {
            // While running, show a single compact line that updates live
            // instead of an ever-growing output block (minimize output).
            HStack(spacing: 6) {
                Image(systemName: "terminal").foregroundStyle(.blue)
                Text(execution.command.isEmpty ? "运行中…" : execution.command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                ProgressView().controlSize(.mini)
                Button {
                    store.cancelActiveTurn()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("中断任务")
                .accessibilityLabel("中断任务")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
            .shadow(color: DSHTheme.cardShadow, radius: 3, x: 0, y: 1)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // Compact single-line activity row: "terminal Bash · <cmd>".
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.blue)
                    Text("Bash")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(execution.command)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let via = execution.viaSSH {
                        Text("\(L10n.viaSSHPrefix) \(via)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.18), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    Spacer(minLength: 0)
                    if !output.isEmpty {
                        Text("\(outputLineCount) 行")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if execution.status == .failed, let code = execution.exitCode,
                       code != 0 {
                        Text(L10n.exitCode(code))
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    statusBadge
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isExpanded ? "折叠输出" : "展开输出")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
                .contextMenu {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(execution.command, forType: .string)
                    } label: {
                        Label("复制命令", systemImage: "doc.on.doc")
                    }
                    if let cwd = execution.cwd, !cwd.isEmpty,
                       FileManager.default.fileExists(atPath: cwd) {
                        Button {
                            let p = Process()
                            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                            p.arguments = ["-a", "Terminal", cwd]
                            try? p.run()
                        } label: {
                            Label("在终端中打开目录", systemImage: "terminal")
                        }
                    }
                }

                if isExpanded && !output.isEmpty {
                    if !execution.stdout.isEmpty {
                        ScrollView {
                            Text(execution.stdout)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.green)
                    }
                    if !execution.stderr.isEmpty {
                        ScrollView {
                            Text(execution.stderr)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 140)
                        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    /// stdout + stderr flattened onto a single line so it can be shown as
    /// one ellipsized row.
    private var output: String {
        var s = execution.stdout
        if !execution.stderr.isEmpty {
            s += (s.isEmpty ? "" : "\n") + execution.stderr
        }
        return s.replacingOccurrences(of: "\n", with: " ")
    }

    /// Total lines of raw stdout+stderr, so a collapsed row can hint at
    /// how much output is folded away.
    private var outputLineCount: Int {
        var s = execution.stdout
        if !execution.stderr.isEmpty {
            s += (s.isEmpty ? "" : "\n") + execution.stderr
        }
        return s.isEmpty ? 0 : s.components(separatedBy: "\n").count
    }

    private var statusBadge: some View {
        let (label, icon, color): (String, String, Color) = {
            switch execution.status {
            case .succeeded: return ("完成", "checkmark", .green)
            case .failed: return ("失败", "xmark", .red)
            case .denied: return ("已拒绝", "hand.raised.slash", .red)
            case .running: return ("运行中", "gearshape.2", .blue)
            case .awaitingApproval: return ("待批准", "hand.raised", .orange)
            case .pending: return ("待执行", "clock", .secondary)
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

/// Small copy-to-pasteboard icon button used inside a terminal/command
/// block so the user can grab the command or its output.
struct CopyIconButton: View {
    let text: String
    var help: String = "复制"
    @State private var copied = false

    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
