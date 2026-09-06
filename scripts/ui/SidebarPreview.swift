import SwiftUI
import TapgoCore

// Safe visual fixture using shipping sidebar components; no SessionStore or model requests.
@main
struct SidebarPreview: App {
    var body: some Scene {
        WindowGroup("侧栏组件验收") { SidebarPreviewContent() }
            .defaultSize(width: 800, height: 780)
    }
}
private struct SidebarPreviewContent: View {
    @State private var dark = true
    @State private var large = false
    @State private var narrow = false
    @State private var folded = false
    @State private var selected = "统一任务与目标交互"
    @State private var hovering = false
    @State private var account = false
    private let tasks = ["统一任务与目标交互", "检查窄窗口中的超长任务标题是否保持稳定且不会挤动日期", "核对清单的待批准状态", "排查构建失败", "补充界面回归记录"]
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    SidebarNavigationRow(title: "新建任务", icon: "square.and.pencil", shortcut: "⌘N") { selected = "新建任务" }
                    SidebarNavigationRow(title: "搜索", icon: "magnifyingglass", shortcut: "⌘K") {}
                    SidebarNavigationRow(title: "插件市场", icon: "shippingbox") {}
                    SidebarNavigationRow(title: "定时任务", icon: "clock") {}
                }.padding(.horizontal, SidebarMetrics.inset).padding(.top, 14)
                HStack {
                    Text("任务").font(.system(size: 11)).foregroundStyle(DSHTheme.labelDim)
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease")
                    Image(systemName: "folder.badge.plus").padding(.leading, 12)
                }.font(.system(size: 12)).padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 6)
                VStack(spacing: 3) {
                    HStack(spacing: 2) {
                        Button { folded.toggle() } label: {
                            SidebarProjectLabel(title: "JLcake", collapsed: folded, hovering: hovering)
                        }.buttonStyle(.plain).accessibilityLabel("展开或折叠 JLcake")
                        Image(systemName: "plus").frame(width: 20, height: 24).opacity(hovering ? 1 : 0.25)
                        Image(systemName: "ellipsis").frame(width: 20).opacity(hovering ? 1 : 0.25)
                    }.font(.system(size: 11)).padding(.horizontal, SidebarMetrics.rowInset)
                        .frame(height: 32 * (large ? 1.1 : 1))
                        .background(hovering ? DSHTheme.sidebarHover : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .onHover { hovering = $0 }
                    if !folded {
                        ForEach(Array(tasks.enumerated()), id: \.offset) { index, title in
                            Button { selected = title } label: {
                                SidebarTaskLabel(title: title, date: index < 2 ? "今天" : "昨天",
                                                 status: index == 1 ? .running : (index == 2 ? .awaitingApproval : (index == 3 ? .failed : .completed)),
                                                 pinned: index == 0, selected: selected == title)
                            }.buttonStyle(.plain)
                        }
                    }
                    SidebarProjectLabel(title: "远程设计项目", remote: true, collapsed: true)
                        .padding(.horizontal, SidebarMetrics.rowInset).frame(height: 32 * (large ? 1.1 : 1))
                    Text("其他任务").font(.system(size: 11)).foregroundStyle(DSHTheme.labelDim)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 4)
                    Button { selected = "整理设计参考" } label: {
                        SidebarTaskLabel(title: "整理设计参考", date: "9/1", selected: selected == "整理设计参考", indented: false)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, SidebarMetrics.inset)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    Button { account = true } label: {
                        SidebarAccountLabel(name: "设计工作室") {
                            Text("设").font(.system(size: 11, weight: .medium))
                                .frame(width: 24, height: 24).background(DSHTheme.sidebarSelection, in: Circle())
                        }
                    }.buttonStyle(.plain).popover(isPresented: $account) {
                        VStack(spacing: 4) {
                            SidebarNavigationRow(title: "设置", icon: "gearshape") { account = false }
                            SidebarNavigationRow(title: "连接手机", icon: "iphone") { account = false }
                        }.padding(8).frame(width: 230)
                    }
                    Image(systemName: "arrow.up.circle").font(.system(size: 12)).foregroundStyle(DSHTheme.labelDim).frame(width: 24, height: 24)
                }.padding(.horizontal, 10).padding(.vertical, 8)
                    .overlay(alignment: .top) { Rectangle().fill(DSHTheme.border.opacity(0.5)).frame(height: 0.5) }
            }.frame(width: narrow ? 220 : 260).background(DSHTheme.sidebarBg)
            VStack(alignment: .leading, spacing: 18) {
                Text("侧栏组件验收").font(.title2)
                Toggle("深色", isOn: $dark)
                Toggle("大字体", isOn: $large)
                Toggle("窄侧栏", isOn: $narrow)
                Divider()
                Text(selected).font(.headline)
                Text("检查左侧行对齐、状态、长标题与折叠。\n此窗口使用虚构数据和正式组件。").foregroundStyle(.secondary)
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(DSHTheme.surface)
        }
        .frame(minWidth: 660, minHeight: 650)
        .environment(\.tapgoFontScale, large ? AppFontScale.large : .medium)
        .preferredColorScheme(dark ? .dark : .light)
    }
}
