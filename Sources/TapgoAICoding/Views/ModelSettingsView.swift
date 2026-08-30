// TapgoAICoding/Views/ModelSettingsView.swift
// v0.5.53 起：模型设置 1:1 仿造 ZCode —— 把"供应商 / 模型"两层结构搬到
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 顶部操作条
            HStack {
                Button {
                    reloadProviders()
                } label: {
                    Label(L10n.providerRefresh, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    dragReorderHintShown = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        dragReorderHintShown = false
                    }
                } label: {
                    Label(L10n.providerDragReorder, systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    addingProvider = true
                } label: {
                    Label(L10n.providerAddProvider, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            if dragReorderHintShown {
                Text(L10n.providerDragHint)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.warn)
            }

            // 「智谱」Section：内置 Provider
            providerSection(
                title: L10n.providerZhipuSection,
                providers: builtinProviders,
                showBuiltinBadge: true
            )

            // 「自定义供应商」Section
            providerSection(
                title: L10n.providerCustomSection,
                providers: customProviders,
                showBuiltinBadge: false
            )
        }
        .onAppear {
            reloadProviders()
            let r = TapgoConfig.providerRegistry()
            _ = r.migrateFromLegacyIfNeeded()
            r.ensureBuiltinProviders()
            let sel = r.resolveSelectedProvider()
            let model = r.resolveSelectedModel(for: sel)
            selectedProviderModel = "\(sel.id)::\(model.id)"
        }
        .sheet(item: $editingProvider) { p in
            EditProviderSheet(provider: p) { saved in
                saveProvider(saved)
            }
        }
        .sheet(isPresented: $addingProvider) {
            EditProviderSheet(provider: nil) { saved in
                saveProvider(saved)
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
    }

    // MARK: - Section

    @ViewBuilder
    private func providerSection(
        title: String,
        providers: [Provider],
        showBuiltinBadge: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier).weight(.semibold))
                if showBuiltinBadge {
                    Label(L10n.providerBuiltinBadge, systemImage: "checkmark.seal.fill")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.success)
                }
                Spacer()
                Text("\(providers.count)")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)

            if providers.isEmpty {
                Text(title == L10n.providerCustomSection ? "尚未添加自定义供应商" : "")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ForEach(Array(providers.enumerated()), id: \.element.id) { idx, p in
                    if idx > 0 { Divider() }
                    providerCard(p, isBuiltin: p.isBuiltin)
                }
            }
        }
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
                .strokeBorder(DSHTheme.border, lineWidth: 1)
        )
    }

    // MARK: - 单个 Provider 卡

    @ViewBuilder
    private func providerCard(_ provider: Provider, isBuiltin: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider 头部
            HStack(spacing: 8) {
                Text(provider.displayName)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.semibold))
                Text(provider.brand)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !isBuiltin {
                    Button {
                        editingProvider = provider
                    } label: {
                        Label(L10n.providerEditConfig, systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Provider 下每个 Model 行
            ForEach(provider.models) { model in
                modelRow(provider: provider, model: model)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func modelRow(provider: Provider, model: ProviderModel) -> some View {
        let composite = "\(provider.id)::\(model.id)"
        let isSelected = composite == selectedProviderModel
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // API 模型 ID（editable TextField）
                TextField("", text: Binding(
                    get: { model.apiModel },
                    set: { newValue in
                        var m = model
                        m.apiModel = newValue
                        var p = provider
                        if let idx = p.models.firstIndex(where: { $0.id == m.id }) {
                            p.models[idx] = m
                        }
                        TapgoConfig.providerRegistry().updateModels(p.models, for: p.id)
                        reloadProviders()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .disabled(provider.isBuiltin)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))

                // 上下文窗口
                Menu {
                    ForEach(CustomModel.contextWindowOptions, id: \.self) { win in
                        Button {
                            var m = model
                            m.contextWindow = win
                            var p = provider
                            if let idx = p.models.firstIndex(where: { $0.id == m.id }) {
                                p.models[idx] = m
                            }
                            TapgoConfig.providerRegistry().updateModels(p.models, for: p.id)
                            reloadProviders()
                        } label: {
                            Text(contextWindowLabel(win))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(String(format: L10n.providerContextWindow,
                                    contextWindowLabel(model.contextWindow)))
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .disabled(provider.isBuiltin)

                Spacer()

                if isSelected {
                    Label(L10n.modelCurrentSelection, systemImage: "checkmark")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DSHTheme.brandSoft, in: Capsule())
                        .foregroundStyle(DSHTheme.brand)
                }

                // 测试
                Button(L10n.modelTest) {
                    runTest(provider: provider, model: model)
                }
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .buttonStyle(.borderless)

                // 设为默认（点击主行区域）
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !isSelected {
                    selectProviderModel(provider: provider, model: model)
                }
            }

            // 测试结果内联
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
            }
        }
        .padding(.vertical, 6)
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

    private func selectProviderModel(provider: Provider, model: ProviderModel) {
        let composite = "\(provider.id)::\(model.id)"
        selectedProviderModel = composite
        // 同步给 v0.5.52 旧 UserDefaults（thread/start 路径用 builtin:<slug>
        // 或 custom-XXX），保持选择态一致
        let resolved = resolveLegacyRaw(for: provider, model: model)
        selectedModelRaw = resolved
        TapgoConfig.setSelectedModel(id: resolved)
        let registry = TapgoConfig.providerRegistry()
        registry.setSelectedProvider(id: provider.id)
        registry.setSelectedModel(model, for: provider)
    }

    /// 把 Provider / Model 映射回 v0.5.52 的 selectedModelKey 值。
    private func resolveLegacyRaw(for provider: Provider, model: ProviderModel) -> String {
        if provider.isBuiltin, let kind = provider.builtInKind {
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
                    .disabled(isBuiltin)
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
                    .disabled(isBuiltin)
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
                .disabled(isBuiltin)
                TextField("显示名", text: Binding(
                    get: { model.displayName },
                    set: { newValue in
                        models[idx].displayName = newValue
                    }
                ))
                .disabled(isBuiltin)
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
                .disabled(isBuiltin)
                Spacer()
                Button(role: .destructive) {
                    models.remove(at: idx)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(isBuiltin)
            }
        }
        .padding(.vertical, 4)
    }
}
