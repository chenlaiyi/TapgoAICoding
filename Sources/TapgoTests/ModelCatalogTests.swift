// TapgoTests/ModelCatalogTests.swift
import Foundation
import TapgoCore

@MainActor
func runModelCatalog(_ t: TestRunner) {
    // 模型 → provider 映射: thread/start 的 modelProvider 参数必须与
    // config.toml 模板里 [model_providers.<id>] 的段名一致, 否则 harness
    // 找不到 provider 直接报错。
    t.expectEqual(TapgoModel.deepSeekV4Flash.providerId, "deepseek",
                  "model: deepseek-v4-flash maps to provider deepseek")
    t.expectEqual(TapgoModel.deepSeekV4Pro.providerId, "deepseek",
                  "model: deepseek-v4-pro maps to provider deepseek")
    // UI 展示名: 品牌 + 模型名, 不暴露技术 slug。
    t.expectEqual(TapgoModel.deepSeekV4Flash.displayName, "DeepSeek V4 Flash",
                  "model: DeepSeek flash display name is brand + model")
    t.expectEqual(TapgoModel.deepSeekV4Pro.displayName, "DeepSeek V4 Pro",
                  "model: DeepSeek pro display name is brand + model")
    // slug 保持官方 API 名不变（displayName 只是展示层）。
    t.expectEqual(TapgoModel.deepSeekV4Flash.rawValue, "deepseek-v4-flash",
                  "model: raw slug stays the official API id")

    // 端点: DeepSeek 保持官方 v1。
    t.expectEqual(TapgoModel.deepSeekV4Flash.defaultBaseURL, "https://api.deepseek.com",
                  "model: DeepSeek pins the official responses-capable endpoint")

    // 上下文窗口: DeepSeek 官方标称 1,048,576。
    let expectedWindows: [TapgoModel: Int] = [
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
    t.expect(catalog.contains("powered by deepseek-v4-flash"),
             "catalog: DeepSeek base_instructions self-describes deepseek-v4-flash")
    t.expect(catalog.contains("input_modalities"),
             "catalog: entries declare input modalities")
    t.expect(catalog.contains("list_apps") && catalog.contains("disableDiffing=true"),
             "catalog: injects Codex-compatible computer-use workflow")

    // 自定义字段来自用户输入：引号、反斜杠和换行必须安全编码，且 Key 绝不
    // 进入公开模型目录。
    let custom = CustomModel(
        id: "custom-JSON", displayName: "My \"Model\"\\Beta",
        apiModel: "vendor/model\npreview", brand: "Acme \"AI\"",
        baseURL: "https://example.com/v1", apiKey: "sk-never-in-catalog",
        contextWindow: 128_000)
    let customCatalog = TapgoModel.catalogJSON(customs: [custom])
    guard let customParsed = try? JSONSerialization.jsonObject(
        with: Data(customCatalog.utf8)) as? [String: Any],
          let customModels = customParsed["models"] as? [[String: Any]],
          let customEntry = customModels.last
    else {
        t.expect(false, "catalog: custom fields remain valid JSON")
        return
    }
    t.expectEqual(customModels.count, TapgoModel.allCases.count + 1,
                  "catalog: appends one custom model")
    t.expectEqual(customEntry["display_name"] as? String, custom.displayName,
                  "catalog: custom display name round-trips escaped characters")
    t.expectEqual(customEntry["slug"] as? String, custom.apiModel,
                  "catalog: custom API slug round-trips escaped characters")
    t.expect(!customCatalog.contains(custom.apiKey),
             "catalog: never includes custom API key")
}
