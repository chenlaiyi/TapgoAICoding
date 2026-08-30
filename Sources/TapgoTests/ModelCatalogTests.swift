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
    t.expectEqual(TapgoModel.deepSeekV4Flash.providerId, "deepseek",
                  "model: deepseek-v4-flash maps to provider deepseek")
    t.expectEqual(TapgoModel.deepSeekV4Pro.providerId, "deepseek",
                  "model: deepseek-v4-pro maps to provider deepseek")
    // UI 展示名: 品牌 + 模型名, 不暴露技术 slug。
    t.expectEqual(TapgoModel.minimaxM3.displayName, "MiniMax M3",
                  "model: MiniMax display name is brand + model")
    t.expectEqual(TapgoModel.glm53Flash.displayName, "GLM 5.3 Flash",
                  "model: GLM display name is brand + model")
    t.expectEqual(TapgoModel.deepSeekV4Flash.displayName, "DeepSeek V4 Flash",
                  "model: DeepSeek flash display name is brand + model")
    t.expectEqual(TapgoModel.deepSeekV4Pro.displayName, "DeepSeek V4 Pro",
                  "model: DeepSeek pro display name is brand + model")
    // slug 保持官方 API 名不变（displayName 只是展示层）。
    t.expectEqual(TapgoModel.deepSeekV4Flash.rawValue, "deepseek-v4-flash",
                  "model: raw slug stays the official API id")

    // 端点: GLM 必须指向智谱给 Codex 的 OpenAI Responses 协议专属端点
    // (docs.bigmodel.cn/cn/coding-plan/tool/codex); MiniMax 保持官方 v1。
    t.expectEqual(TapgoModel.glm53Flash.defaultBaseURL, "https://open.bigmodel.cn/api/v1",
                  "model: GLM-5.3-Flash pins the official Responses endpoint")
    t.expectEqual(TapgoModel.minimaxM3.defaultBaseURL, "https://api.minimaxi.com/v1",
                  "model: MiniMax-M3 pins the official china endpoint")
    t.expectEqual(TapgoModel.deepSeekV4Flash.defaultBaseURL, "https://api.deepseek.com",
                  "model: DeepSeek pins the official responses-capable endpoint")

    // 上下文窗口: MiniMax/GLM 1M, DeepSeek 官方标称 1,048,576。
    let expectedWindows: [TapgoModel: Int] = [
        .minimaxM3: 1_000_000, .glm53Flash: 1_000_000,
        .deepSeekV4Flash: 1_048_576, .deepSeekV4Pro: 1_048_576,
    ]
    for (model, expected) in expectedWindows {
        t.expectEqual(model.contextWindow, expected,
                      "model: \(model.rawValue) context window")
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
