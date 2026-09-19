// TapgoTests/ProviderRegistryTests.swift
// v0.5.53 起：Provider / ProviderModel / TapgoProviderKind / ProviderRegistry
// 的单测。覆盖 addOrUpdate / removeProvider / setSelectedProvider /
// setSelectedModel / reorderProviders + v0.5.52 旧 model-registry.json 迁移。

import Foundation
@testable import TapgoCore

@MainActor
func runProviderRegistry(_ t: TestRunner) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-providers-\(UUID().uuidString)", isDirectory: true)
    let file = dir.appendingPathComponent("provider-registry.json")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let registry = ProviderRegistry(fileURL: file)

    // MARK: - 内置 Provider 自动补全（v0.5.117 起只保留 DeepSeek）
    registry.ensureBuiltinProviders()
    t.expectEqual(registry.builtinProviders.count, 1,
                  "provider: 内置供应商只保留 DeepSeek（智谱 / MiniMax 已下线）")
    t.expectEqual(registry.builtinProviders.first?.id,
                  TapgoProviderKind.deepseek.registryID,
                  "provider: 唯一内置 Provider 是 DeepSeek")
    t.expectEqual(registry.customProviders.count, 0,
                  "provider: 起初无自定义 Provider")
    t.expectEqual(registry.resolveSelectedProvider().id,
                  TapgoProviderKind.deepseek.registryID,
                  "provider: resolveSelectedProvider 落到 DeepSeek")

    // MARK: - DeepSeek 下挂 3 个默认模型
    let deepSeek = registry.provider(id: TapgoProviderKind.deepseek.registryID)!
    t.expectEqual(deepSeek.models.count, 2,
                  "provider: DeepSeek 默认挂 2 个模型（Flash / Pro）")
    // DeepSeek API 只接受 `deepseek-flash`；v0.5.319 起 apiModel 用真实
    // 名字，id 仍保留 builtin:deepseek::deepseek-v4-flash 以兼容选中态。
    t.expect(deepSeek.models.contains { $0.apiModel == "deepseek-flash" },
             "provider: DeepSeek 默认模型用 API 接受的 deepseek-flash")

    // MARK: - v0.5.117：名单外的内置供应商在补全时被清除
    let staleState = ProviderRegistryState(
        providers: [.builtin(.zhipu), .builtin(.minimax), .builtin(.deepseek)],
        selectedProviderID: TapgoProviderKind.zhipu.registryID,
        selectedModelPerProvider: [
            TapgoProviderKind.zhipu.registryID: "builtin:zhipu::GLM-5.3"
        ])
    let staleFile = dir.appendingPathComponent("stale-registry.json")
    if let data = try? JSONEncoder().encode(staleState) {
        try? data.write(to: staleFile)
    }
    let staleRegistry = ProviderRegistry(fileURL: staleFile)
    t.expectEqual(staleRegistry.providers.count, 3,
                  "provider: 旧注册表仍能解码含智谱 / MiniMax 的历史数据")
    staleRegistry.ensureBuiltinProviders()
    t.expectEqual(staleRegistry.providers.map { $0.id },
                  [TapgoProviderKind.deepseek.registryID],
                  "provider: ensureBuiltinProviders 清除名单外的内置供应商")
    t.expectEqual(staleRegistry.state.selectedProviderID, "",
                  "provider: 指向已清除供应商的选中态被重置")
    t.expect(staleRegistry.state.selectedModelPerProvider.isEmpty,
             "provider: 已清除供应商的模型选中态一并清掉")

    // MARK: - 自定义 Provider 增删改查
    let custom = Provider(
        id: "custom-TEST",
        displayName: "我的代理",
        brand: "Mine",
        baseURL: "https://proxy.example.com/v1",
        apiKey: "sk-x",
        models: [
            ProviderModel(
                id: "custom-TEST::probe-model",
                displayName: "Probe (代理)",
                apiModel: "probe-model",
                contextWindow: 128_000,
                isCustom: true)
        ],
        builtInKindRaw: nil
    )
    registry.addOrUpdate(custom)
    t.expectEqual(registry.customProviders.count, 1,
                  "provider: 新增自定义 Provider")
    t.expectEqual(registry.provider(id: "custom-TEST")?.apiKey, "sk-x",
                  "provider: 自定义 Provider Key 持久化")

    // 编辑：更新 Key + models
    var edited = custom
    edited.apiKey = "sk-y"
    edited.models = custom.models + [
        ProviderModel(id: "custom-TEST::extra-model",
                      displayName: "Extra (代理)",
                      apiModel: "extra-model",
                      contextWindow: 128_000,
                      isCustom: true)
    ]
    registry.addOrUpdate(edited)
    t.expectEqual(registry.provider(id: "custom-TEST")?.apiKey, "sk-y",
                  "provider: 同一 id 二次 addOrUpdate = 替换")
    t.expectEqual(registry.provider(id: "custom-TEST")?.models.count, 2,
                  "provider: addOrUpdate 合并 models")

    // MARK: - setSelectedProvider / setSelectedModel
    registry.setSelectedProvider(id: "custom-TEST")
    t.expectEqual(registry.state.selectedProviderID, "custom-TEST",
                  "provider: setSelectedProvider 写入选中态")
    let model = edited.models[0]
    registry.setSelectedModel(model, for: edited)
    t.expectEqual(registry.state.selectedModelPerProvider["custom-TEST"],
                  "custom-TEST::probe-model",
                  "provider: setSelectedModel 写入 provider→model 映射")
    t.expectEqual(registry.resolveSelectedModel(for: edited).apiModel,
                  "probe-model",
                  "provider: resolveSelectedModel 取回正确 model")

    // MARK: - 内置 Provider 拒绝删除
    let removedBuiltin = registry.removeProvider(id: TapgoProviderKind.deepseek.registryID)
    t.expect(!removedBuiltin,
             "provider: 内置 Provider 不允许删除（removeProvider 返回 false）")
    t.expect(registry.provider(id: TapgoProviderKind.deepseek.registryID) != nil,
             "provider: 内置 Provider 仍在 state 中")

    // MARK: - 自定义 Provider 删除
    let removedCustom = registry.removeProvider(id: "custom-TEST")
    t.expect(removedCustom, "provider: 自定义 Provider 删除成功")
    t.expect(registry.provider(id: "custom-TEST") == nil,
             "provider: 自定义 Provider 删除后查不到")

    // MARK: - 内置 Provider 字段锁
    let builtin = registry.provider(id: TapgoProviderKind.deepseek.registryID)!
    var tryEditDisplayName = builtin
    tryEditDisplayName.displayName = "改名"
    registry.addOrUpdate(tryEditDisplayName)
    let builtinAfter = registry.provider(id: TapgoProviderKind.deepseek.registryID)!
    t.expectEqual(builtinAfter.displayName, "DeepSeek",
                  "provider: 内置 displayName 不允许改")
    t.expectEqual(builtinAfter.brand, "DeepSeek",
                  "provider: 内置 brand 不允许改")
    t.expectEqual(builtinAfter.apiKey, "",
                  "provider: 内置 Key 仍空")
    // 但 Key / baseURL / models 允许改
    var tryEditKey = builtinAfter
    tryEditKey.apiKey = "sk-builtin"
    registry.addOrUpdate(tryEditKey)
    t.expectEqual(registry.provider(id: TapgoProviderKind.deepseek.registryID)?.apiKey,
                  "sk-builtin",
                  "provider: 内置 Key 允许改")

    // MARK: - 内置 Provider 不能改 baseURL 锁校验（v0.5.53 设计）：允许
    // （baseURL 已被内置 / 用户双轨允许），这里只验不会因为校验失败被拒。
    var tryEditURL = tryEditKey
    tryEditURL.baseURL = "not-a-url"
    registry.addOrUpdate(tryEditURL)
    t.expectEqual(registry.provider(id: TapgoProviderKind.deepseek.registryID)?.baseURL,
                  "not-a-url",
                  "provider: 内置 baseURL 允许改（保留 v0.5.52 端点覆盖行为）")

    // MARK: - 额度通道按内置供应商，不按可改名 apiModel（v0.5.315）
    let deepSeekFresh = registry.provider(id: TapgoProviderKind.deepseek.registryID)!
    t.expectEqual(deepSeekFresh.quotaChannel, .deepseek,
                  "quota: DeepSeek Provider 路由到余额接口")
    var renamedDeepSeek = deepSeekFresh
    renamedDeepSeek.models = [
        ProviderModel(
            id: "builtin:deepseek::deepseek-v4-pro",
            displayName: "DeepSeek V4.1 flash",
            apiModel: "deepseek-v4.1-flash",
            contextWindow: 1_048_576,
            isCustom: false)
    ]
    registry.addOrUpdate(renamedDeepSeek)
    registry.setSelectedProvider(id: renamedDeepSeek.id)
    registry.setSelectedModel(renamedDeepSeek.models[0], for: renamedDeepSeek)
    let renamedSelected = registry.resolveSelectedProvider()
    t.expectEqual(renamedSelected.builtInKind, .deepseek,
                  "quota: 模型 slug 改名后仍保留 DeepSeek 供应商身份")
    t.expectEqual(renamedSelected.quotaChannel, .deepseek,
                  "quota: V4.1 改名不影响 DeepSeek 余额通道")
    t.expectEqual(registry.resolveSelectedModel(for: renamedSelected).apiModel,
                  "deepseek-v4.1-flash",
                  "quota: 仍返回用户改后的实际模型 slug")

    // MARK: - reorderProviders（UI 占位）
    registry.addOrUpdate(custom)
    let order = ["custom-TEST", TapgoProviderKind.deepseek.registryID]
    registry.reorderProviders(order)
    t.expectEqual(registry.providers.map { $0.id }, order,
                  "provider: reorderProviders 调整顺序")

    // MARK: - 持久化往返
    let reloaded = ProviderRegistry(fileURL: file)
    reloaded.ensureBuiltinProviders()
    t.expectEqual(reloaded.providers.count, 2,
                  "provider: 重启后保留 1 个内置 + 1 个自定义")
    t.expectEqual(reloaded.providers.first?.id,
                  "custom-TEST",
                  "provider: 顺序持久化")
}

