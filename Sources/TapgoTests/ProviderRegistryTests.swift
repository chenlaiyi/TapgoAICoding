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
    t.expectEqual(registry.builtinProviders.count, 3,
                  "provider: 内置 3 个供应商（智谱 / MiniMax / DeepSeek）")
    t.expectEqual(registry.customProviders.count, 0,
                  "provider: 起初无自定义 Provider")
    t.expectEqual(registry.resolveSelectedProvider().id,
                  TapgoProviderKind.zhipu.registryID,
                  "provider: resolveSelectedProvider 落到第一个内置（智谱）")

    // MARK: - 智谱下挂 3 个默认模型
    let zhipu = registry.provider(id: TapgoProviderKind.zhipu.registryID)!
    t.expectEqual(zhipu.models.count, 3,
                  "provider: 智谱默认挂 3 个模型（GLM-5.3 / -Flash / -Turbo）")
    let turbo = zhipu.models.first(where: { $0.apiModel == "GLM-5-Turbo" })!
    t.expectEqual(turbo.contextWindow, 200_000,
                  "provider: GLM-5-Turbo 上下文窗口 200K")

    // MARK: - 自定义 Provider 增删改查
    let custom = Provider(
        id: "custom-TEST",
        displayName: "我的 GLM 代理",
        brand: "Mine",
        baseURL: "https://proxy.example.com/v1",
        apiKey: "sk-x",
        models: [
            ProviderModel(
                id: "custom-TEST::glm-5.3",
                displayName: "GLM-5.3 (代理)",
                apiModel: "GLM-5.3",
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
        ProviderModel(id: "custom-TEST::glm-5.3-flash",
                      displayName: "GLM-5.3-Flash (代理)",
                      apiModel: "GLM-5.3-Flash",
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
                  "custom-TEST::glm-5.3",
                  "provider: setSelectedModel 写入 provider→model 映射")
    t.expectEqual(registry.resolveSelectedModel(for: edited).apiModel,
                  "GLM-5.3",
                  "provider: resolveSelectedModel 取回正确 model")

    // MARK: - 内置 Provider 拒绝删除
    let removedBuiltin = registry.removeProvider(id: TapgoProviderKind.zhipu.registryID)
    t.expect(!removedBuiltin,
             "provider: 内置 Provider 不允许删除（removeProvider 返回 false）")
    t.expect(registry.provider(id: TapgoProviderKind.zhipu.registryID) != nil,
             "provider: 内置 Provider 仍在 state 中")

    // MARK: - 自定义 Provider 删除
    let removedCustom = registry.removeProvider(id: "custom-TEST")
    t.expect(removedCustom, "provider: 自定义 Provider 删除成功")
    t.expect(registry.provider(id: "custom-TEST") == nil,
             "provider: 自定义 Provider 删除后查不到")

    // MARK: - 内置 Provider 字段锁
    let zhipu2 = registry.provider(id: TapgoProviderKind.zhipu.registryID)!
    var tryEditDisplayName = zhipu2
    tryEditDisplayName.displayName = "改名"
    registry.addOrUpdate(tryEditDisplayName)
    let zhipu3 = registry.provider(id: TapgoProviderKind.zhipu.registryID)!
    t.expectEqual(zhipu3.displayName, "智谱",
                  "provider: 内置 displayName 不允许改")
    t.expectEqual(zhipu3.brand, "Zhipu",
                  "provider: 内置 brand 不允许改")
    t.expectEqual(zhipu3.apiKey, "",
                  "provider: 内置 Key 仍空")
    // 但 Key / baseURL / models 允许改
    var tryEditKey = zhipu3
    tryEditKey.apiKey = "sk-builtin"
    registry.addOrUpdate(tryEditKey)
    t.expectEqual(registry.provider(id: TapgoProviderKind.zhipu.registryID)?.apiKey,
                  "sk-builtin",
                  "provider: 内置 Key 允许改")

    // MARK: - 内置 Provider 不能改 baseURL 锁校验（v0.5.53 设计）：允许
    // （baseURL 已被内置 / 用户双轨允许），这里只验不会因为校验失败被拒。
    var tryEditURL = tryEditKey
    tryEditURL.baseURL = "not-a-url"
    registry.addOrUpdate(tryEditURL)
    t.expectEqual(registry.provider(id: TapgoProviderKind.zhipu.registryID)?.baseURL,
                  "not-a-url",
                  "provider: 内置 baseURL 允许改（保留 v0.5.52 端点覆盖行为）")

    // MARK: - reorderProviders（UI 占位）
    let order = [
        TapgoProviderKind.deepseek.registryID,
        TapgoProviderKind.zhipu.registryID,
        TapgoProviderKind.minimax.registryID,
    ]
    registry.reorderProviders(order)
    t.expectEqual(registry.providers.map { $0.id }, order,
                  "provider: reorderProviders 调整顺序")

    // MARK: - 持久化往返
    let reloaded = ProviderRegistry(fileURL: file)
    t.expectEqual(reloaded.providers.count, 3,
                  "provider: 重启后 3 个内置 Provider")
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

    // 智谱内置 Key 应从 auth-glm.json 合并
    let zhipu = registry.provider(id: TapgoProviderKind.zhipu.registryID)!
    t.expectEqual(zhipu.apiKey, "sk-glm-test",
                  "provider: 智谱 Key 从 auth-glm.json 合并")

    // 3 个内置 + 2 个自定义 = 5
    t.expectEqual(registry.providers.count, 5,
                  "provider: 迁移后 5 个 Provider（3 内置 + 2 自定义）")

    // 再次调用 migrateFromLegacyIfNeeded → 返回 false（不再迁移）
    let again = registry.migrateFromLegacyIfNeeded()
    t.expect(!again, "provider: 重复 migrate 不再触发")
}
