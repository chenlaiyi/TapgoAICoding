// TapgoTests/ProviderRegistryPruneTests.swift
// v0.5.319：供应商精简后，旧 provider-registry.json 里遗留的
// `builtin:zhipu` / `builtin:minimax` 必须被清理掉，不能以「自定义
// Provider」的身份继续活着（否则模型选择器里还挂着 GLM / MiniMax，
// config.toml 还会渲染出 `[model_providers.builtin:zhipu]` 这种段名）。

import Foundation
@testable import TapgoCore

@MainActor
func runProviderRegistryRetiredBuiltinPrune(_ t: TestRunner) {
    t.section("ProviderRegistry: 下线内置供应商清理")

    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-prune-\(UUID().uuidString)", isDirectory: true)
    let file = dir.appendingPathComponent("provider-registry.json")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // 造一份「精简前」的注册表：zhipu / minimax 遗留内置 + deepseek + 自定义。
    let legacy = """
    {
      "providers": [
        {"id":"builtin:zhipu","displayName":"智谱","brand":"Zhipu","baseURL":"https://open.bigmodel.cn/api/v1","apiKey":"k1","builtInKindRaw":"zhipu","models":[]},
        {"id":"builtin:minimax","displayName":"MiniMax","brand":"MiniMax","baseURL":"https://api.minimaxi.com/v1","apiKey":"k2","builtInKindRaw":"minimax","models":[]},
        {"id":"builtin:deepseek","displayName":"DeepSeek","brand":"DeepSeek","baseURL":"https://api.deepseek.com","builtInKindRaw":"deepseek","apiKey":"sk-test","models":[]},
        {"id":"custom-TEST","displayName":"我的代理","brand":"Mine","baseURL":"https://proxy.example.com/v1","apiKey":"k3","models":[]}
      ],
      "selectedProviderID": "builtin:zhipu",
      "selectedModelPerProvider": {
        "builtin:zhipu": "builtin:zhipu::GLM-5.3-Flash",
        "custom-TEST": "custom-TEST::m"
      }
    }
    """
    try? legacy.write(to: file, atomically: true, encoding: .utf8)

    let registry = ProviderRegistry(fileURL: file)
    t.expect(registry.provider(id: "builtin:zhipu") != nil,
             "前置：遗留 builtin:zhipu 能被解码出来（未知 kind → 当作自定义）")

    registry.ensureBuiltinProviders()

    t.expectNil(registry.provider(id: "builtin:zhipu"), "遗留 builtin:zhipu 已被清理")
    t.expectNil(registry.provider(id: "builtin:minimax"), "遗留 builtin:minimax 已被清理")
    t.expectNotNil(registry.provider(id: "builtin:deepseek"), "DeepSeek 内置保留")
    t.expectNotNil(registry.provider(id: "custom-TEST"), "用户自建 Provider 不受影响")
    t.expectEqual(registry.builtinProviders.count, 1, "内置 Provider 只剩 DeepSeek 一个")
    t.expectEqual(registry.resolveSelectedProvider().id, "builtin:deepseek",
                  "选中态落到 DeepSeek（原选中项已被清理）")

    // 清理结果必须落盘：重新读一遍文件，不能只改内存。
    let reloaded = ProviderRegistry(fileURL: file)
    reloaded.ensureBuiltinProviders()
    t.expectNil(reloaded.provider(id: "builtin:zhipu"), "清理结果已落盘（重新加载仍无 zhipu）")
    t.expectNil(reloaded.provider(id: "builtin:minimax"), "清理结果已落盘（重新加载仍无 minimax）")
    t.expectEqual(reloaded.providers.count, 2, "落盘后 provider 数 = DeepSeek + custom-TEST")
}