@MainActor
func runProviderRegistryMigration(_ t: TestRunner) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-providers-mig-\(UUID().uuidString)", isDirectory: true)
    let file = dir.appendingPathComponent("provider-registry.json")
    let legacyFile = dir.appendingPathComponent("model-registry.json")
    let authGLM = dir.appendingPathComponent("auth-glm.json")
    defer { try? FileManager.default.removeItem(at: dir) }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // 写入 v0.5.52 旧 model-registry.json
    let customA = CustomModel(
        id: "custom-A", displayName: "A", apiModel: "a",
        brand: "Brand", baseURL: "https://a.example.com/v1",
        apiKey: "sk-a", contextWindow: 128_000)
    let customB = CustomModel(
        id: "custom-B", displayName: "B", apiModel: "b",
        brand: "Brand", baseURL: "https://b.example.com/v1",
        apiKey: "sk-b", contextWindow: 256_000)
    let legacyData = try? JSONEncoder().encode(["customModels": [customA, customB]])
    try? legacyData?.write(to: legacyFile)

    // 写入 auth-glm.json
    let glmKey = "{\"OPENAI_API_KEY\":\"sk-glm-test\"}"
    try? glmKey.data(using: .utf8)?.write(to: authGLM)

    let registry = ProviderRegistry(
        fileURL: file,
        legacyModelRegistryURL: legacyFile,
        legacyAuthPaths: [authGLM]
    )
    let migrated = registry.migrateFromLegacyIfNeeded()
    t.expect(migrated, "provider: migrateFromLegacyIfNeeded 返回 true")
    t.expect(!FileManager.default.fileExists(atPath: legacyFile.path),
             "provider: 旧 model-registry.json 移到 backups")
    t.expect(!FileManager.default.fileExists(atPath: authGLM.path),
             "provider: 旧 auth-glm.json 移到 backups")

    // 2 个自定义 Provider，每个 1 个模型
    t.expectEqual(registry.customProviders.count, 2,
                  "provider: 迁移后 2 个自定义 Provider")
    let provA = registry.customProviders.first(where: { $0.displayName == "A" })!
    t.expectEqual(provA.baseURL, "https://a.example.com/v1",
                  "provider: 自定义 Provider baseURL 来自旧字段")
    t.expectEqual(provA.apiKey, "sk-a",
                  "provider: 自定义 Provider Key 来自旧字段")
    t.expectEqual(provA.models.first?.apiModel, "a",
                  "provider: 自定义 Provider 内嵌 1 个模型")

    // v0.5.117：智谱 / MiniMax 已从启用名单移除，迁移不再补回这两个内置
    // 供应商；auth-glm.json 的 Key 不合并进注册表（原文件已被移到
    // backups/ 保留，需要恢复时从备份取回）。
    t.expectNil(registry.provider(id: TapgoProviderKind.zhipu.registryID),
                "provider: 迁移不再补回已下线的智谱")
    t.expectEqual(registry.builtinProviders.map { $0.id },
                  [TapgoProviderKind.deepseek.registryID],
                  "provider: 迁移后内置只剩 DeepSeek")

    // 1 个内置 + 2 个自定义 = 3
    t.expectEqual(registry.providers.count, 3,
                  "provider: 迁移后 3 个 Provider（1 内置 + 2 自定义）")

    // 再次调用 migrateFromLegacyIfNeeded → 返回 false（不再迁移）
    let again = registry.migrateFromLegacyIfNeeded()
    t.expect(!again, "provider: 重复 migrate 不再触发")
}
