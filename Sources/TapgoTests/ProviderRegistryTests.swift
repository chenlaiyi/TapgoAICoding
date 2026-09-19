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

    // MARK: - 内置 Provider 自动补全
    registry.ensureBuiltinProviders()
    t.expectEqual(registry.builtinProviders.count, 1,
                  "provider: 内置 1 个供应商（DeepSeek）")
    t.expectEqual(registry.customProviders.count, 0,
                  "provider: 起初无自定义 Provider")
    t.expectEqual(registry.resolveSelectedProvider().id,
                  TapgoProviderKind.deepseek.registryID,
                  "provider: resolveSelectedProvider 落到唯一内置（DeepSeek）")

    // MARK: - DeepSeek 下挂 2 个默认模型
    let deepseek = registry.provider(id: TapgoProviderKind.deepseek.registryID)!
    t.expectEqual(deepseek.models.count, 2,
                  "provider: DeepSeek 默认挂 2 个模型（flash / pro）")
    t.expect(deepseek.models.contains(where: { $0.apiModel == "deepseek-flash" }),
             "provider: DeepSeek flash apiModel 为 deepseek-flash")

    // MARK: - 自定义 Provider 增删改查
    let custom = Provider(
        id: "custom-TEST",
        displayName: "我的代理",
        brand: "Mine",
        baseURL: "https://proxy.example.com/v1",
        apiKey: "sk-x",
        models: [
            ProviderModel(
                id: "custom-TEST::m1",
                displayName: "Proxy Model",
                apiModel: "vendor/model",
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
        ProviderModel(id: "custom-TEST::m2",
                      displayName: "Proxy Model 2",
                      apiModel: "vendor/model2",
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
                  "custom-TEST::m1",
                  "provider: setSelectedModel 写入 provider→model 映射")
    t.expectEqual(registry.resolveSelectedModel(for: edited).apiModel,
                  "vendor/model",
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
    let deepseek2 = registry.provider(id: TapgoProviderKind.deepseek.registryID)!
    var tryEditDisplayName = deepseek2
    tryEditDisplayName.displayName = "改名"
    registry.addOrUpdate(tryEditDisplayName)
    let deepseek3 = registry.provider(id: TapgoProviderKind.deepseek.registryID)!
    t.expectEqual(deepseek3.displayName, "DeepSeek",
                  "provider: 内置 displayName 不允许改")
    t.expectEqual(deepseek3.brand, "DeepSeek",
                  "provider: 内置 brand 不允许改")
    // 但 Key / baseURL / models 允许改
    var tryEditKey = deepseek3
    tryEditKey.apiKey = "sk-builtin"
    registry.addOrUpdate(tryEditKey)
    t.expectEqual(registry.provider(id: TapgoProviderKind.deepseek.registryID)?.apiKey,
                  "sk-builtin",
                  "provider: 内置 Key 允许改")

    // MARK: - 额度通道按内置供应商，不按可改名 apiModel（v0.5.315）
    t.expectEqual(deepseek.quotaChannel, .deepseek,
                  "quota: DeepSeek Provider 路由到余额接口")
    var renamedDeepSeek = deepseek3
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
    let order = [
        TapgoProviderKind.deepseek.registryID,
    ]
    registry.reorderProviders(order)
    t.expectEqual(registry.providers.map { $0.id }, order,
                  "provider: reorderProviders 调整顺序")

    // MARK: - 持久化往返
    let reloaded = ProviderRegistry(fileURL: file)
    t.expectEqual(reloaded.providers.count, 1,
                  "provider: 重启后 1 个内置 Provider")
    t.expectEqual(reloaded.providers.first?.id,
                  TapgoProviderKind.deepseek.registryID,
                  "provider: 顺序持久化")
}

@MainActor
func runProviderRegistryMigration(_ t: TestRunner) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-providers-mig-\(UUID().uuidString)", isDirectory: true)
    let file = dir.appendingPathComponent("provider-registry.json")
    let legacyFile = dir.appendingPathComponent("model-registry.json")
    let authDS = dir.appendingPathComponent("auth-deepseek.json")
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

    // 写入 auth-deepseek.json
    let dsKey = "{\"OPENAI_API_KEY\":\"sk-ds-test\"}"
    try? dsKey.data(using: .utf8)?.write(to: authDS)

    let registry = ProviderRegistry(
        fileURL: file,
        legacyModelRegistryURL: legacyFile,
        legacyAuthPaths: [authDS]
    )
    let migrated = registry.migrateFromLegacyIfNeeded()
    t.expect(migrated, "provider: migrateFromLegacyIfNeeded 返回 true")
    t.expect(!FileManager.default.fileExists(atPath: legacyFile.path),
             "provider: 旧 model-registry.json 移到 backups")
    t.expect(!FileManager.default.fileExists(atPath: authDS.path),
             "provider: 旧 auth-deepseek.json 移到 backups")

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

    // DeepSeek 内置 Key 应从 auth-deepseek.json 合并
    let ds = registry.provider(id: TapgoProviderKind.deepseek.registryID)!
    t.expectEqual(ds.apiKey, "sk-ds-test",
                  "provider: DeepSeek Key 从 auth-deepseek.json 合并")

    // 1 个内置 + 2 个自定义 = 3
    t.expectEqual(registry.providers.count, 3,
                  "provider: 迁移后 3 个 Provider（1 内置 + 2 自定义）")

    // 再次调用 migrateFromLegacyIfNeeded → 返回 false（不再迁移）
    let again = registry.migrateFromLegacyIfNeeded()
    t.expect(!again, "provider: 重复 migrate 不再触发")
}
