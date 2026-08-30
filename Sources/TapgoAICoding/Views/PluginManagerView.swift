import SwiftUI
import TapgoCore

@MainActor
final class PluginManagerViewModel: ObservableObject {
    enum PendingAction {
        case install(PluginCatalogItem)
        case uninstall(PluginCatalogItem)

        var item: PluginCatalogItem {
            switch self {
            case .install(let item), .uninstall(let item): return item
            }
        }

        var title: String {
            switch self {
            case .install: return "安装插件？"
            case .uninstall: return "卸载插件？"
            }
        }

        var buttonTitle: String {
            switch self {
            case .install: return "安装"
            case .uninstall: return "卸载"
            }
        }
    }

    @Published private(set) var items: [PluginCatalogItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var operatingId: String?
    @Published var errorMessage: String?
    @Published var pendingAction: PendingAction?

    private let service = PluginManagerService()

    var installedCount: Int { items.filter(\.installed).count }
    var codexCount: Int { items.filter { $0.marketplace == .codex }.count }
    var deepSeekCount: Int { items.filter { $0.marketplace == .deepSeek }.count }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await service.loadCatalog()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func performPendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        operatingId = action.item.id
        errorMessage = nil
        defer { operatingId = nil }
        do {
            switch action {
            case .install(let item): try await service.install(item)
            case .uninstall(let item): try await service.uninstall(item)
            }
            items = try await service.loadCatalog()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, item: PluginCatalogItem) async {
        operatingId = item.id
        errorMessage = nil
        defer { operatingId = nil }
        do {
            try await service.setCodexEnabled(enabled, item: item)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].enabled = enabled
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PluginManagerView: View {
    var isEmbedded = false

    private enum Tab: String, CaseIterable, Identifiable {
        case installed
        case codex
        case deepSeek

        var id: String { rawValue }
        var title: String {
            switch self {
            case .installed: return "已安装"
            case .codex: return "Codex 官方"
            case .deepSeek: return "DeepSeek 官方"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    @StateObject private var model = PluginManagerViewModel()
    @State private var selectedTab: Tab = .installed
    @State private var searchText = ""

    private var visibleItems: [PluginCatalogItem] {
        model.items.filter { item in
            let tabMatches: Bool
            switch selectedTab {
            case .installed: tabMatches = item.installed
            case .codex: tabMatches = item.marketplace == .codex
            case .deepSeek: tabMatches = item.marketplace == .deepSeek
            }
            return tabMatches && item.matches(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.errorMessage {
                errorBanner(error)
            }
            content
        }
        .frame(
            minWidth: isEmbedded ? 0 : 980,
            maxWidth: isEmbedded ? .infinity : 980,
            minHeight: isEmbedded ? 0 : 680,
            maxHeight: isEmbedded ? .infinity : 680
        )
        .background(DSHTheme.bg)
        .task { await model.refresh() }
        .confirmationDialog(
            model.pendingAction?.title ?? "插件操作",
            isPresented: Binding(
                get: { model.pendingAction != nil },
                set: { if !$0 { model.pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = model.pendingAction {
                Button(action.buttonTitle, role: action.buttonTitle == "卸载" ? .destructive : nil) {
                    Task { await model.performPendingAction() }
                }
                Button("取消", role: .cancel) { model.pendingAction = nil }
            }
        } message: {
            if let action = model.pendingAction {
                Text("\(action.item.displayName) 将修改本机的 \(action.item.marketplace.displayName) 插件环境。新会话或重启对应 Harness 后生效。")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DSHTheme.brand)
                    .frame(width: 38, height: 38)
                    .background(DSHTheme.brandSoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("插件")
                        .font(AppFont.scaled(.title2, multiplier: appFontScale.multiplier).weight(.semibold))
                    Text("管理已安装插件，或从官方来源选择安装")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoading)
                .help("刷新插件目录")
                if !isEmbedded {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("关闭插件管理")
                }
            }

            HStack(spacing: 8) {
                ForEach(Tab.allCases) { tab in
                    tabButton(tab)
                }
                Spacer(minLength: 20)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索插件", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 210)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DSHTheme.border, lineWidth: 1))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func tabButton(_ tab: Tab) -> some View {
        let count: Int = {
            switch tab {
            case .installed: return model.installedCount
            case .codex: return model.codexCount
            case .deepSeek: return model.deepSeekCount
            }
        }()
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(tab.title)
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
            .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selectedTab == tab ? DSHTheme.interactiveHoverStrong : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在读取官方插件目录…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: searchText.isEmpty ? "shippingbox" : "magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                Text(searchText.isEmpty ? emptyMessage : "没有匹配的插件")
                    .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                if selectedTab == .deepSeek {
                    Text("DeepSeek 官方没有独立市场接口；这里显示官方发布、可安装到 web profile 的插件包。")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if selectedTab == .deepSeek {
                        sourceNote("通过 DeepSeek 官方 npm 组织读取，安装到 web profile；变更后需重启 DeepSeek Harness。")
                    } else if selectedTab == .codex {
                        sourceNote("通过当前 Tapgo AICoding 使用的 Codex CLI 与隔离配置目录读取。")
                    }
                    ForEach(visibleItems) { item in
                        pluginRow(item)
                        Divider().padding(.leading, 84)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyMessage: String {
        switch selectedTab {
        case .installed: return "还没有安装插件"
        case .codex: return "没有读取到 Codex 官方插件"
        case .deepSeek: return "没有读取到可安装的 DeepSeek 官方插件包"
        }
    }

    private func sourceNote(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(DSHTheme.brand)
            Text(text)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private func pluginRow(_ item: PluginCatalogItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor(item).opacity(0.16))
                Image(systemName: iconName(item))
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(iconColor(item))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                    Text("v\(item.version)")
                        .font(AppFont.monoScaled(size: 10, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                    if item.installed {
                        Text("已安装")
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                            .foregroundStyle(DSHTheme.success)
                    }
                }
                Text(item.summary.isEmpty ? "\(item.marketplace.displayName)插件" : item.summary)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.marketplaceName)
                    ForEach(item.capabilities, id: \.self) { capability in
                        Text(capability)
                    }
                }
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 16)

            if model.operatingId == item.id {
                ProgressView().controlSize(.small).frame(width: 64)
            } else if item.installed {
                if item.marketplace == .codex {
                    Toggle("", isOn: Binding(
                        get: { item.enabled },
                        set: { enabled in Task { await model.setEnabled(enabled, item: item) } }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(item.enabled ? "停用插件" : "启用插件")
                }
                Menu {
                    Button("卸载", role: .destructive) {
                        model.pendingAction = .uninstall(item)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Button("安装") {
                    model.pendingAction = .install(item)
                }
                .buttonStyle(DSHPrimaryButtonStyle())
            }
        }
        .padding(.vertical, 14)
    }

    private func iconName(_ item: PluginCatalogItem) -> String {
        if item.marketplace == .deepSeek { return "shippingbox.fill" }
        if item.capabilities.contains("应用") { return "square.grid.2x2.fill" }
        if item.capabilities.contains("MCP") { return "point.3.connected.trianglepath.dotted" }
        return "puzzlepiece.extension.fill"
    }

    private func iconColor(_ item: PluginCatalogItem) -> Color {
        if item.marketplace == .deepSeek { return Color(hex: 0x8B5CF6) }
        let palette: [Color] = [DSHTheme.brand, DSHTheme.success, Color(hex: 0xF97316), Color(hex: 0xEC4899)]
        return palette[Int(UInt(bitPattern: item.name.hashValue) % UInt(palette.count))]
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DSHTheme.error)
            Text(message)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .lineLimit(3)
            Spacer()
            Button("关闭") { model.errorMessage = nil }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(DSHTheme.error.opacity(0.09))
    }
}
