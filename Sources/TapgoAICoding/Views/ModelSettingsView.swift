// TapgoAICoding/Views/ModelSettingsView.swift
// v0.5.54：模型设置按 ZCode 真实界面整窗复刻 —— 把"供应商 / 模型"两层结构搬到
// Tapgo AICoding。三个内置供应商（智谱 / MiniMax / DeepSeek）按 kind 默认
// 挂若干 ProviderModel；用户可在"自定义供应商"段下增删改查。
//
// 与 v0.5.52 SettingsView.modelTab 的差异：
//   * 不再在 SettingsView 内联：迁到独立 ModelSettingsView
//   * 不再有"MiniMax 端点覆盖"卡片（端点改到每个 Provider 行内可改）
//   * 行尾操作：测试模型 / 编辑模型配置（popupbutton 菜单：编辑 / 添加模型 / 删除）
//   * 自定义供应商支持删除；内置不允许
//   * 顶部"拖拽调整供应商顺序"按钮占位，点击弹即将推出提示

import SwiftUI
import TapgoCore

/// 模型设置页（v0.5.53 起）。从 SettingsView.modelTab 接入。
struct ModelSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tapgoFontScale) private var appFontScale
    @State private var providers: [Provider] = []
    @State private var editingProvider: Provider?
    @State private var addingProvider: Bool = false
    @State private var removeCandidate: Provider?
    @State private var dragReorderHintShown: Bool = false
    @State private var perProviderTest: [String: TestState] = [:]
    @State private var activeProviderID: String = ""
    @State private var modelEditor: ModelEditorContext?
    @State private var modelRemoval: ModelRemovalContext?
    @State private var quotaSnapshot: RateLimitsSnapshot?
    @State private var quotaLoading = false
    @State private var quotaError: String?
    /// 「新会话模型」当前选中的「providerID :: modelID」。
    @State private var selectedProviderModel: String = ""
    @AppStorage(TapgoConfig.selectedModelKey) private var selectedModelRaw = ""
    @AppStorage(TapgoConfig.reasoningEffortKey) private var reasoningEffort = ""

    enum TestState: Equatable {
        case testing
        case success(latencyMs: UInt)
        case failure(String)

        var displayText: String {
            switch self {
            case .testing: return L10n.testingConnection
            case .success(let ms): return L10n.connectionSucceeded(latencyMs: ms)
            case .failure(let msg): return L10n.connectionFailed(msg)
            }
        }
        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    private var builtinProviders: [Provider] {
        providers.filter { $0.isBuiltin }
    }
    private var customProviders: [Provider] {
        providers.filter { !$0.isBuiltin }
    }
    private var selectedProviderID: String? {
        providers.first(where: { selectedProviderModel.hasPrefix($0.id + "::") })?.id
    }
    private var activeProvider: Provider? {
        providers.first(where: { $0.id == activeProviderID }) ?? providers.first
    }

    private struct ModelEditorContext: Identifiable {
        let id = UUID()
        let providerID: String
        let model: ProviderModel?
    }

    private struct ModelRemovalContext: Identifiable {
        let id = UUID()
        let provider: Provider
        let model: ProviderModel
    }

    var body: some View {
        HStack(spacing: 0) {
            providerNavigation
                .frame(width: 265)
            Divider()
            Group {
                if let provider = activeProvider {
                    providerDetail(provider)
                } else {
                    ContentUnavailableView(
                        "尚无模型供应商",
                        systemImage: "cube",
                        description: Text("添加供应商后即可配置模型。")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 690)
        .background(DSHTheme.bgLayer1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DSHTheme.borderStrong.opacity(0.75), lineWidth: 1)
        )
        .onAppear {
            reloadProviders()
            let r = TapgoConfig.providerRegistry()
            _ = r.migrateFromLegacyIfNeeded()
            r.ensureBuiltinProviders()
            let sel = r.resolveSelectedProvider()
            let model = r.resolveSelectedModel(for: sel)
            activeProviderID = sel.id
            selectedProviderModel = "\(sel.id)::\(model.id)"
        }
        .task(id: activeProviderID) {
            await loadQuotaForActiveProvider()
        }
        .sheet(item: $editingProvider) { p in
            EditProviderSheet(provider: p) { saved in
                saveProvider(saved)
            }
        }
        .sheet(isPresented: $addingProvider) {
            EditProviderSheet(provider: nil) { saved in
                saveProvider(saved)
                activeProviderID = saved.id
            }
        }
        .sheet(item: $modelEditor) { context in
            EditModelSheet(model: context.model) { model in
                saveModel(model, providerID: context.providerID)
            }
        }
        .confirmationDialog(
            String(format: L10n.providerRemoveConfirm,
                   removeCandidate?.displayName ?? ""),
            isPresented: .init(get: { removeCandidate != nil },
                               set: { if !$0 { removeCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.delete, role: .destructive) {
                if let p = removeCandidate { deleteProvider(p) }
                removeCandidate = nil
            }
            Button(L10n.cancel, role: .cancel) { removeCandidate = nil }
        } message: {
            Text(L10n.providerRemoveHint)
        }
        .confirmationDialog(
            "删除模型 \(modelRemoval?.model.apiModel ?? "")？",
            isPresented: .init(
                get: { modelRemoval != nil },
                set: { if !$0 { modelRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.delete, role: .destructive) {
                if let context = modelRemoval {
                    removeModel(context.model, from: context.provider)
                }
                modelRemoval = nil
            }
            Button(L10n.cancel, role: .cancel) { modelRemoval = nil }
        } message: {
            Text("仅删除 Tapgo AICoding 内的模型配置，不影响上游账号。")
        }
    }

    // MARK: - Provider navigation

    @ViewBuilder
    private var providerNavigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    providerNavigationSection(title: "智谱", providers: builtinProviders)
                    providerNavigationSection(title: "自定义供应商", providers: customProviders)

                    Button {
                        addingProvider = true
                    } label: {
                        Label("添加供应商", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                    .foregroundStyle(DSHTheme.label)
                    .padding(.horizontal, 10)

                    if dragReorderHintShown {
                        Text(L10n.providerDragHint)
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(DSHTheme.warn)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(14)
            }

            Divider()
            HStack(spacing: 8) {
                Button {
                    reloadProviders()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    dragReorderHintShown.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .buttonStyle(.plain)
                .help("拖拽调整供应商顺序")
            }
            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            .foregroundStyle(DSHTheme.labelDim)
            .padding(14)
        }
        .background(DSHTheme.surface.opacity(0.72))
    }

    @ViewBuilder
    private func providerNavigationSection(title: String, providers: [Provider]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                .foregroundStyle(DSHTheme.labelTertiary)
                .padding(.horizontal, 8)
            if providers.isEmpty {
                Text("尚未添加")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            } else {
                ForEach(providers) { provider in
                    providerNavigationRow(provider)
                }
            }
        }
    }

    @ViewBuilder
    private func providerNavigationRow(_ provider: Provider) -> some View {
        Button {
            activeProviderID = provider.id
        } label: {
            HStack(spacing: 9) {
                Image(systemName: providerIcon(provider))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(provider.isBuiltin ? DSHTheme.brand : DSHTheme.labelDim)
                    .frame(width: 18)
                Text(provider.displayName)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Circle()
                    .fill(provider.apiKey.isEmpty ? DSHTheme.labelTertiary : DSHTheme.success)
                    .frame(width: 7, height: 7)
            }
            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
            .foregroundStyle(DSHTheme.label)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                activeProviderID == provider.id ? DSHTheme.interactiveHoverStrong : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                if activeProviderID == provider.id {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(DSHTheme.borderStrong, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Provider detail

    @ViewBuilder
    private func providerDetail(_ provider: Provider) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: providerIcon(provider))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DSHTheme.brand)
                    Text(provider.displayName)
                        .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier).weight(.bold))
                    statusBadge(provider.apiKey.isEmpty ? "未配置" : "已启用",
                                color: provider.apiKey.isEmpty ? DSHTheme.labelTertiary : DSHTheme.success)
                    Spacer()
                    Text("连接方式")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.labelDim)
                    Menu("API Key") { Text("API Key") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                }

                providerOverview(provider)

                VStack(alignment: .leading, spacing: 8) {
                    Text("模型列表")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                        .foregroundStyle(DSHTheme.labelDim)
                    VStack(spacing: 0) {
                        ForEach(Array(provider.models.enumerated()), id: \.element.id) { index, model in
                            if index > 0 { Divider().padding(.leading, 12) }
                            modelRow(provider: provider, model: model)
                        }
                    }
                    .background(DSHTheme.surface.opacity(0.74), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(DSHTheme.border, lineWidth: 1)
                    )

                    Button {
                        modelEditor = ModelEditorContext(providerID: provider.id, model: nil)
                    } label: {
                        Label("添加模型", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                    .foregroundStyle(DSHTheme.label)
                    .padding(.top, 2)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func providerOverview(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(providerOverviewTitle(provider))
                        .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier).weight(.bold))
                    Text(provider.baseURL)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.labelDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("管理") { editingProvider = provider }
                    .buttonStyle(.plain)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                if !provider.isBuiltin {
                    Button("删除") { removeCandidate = provider }
                        .buttonStyle(.plain)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                        .foregroundStyle(DSHTheme.error)
                }
            }
            Divider()
            Text("剩余额度")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                .foregroundStyle(DSHTheme.labelDim)
            switch provider.builtInKind {
            case .zhipu:
                windowQuotaCards(providerName: "智谱 Coding Plan", defaultPlan: "--")
            case .minimax:
                windowQuotaCards(
                    providerName: "MiniMax Coding Plan",
                    defaultPlan: TapgoConfig.planDisplayName
                )
            case .deepseek:
                deepSeekBalanceCards
            case nil:
                unsupportedQuotaCard
            }
        }
        .padding(24)
        .background(DSHTheme.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DSHTheme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func windowQuotaCards(providerName: String, defaultPlan: String) -> some View {
        HStack(spacing: 10) {
            quotaMetricCard(title: quotaSnapshot?.primary?.windowLabel ?? "5 小时剩余",
                            window: quotaSnapshot?.primary,
                            tint: DSHTheme.brand)
            quotaMetricCard(title: quotaSnapshot?.secondary?.windowLabel ?? "每周剩余",
                            window: quotaSnapshot?.secondary,
                            tint: DSHTheme.success)
            metricCard(
                title: "当前套餐",
                value: quotaLoading ? "…" : (quotaSnapshot?.planLabel ?? defaultPlan),
                caption: quotaError ?? providerName,
                tint: Color(hex: 0xFF8A3D),
                progress: quotaSnapshot == nil ? 0 : 1
            )
        }
    }

    @ViewBuilder
    private var deepSeekBalanceCards: some View {
        let credits = quotaSnapshot?.credits
        HStack(spacing: 10) {
            metricCard(
                title: "账户余额",
                value: quotaLoading ? "…" : ((credits?.balance.isEmpty == false) ? credits!.balance : "--"),
                caption: quotaError ?? "DeepSeek 官方余额",
                tint: DSHTheme.brand,
                progress: credits == nil ? 0 : 1
            )
            metricCard(
                title: "计费方式",
                value: "按量",
                caption: "无 5 小时/每周窗口",
                tint: DSHTheme.success,
                progress: 1
            )
            metricCard(
                title: "余额状态",
                value: quotaLoading ? "查询中" : (credits == nil ? "--" : "可用"),
                caption: credits?.unlimited == true ? "不限额" : "以官方账户为准",
                tint: Color(hex: 0xFF8A3D),
                progress: credits == nil ? 0 : 1
            )
        }
    }

    @ViewBuilder
    private var unsupportedQuotaCard: some View {
        metricCard(
            title: "剩余额度",
            value: "--",
            caption: "该供应商未提供官方额度查询接口",
            tint: DSHTheme.labelTertiary,
            progress: 0
        )
    }

    @ViewBuilder
    private func quotaMetricCard(title: String, window: RateLimitWindow?, tint: Color) -> some View {
        let remaining = window.map { max(0, 100 - $0.usedPercent) }
        metricCard(
            title: title,
            value: quotaLoading ? "…" : remaining.map { "\($0)%" } ?? "--",
            caption: window?.resetsAt.map(resetCaption)
                ?? quotaError
                ?? (window == nil ? "未返回此额度" : "当前周期"),
            tint: tint,
            progress: Double(remaining ?? 0) / 100
        )
    }

    @ViewBuilder
    private func metricCard(
        title: String,
        value: String,
        caption: String,
        tint: Color,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                .foregroundStyle(DSHTheme.labelDim)
            Text(value)
                .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier).weight(.bold))
                .foregroundStyle(DSHTheme.label)
            Text(caption)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.labelTertiary)
                .lineLimit(1)
            Capsule()
                .fill(DSHTheme.borderStrong)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * max(0, min(1, progress)))
                    }
                }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(DSHTheme.bgLayer1.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func modelRow(provider: Provider, model: ProviderModel) -> some View {
        let composite = "\(provider.id)::\(model.id)"
        let isSelected = composite == selectedProviderModel
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(model.apiModel)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                    .foregroundStyle(DSHTheme.label)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if model.apiModel.localizedCaseInsensitiveContains("Flash") {
                    statusBadge("视觉", color: DSHTheme.labelDim)
                }
                Text(contextWindowLabel(model.contextWindow))
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                    .foregroundStyle(DSHTheme.labelDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DSHTheme.interactiveHover, in: Capsule())
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DSHTheme.success)
                        .help("当前模型")
                }
                Button {
                    runTest(provider: provider, model: model)
                } label: {
                    Image(systemName: "bolt")
                }
                .buttonStyle(.plain)
                .help("测试模型")
                Button {
                    modelEditor = ModelEditorContext(providerID: provider.id, model: model)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("编辑模型配置")
                Button {
                    modelRemoval = ModelRemovalContext(provider: provider, model: model)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("删除模型")
            }
            .foregroundStyle(DSHTheme.labelDim)
            .padding(.horizontal, 12)
            .frame(height: 60)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isSelected { selectProviderModel(provider: provider, model: model) }
            }

            if let state = perProviderTest[composite] {
                HStack(spacing: 6) {
                    switch state {
                    case .testing:
                        ProgressView().controlSize(.small)
                    case .success:
                        Image(systemName: "checkmark.seal.fill")
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    Text(state.displayText)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                }
                .foregroundStyle(state.isSuccess ? DSHTheme.success : DSHTheme.error)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func providerIcon(_ provider: Provider) -> String {
        switch provider.builtInKind {
        case .zhipu: return "diamond.fill"
        case .minimax: return "circle.hexagongrid.fill"
        case .deepseek: return "wave.3.right.circle.fill"
        case nil: return "shippingbox.fill"
        }
    }

    private func providerOverviewTitle(_ provider: Provider) -> String {
        if provider.builtInKind == .zhipu {
            let plan = quotaSnapshot?.planLabel ?? "Lite"
            return plan.localizedCaseInsensitiveContains("coding")
                ? "GLM \(plan)"
                : "GLM Coding \(plan)"
        }
        return provider.brand
    }

    private func resetCaption(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M月d日"
        }
        return formatter.string(from: date)
    }

    private func contextWindowLabel(_ value: Int) -> String {
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return "\(value / 1_000)K"
        default: return "\(value / 1_000_000)M"
        }
    }

    // MARK: - 操作

    private func reloadProviders() {
        let r = TapgoConfig.providerRegistry()
        _ = r.migrateFromLegacyIfNeeded()
        r.ensureBuiltinProviders()
        providers = r.providers
    }

    @MainActor
    private func loadQuotaForActiveProvider() async {
        quotaSnapshot = nil
        quotaError = nil
        guard let provider = activeProvider,
              let kind = provider.builtInKind,
              !provider.apiKey.isEmpty
        else {
            if activeProvider?.isBuiltin == false {
                quotaError = "该供应商未提供官方额度查询接口"
            }
            return
        }
        quotaLoading = true
        defer { quotaLoading = false }
        do {
            switch kind {
            case .zhipu:
                quotaSnapshot = try await GLMQuotaClient(apiKey: provider.apiKey).fetchRemains()
            case .minimax:
                quotaSnapshot = try await MiniMaxQuotaClient(
                    apiKey: provider.apiKey,
                    modelName: provider.models.first?.apiModel ?? TapgoConfig.modelName
                ).fetchRemains()
            case .deepseek:
                quotaSnapshot = try await DeepSeekQuotaClient(apiKey: provider.apiKey).fetchBalance()
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            quotaError = error.localizedDescription
        }
    }

    private func saveProvider(_ provider: Provider) {
        let r = TapgoConfig.providerRegistry()
        r.addOrUpdate(provider)
        TapgoConfig.syncProviderFiles()
        reloadProviders()
    }

    private func deleteProvider(_ provider: Provider) {
        let r = TapgoConfig.providerRegistry()
        if r.removeProvider(id: provider.id) {
            TapgoConfig.syncProviderFiles()
        }
        reloadProviders()
    }

    private func saveModel(_ model: ProviderModel, providerID: String) {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        var models = provider.models
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index] = model
        } else {
            models.append(model)
        }
        TapgoConfig.providerRegistry().updateModels(models, for: providerID)
        TapgoConfig.syncProviderFiles()
        reloadProviders()
    }

    private func removeModel(_ model: ProviderModel, from provider: Provider) {
        let models = provider.models.filter { $0.id != model.id }
        guard !models.isEmpty else { return }
        TapgoConfig.providerRegistry().updateModels(models, for: provider.id)
        if selectedProviderModel == "\(provider.id)::\(model.id)", let fallback = models.first {
            selectProviderModel(provider: provider, model: fallback)
        }
        TapgoConfig.syncProviderFiles()
        reloadProviders()
    }

    private func selectProviderModel(provider: Provider, model: ProviderModel) {
        let composite = "\(provider.id)::\(model.id)"
        selectedProviderModel = composite
        // 同步给 v0.5.52 旧 UserDefaults（thread/start 路径用 builtin:<slug>
        // 或 custom-XXX），保持选择态一致
        let resolved = resolveLegacyRaw(for: provider, model: model)
        selectedModelRaw = resolved
        let registry = TapgoConfig.providerRegistry()
        registry.setSelectedProvider(id: provider.id)
        registry.setSelectedModel(model, for: provider)
        TapgoConfig.syncProviderFiles()
    }

    /// 把 Provider / Model 映射回 v0.5.52 的 selectedModelKey 值。
    private func resolveLegacyRaw(for provider: Provider, model: ProviderModel) -> String {
        if provider.isBuiltin, provider.builtInKind != nil {
            // 内置 GLM-5.3 / GLM-5.3-Flash / GLM-5-Turbo 映射回旧 slug：
            // 旧 TapgoModel 用 "GLM-5.3-Flash" / "deepseek-v4-flash" 等。
            // 兼容旧 thread/start —— 用 model.apiModel 作为 builtin:<apiModel>
            return "builtin:\(model.apiModel)"
        }
        return provider.id  // 自定义 Provider 整体 = 旧 custom-<id>
    }

    private func runTest(provider: Provider, model: ProviderModel) {
        let composite = "\(provider.id)::\(model.id)"
        perProviderTest[composite] = .testing
        TapgoConfig.testConnection(provider: provider, model: model) { result in
            switch result {
            case .success(let ms):
                perProviderTest[composite] = .success(latencyMs: ms)
            case .failure(let err):
                let msg = (err as? LocalizedError)?.errorDescription
                    ?? err.localizedDescription
                perProviderTest[composite] = .failure(msg)
            }
        }
    }
}

