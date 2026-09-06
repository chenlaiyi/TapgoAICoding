import SwiftUI
import TapgoCore

/// Shared sizes keep navigation, project labels and task text on one grid.
enum SidebarMetrics {
    static let inset: CGFloat = 10
    static let rowInset: CGFloat = 8
    static let icon: CGFloat = 18
    static let gap: CGFloat = 8
    static let childInset: CGFloat = rowInset + icon + gap
}

struct SidebarNavigationRow: View {
    let title: String
    let icon: String
    var shortcut: String?
    var role: ButtonRole? = nil
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: SidebarMetrics.gap) {
                Image(systemName: icon).frame(width: SidebarMetrics.icon).foregroundStyle(DSHTheme.labelDim)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if let shortcut {
                    Text(shortcut).font(.system(size: 10 * scale.multiplier)).foregroundStyle(DSHTheme.labelTertiary)
                }
            }
            .font(.system(size: 13 * scale.multiplier))
            .padding(.horizontal, SidebarMetrics.rowInset)
            .frame(height: 34 * scale.multiplier)
            .contentShape(Rectangle())
            .background(hovering ? DSHTheme.sidebarHover : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SidebarTaskLabel: View {
    let title: String
    let date: String
    var status: Turn.Status?
    var pinned = false
    var selected = false
    var indented = true
    @State private var hovering = false
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 13 * scale.multiplier)).lineLimit(1).truncationMode(.tail)
            if pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(DSHTheme.labelTertiary)
            }
            Spacer(minLength: 2)
            Group {
                switch status {
                case .running: Image(systemName: "circle.lefthalf.filled").accessibilityLabel("进行中")
                case .awaitingApproval: Image(systemName: "hand.raised").accessibilityLabel("待批准")
                case .failed: Image(systemName: "exclamationmark.circle").foregroundStyle(DSHTheme.warn).accessibilityLabel("未完成")
                default: Text(date).monospacedDigit()
                }
            }
            .font(.system(size: 10 * scale.multiplier))
            .foregroundStyle(DSHTheme.labelTertiary)
            .frame(width: 32 * scale.multiplier, alignment: .trailing)
        }
        .padding(.leading, indented ? SidebarMetrics.childInset : SidebarMetrics.rowInset)
        .padding(.trailing, SidebarMetrics.rowInset)
        .frame(height: 32 * scale.multiplier)
        .contentShape(Rectangle())
        .background(selected ? DSHTheme.sidebarSelection : (hovering ? DSHTheme.sidebarHover : .clear), in: RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("任务：\(title)")
        .accessibilityValue(SidebarPresentation.statusText(status) ?? date)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SidebarProjectLabel: View {
    let title: String
    var remote = false
    var collapsed = false
    var pinned = false
    var running = false
    var hovering = false
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    var body: some View {
        HStack(spacing: SidebarMetrics.gap) {
            Image(systemName: hovering ? (collapsed ? "chevron.right" : "chevron.down") : (remote ? "globe" : "folder"))
                .font(.system(size: hovering ? 10 : 13))
                .foregroundStyle(DSHTheme.labelDim)
                .frame(width: SidebarMetrics.icon)
            Text(title).font(.system(size: 13 * scale.multiplier)).lineLimit(1).truncationMode(.tail)
            if pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(DSHTheme.labelTertiary) }
            Spacer(minLength: 0)
            if running { Circle().fill(DSHTheme.labelDim).frame(width: 5, height: 5) }
        }
        .contentShape(Rectangle())
    }
}

struct SidebarAccountLabel<Avatar: View>: View {
    @State private var hovering = false
    let name: String
    @ViewBuilder var avatar: () -> Avatar
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    var body: some View {
        HStack(spacing: 8) {
            avatar().frame(width: 24, height: 24)
            Text(name).font(.system(size: 13 * scale.multiplier)).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up").font(.system(size: 9)).foregroundStyle(DSHTheme.labelTertiary)
        }
        .padding(.horizontal, 8).frame(height: 40 * scale.multiplier)
        .contentShape(Rectangle())
        .background(hovering ? DSHTheme.sidebarHover : .clear, in: RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
    }
}
