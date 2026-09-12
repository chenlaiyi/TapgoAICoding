import SwiftUI
import TapgoCore

/// 自进化 diff 审阅 sheet：展示上一 tag → 当前 tag 的文件统计与变更列表。
struct EvolutionDiffSheet: View {
    let projectRoot: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    @State private var summary = "加载中…"
    @State private var rangeText = ""
    @State private var commitText = ""
    @State private var statText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(DSHTheme.brand)
                Text("本轮自进化 diff")
                    .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 10) {
                    if !rangeText.isEmpty {
                        EvolutionDiffSummaryCard(range: rangeText, commit: commitText, stat: statText)
                    }
                    Text(summary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .padding(12)
            }
        }
        .frame(width: 760, height: 560)
        .background(DSHTheme.bg)
        .task { load() }
    }

    private func load() {
        let current = git(["describe", "--tags", "--abbrev=0", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !current.isEmpty {
            let previous = git(["describe", "--tags", "--abbrev=0", "\(current)^"]).trimmingCharacters(in: .whitespacesAndNewlines)
            rangeText = "范围: \(previous.isEmpty ? current : previous)..\(current)"
            commitText = git(["log", "-1", "--format=%h %s", current]).trimmingCharacters(in: .whitespacesAndNewlines)
            statText = git(["diff", "--stat", previous.isEmpty ? current : "\(previous)..\(current)"]).trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(rangeText)
            parts.append("")
            parts.append(commitText)
            parts.append(statText)
            parts.append(git(["diff", "--name-status", previous.isEmpty ? current : "\(previous)..\(current)"]))
        } else {
            parts.append("范围: 工作树")
            parts.append(git(["status", "--short"]))
            parts.append(git(["diff", "--stat", "HEAD"]))
            parts.append(git(["diff", "--name-status", "HEAD"]))
        }
        let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        summary = joined.isEmpty ? "没有可展示的 diff。" : joined
    }

    private func git(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectRoot.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "git 执行失败: \(error.localizedDescription)"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