// MARK: - 编辑单个模型

private struct EditModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var apiModel: String
    @State private var contextWindow: Int
    private let originalID: String
    private let onSave: (ProviderModel) -> Void

    init(model: ProviderModel?, onSave: @escaping (ProviderModel) -> Void) {
        _displayName = State(initialValue: model?.displayName ?? "")
        _apiModel = State(initialValue: model?.apiModel ?? "")
        _contextWindow = State(initialValue: model?.contextWindow ?? 128_000)
        originalID = model?.id ?? "model-\(UUID().uuidString.prefix(8).uppercased())"
        self.onSave = onSave
    }

    private var model: ProviderModel {
        ProviderModel(
            id: originalID,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            apiModel: apiModel.trimmingCharacters(in: .whitespacesAndNewlines),
            contextWindow: contextWindow,
            isCustom: true
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(displayName.isEmpty ? "添加模型" : "编辑模型配置")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("模型 ID").font(.caption).foregroundStyle(.secondary)
                TextField("例如 GLM-5.3-Flash", text: $apiModel)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("显示名称").font(.caption).foregroundStyle(.secondary)
                TextField("模型显示名称", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("上下文窗口").font(.caption).foregroundStyle(.secondary)
                Picker("上下文窗口", selection: $contextWindow) {
                    ForEach(CustomModel.contextWindowOptions, id: \.self) { value in
                        Text(value >= 1_000_000 ? "\(value / 1_000_000)M" : "\(value / 1_000)K")
                            .tag(value)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(model)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.validationErrors.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 430)
    }
}

// MARK: - 编辑 Provider sheet

struct EditProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tapgoFontScale) private var appFontScale
    @State private var displayName: String
    @State private var brand: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var models: [ProviderModel]
    private let originalID: String
    private let isBuiltin: Bool
    private let onSave: (Provider) -> Void

    init(provider: Provider?, onSave: @escaping (Provider) -> Void) {
        if let p = provider {
            _displayName = State(initialValue: p.displayName)
            _brand = State(initialValue: p.brand)
            _baseURL = State(initialValue: p.baseURL)
            _apiKey = State(initialValue: p.apiKey)
            _models = State(initialValue: p.models)
            self.originalID = p.id
            self.isBuiltin = p.isBuiltin
        } else {
            _displayName = State(initialValue: "")
            _brand = State(initialValue: "")
            _baseURL = State(initialValue: "https://")
            _apiKey = State(initialValue: "")
            _models = State(initialValue: [
                ProviderModel(
                    id: "model-" + UUID().uuidString.prefix(6).uppercased(),
                    displayName: "", apiModel: "",
                    contextWindow: 128_000, isCustom: true)
            ])
            self.originalID = ""
            self.isBuiltin = false
        }
        self.onSave = onSave
    }

    private var errors: [String] {
        provider.validationErrors(apiKeyRequired: !isBuiltin)
    }

    private var provider: Provider {
        Provider(
            id: originalID.isEmpty
                ? "custom-" + UUID().uuidString.prefix(8).uppercased()
                : originalID,
            displayName: displayName,
            brand: brand,
            baseURL: baseURL,
            apiKey: apiKey,
            models: models,
            builtInKindRaw: isBuiltin
                ? TapgoProviderKind(rawValue: originalID.replacingOccurrences(of: "builtin:", with: ""))?.rawValue
                : nil
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(isBuiltin
                 ? "配置 \(displayName)"
                 : (originalID.isEmpty ? L10n.providerAddProvider : "编辑 \(displayName)"))
                .font(AppFont.scaled(.headline, multiplier: 1)).bold()
            if isBuiltin {
                Text("内置供应商仅可更新 Key；其他字段不可修改。")
                    .font(AppFont.scaled(.caption, multiplier: 1))
                    .foregroundStyle(.secondary)
            }
            Form {
                TextField("显示名", text: $displayName)
                    .disabled(isBuiltin)
                TextField("品牌", text: $brand)
                    .disabled(isBuiltin)
                TextField("端点 Base URL", text: $baseURL)
                SecureField("API Key", text: $apiKey)
                Section("模型") {
                    ForEach(Array(models.enumerated()), id: \.element.id) { idx, m in
                        modelEditorRow(idx: idx, model: m)
                    }
                    Button {
                        models.append(ProviderModel(
                            id: "model-" + UUID().uuidString.prefix(6).uppercased(),
                            displayName: "", apiModel: "",
                            contextWindow: 128_000, isCustom: true))
                    } label: {
                        Label("添加模型", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)

            if !errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(errors.prefix(4), id: \.self) { e in
                        Label(e, systemImage: "exclamationmark.circle.fill")
                            .font(AppFont.scaled(.caption, multiplier: 1))
                            .foregroundStyle(DSHTheme.error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(L10n.cancel) { dismiss() }
                Button(L10n.save) {
                    onSave(provider)
                    dismiss()
                }
                .disabled(!errors.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder
    private func modelEditorRow(idx: Int, model: ProviderModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("API 模型 ID", text: Binding(
                    get: { model.apiModel },
                    set: { newValue in
                        models[idx].apiModel = newValue
                    }
                ))
                TextField("显示名", text: Binding(
                    get: { model.displayName },
                    set: { newValue in
                        models[idx].displayName = newValue
                    }
                ))
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(CustomModel.contextWindowOptions, id: \.self) { win in
                        Button("\(win / (win >= 1_000_000 ? 1_000_000 : 1_000))\(win >= 1_000_000 ? "M" : "K")") {
                            models[idx].contextWindow = win
                        }
                    }
                } label: {
                    Text("上下文：\(model.contextWindow)")
                }
                Spacer()
                Button(role: .destructive) {
                    models.remove(at: idx)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(models.count <= 1)
            }
        }
        .padding(.vertical, 4)
    }
}
