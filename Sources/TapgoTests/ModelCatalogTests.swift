// TapgoTests/ModelCatalogTests.swift
import Foundation
import TapgoCore

@MainActor
func runModelCatalog(_ t: TestRunner) {
    // 模型 → provider 映射: thread/start 的 modelProvider 参数必须与
    // config.toml 模板里 [model_providers.<id>] 的段名一致, 否则 harness
    // 找不到 provider 直接报错。
    t.expectEqual(TapgoModel.minimaxM3.providerId, "minimax",
                  "model: MiniMax-M3 maps to provider minimax")
    t.expectEqual(TapgoModel.glm53Flash.providerId, "glm",
                  "model: GLM-5.3-Flash maps to provider glm")

    // 端点: GLM 必须指向智谱给 Codex 的 OpenAI Responses 协议专属端点
    // (docs.bigmodel.cn/cn/coding-plan/tool/codex); MiniMax 保持官方 v1。
    t.expectEqual(TapgoModel.glm53Flash.defaultBaseURL, "https://open.bigmodel.cn/api/v1",
                  "model: GLM-5.3-Flash pins the official Responses endpoint")
    t.expectEqual(TapgoModel.minimaxM3.defaultBaseURL, "https://api.minimaxi.com/v1",
                  "model: MiniMax-M3 pins the official china endpoint")

    // 两个模型上下文一致 (1M), config.toml 的 model_context_window 不用改。
    for model in TapgoModel.allCases {
        t.expectEqual(model.contextWindow, 1_000_000,
                      "model: \(model.rawValue) exposes 1M context window")
    }

    // 目录 JSON: 合法、两个模型都在列、自述与模型对应。
    let catalog = TapgoModel.catalogJSON()
    guard let parsed = try? JSONSerialization.jsonObject(with: Data(catalog.utf8)) as? [String: Any],
          let models = parsed["models"] as? [[String: Any]]
    else {
        t.expect(false, "catalog: parses as valid JSON")
        return
    }
    t.expectEqual(models.count, TapgoModel.allCases.count,
                  "catalog: lists every switchable model")
    for model in TapgoModel.allCases {
        let slugs = models.compactMap { $0["slug"] as? String }
        t.expect(slugs.contains(model.rawValue),
                 "catalog: contains slug \(model.rawValue)")
    }
    t.expect(catalog.contains("powered by MiniMax-M3"),
             "catalog: MiniMax base_instructions self-describes MiniMax-M3")
    t.expect(catalog.contains("powered by GLM-5.3-Flash"),
             "catalog: GLM base_instructions self-describes GLM-5.3-Flash")
    t.expect(catalog.contains("input_modalities"),
             "catalog: entries declare input modalities")
}
