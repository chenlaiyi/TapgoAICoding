import SwiftUI

/// A bounded log viewport follows new output only until the reader scrolls or pauses it.
struct LiveToolOutputView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let output: MobileToolOutput
    @State private var following = true
    private let tail = "live-output-tail"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { statusText; copyButton }
            } else {
                HStack { statusText; Spacer(minLength: 8); copyButton }
            }
            if output.gap {
                Text("部分较早输出已省略或未能恢复，最终返回以工具结果为准")
                    .font(.caption).foregroundStyle(.orange)
            }
            ScrollViewReader { reader in
                VStack(alignment: .leading, spacing: 4) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) { followCaption; followButton(reader) }
                    } else {
                        HStack { followCaption; Spacer(minLength: 4); followButton(reader) }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(output.text.isEmpty ? "等待新输出…" : output.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("liveToolOutputText")
                            Color.clear.frame(height: 1).id(tail)
                        }
                        .padding(10)
                    }
                    .frame(height: 200)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .simultaneousGesture(DragGesture().onChanged { _ in following = false })
                    .onAppear { reader.scrollTo(tail, anchor: .bottom) }
                    .onChange(of: output.revision) { _ in
                        if following { reader.scrollTo(tail, anchor: .bottom) }
                    }

                }
            }
        }
        .accessibilityIdentifier("liveToolOutput")
    }
    private var statusText: some View {
        Text(output.status).font(.caption).foregroundStyle(.secondary)
    }

    private var copyButton: some View {
        Button("复制预览") { UIPasteboard.general.string = output.text }
            .font(.caption).frame(minHeight: 44).disabled(output.text.isEmpty)
    }

    private var followCaption: some View {
        Text(!output.active ? "查看已收到的输出" : following ? "正在跟随最新输出" : "已暂停跟随，输出仍在接收")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func followButton(_ reader: ScrollViewProxy) -> some View {
        let pause = output.active && following
        return Button(!output.active ? "回到末尾" : pause ? "暂停跟随" : "回到最新") {
            following = !pause
            if !pause { reader.scrollTo(tail, anchor: .bottom) }
        }
        .font(.caption).frame(minHeight: 44)
    }

}

#if DEBUG
private struct ToolOutputFixtureAction: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var advanceToolOutputFixture: (() -> Void)? {
        get { self[ToolOutputFixtureAction.self] }
        set { self[ToolOutputFixtureAction.self] = newValue }
    }
}
#endif
