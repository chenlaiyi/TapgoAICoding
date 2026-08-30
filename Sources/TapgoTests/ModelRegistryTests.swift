// TapgoTests/ModelRegistryTests.swift
import Foundation
@testable import TapgoCore

/// Exercises `ModelRegistry`: custom model CRUD + persistence + ID 规范化。
@MainActor
func runModelRegistry(_ t: TestRunner) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-registry-\(UUID().uuidString)", isDirectory: true)
    let file = dir.appendingPathComponent("model-registry.json")
    defer { try? FileManager.default.removeItem(at: dir) }

    let registry = ModelRegistry(fileURL: file)
    t.expectEqual(registry.customModels.count, 0, "registry: starts empty")

    // MARK: add + persist across instances
    let model = CustomModel(
        displayName: "DeepSeek V4 Pro", apiModel: "deepseek-v4-pro",
        brand: "DeepSeek", baseURL: "https://api.deepseek.com",
        apiKey: "sk-test", contextWindow: 1_048_576)
    registry.add(model)
    t.expectEqual(registry.customModels.count, 1, "registry: add persists in memory")
    t.expect(registry.customModels[0].id.hasPrefix("custom-"), "registry: custom id prefix")
    t.expectEqual(registry.customModels[0].providerId, "custom-" + registry.customModels[0].id.dropFirst("custom-".count),
                  "registry: providerId derived from id")
    let reloaded = ModelRegistry(fileURL: file)
    t.expectEqual(reloaded.customModels.count, 1, "registry: survives reload")
    t.expectEqual(reloaded.customModels[0].apiModel, "deepseek-v4-pro", "registry: apiModel round-trips")
    t.expectEqual(reloaded.customModels[0].apiKey, "sk-test", "registry: apiKey round-trips")

    // MARK: update
    var edited = reloaded.customModels[0]
    edited.displayName = "My DeepSeek"
    reloaded.update(edited)
    t.expectEqual(ModelRegistry(fileURL: file).customModels[0].displayName, "My DeepSeek",
                  "registry: update round-trips")

    // MARK: normalize + validate + duplicate ID
    let padded = CustomModel(
        id: "custom-TRIM",
        displayName: "  My Model  ", apiModel: "  model-v1  ",
        brand: "  Brand  ", baseURL: "  https://example.com/v1  ",
        apiKey: "  sk-trim  ", contextWindow: 128_000)
    t.expectNil(padded.validationError, "registry: padded valid model passes validation")
    reloaded.add(padded)
    let trimmed = reloaded.customModel(id: "custom-TRIM")
    t.expectEqual(trimmed?.displayName, "My Model", "registry: display name trimmed")
    t.expectEqual(trimmed?.baseURL, "https://example.com/v1", "registry: base URL trimmed")
    t.expectEqual(trimmed?.apiKey, "sk-trim", "registry: API key trimmed")
    let countBeforeDuplicate = reloaded.customModels.count
    reloaded.add(CustomModel(
        id: "custom-TRIM", displayName: "Replacement", apiModel: "model-v2",
        brand: "Brand", baseURL: "https://example.com/v2", apiKey: "sk-x"))
    t.expectEqual(reloaded.customModels.count, countBeforeDuplicate,
                  "registry: duplicate id replaces instead of appending")
    t.expectEqual(reloaded.customModel(id: "custom-TRIM")?.displayName, "Replacement",
                  "registry: duplicate id keeps latest value")

    let invalidURL = CustomModel(
        id: "custom-BAD", displayName: "Bad", apiModel: "bad",
        brand: "", baseURL: "javascript:alert(1)")
    t.expectNotNil(invalidURL.validationError, "registry: rejects non-http endpoint")
    let countBeforeInvalid = reloaded.customModels.count
    reloaded.add(invalidURL)
    t.expectEqual(reloaded.customModels.count, countBeforeInvalid,
                  "registry: invalid model is not persisted")
    reloaded.remove(id: "custom-TRIM")

    // MARK: selectedID 规范化
    registry.setSelected("GLM-5.3-Flash")
    t.expectEqual(registry.state.selectedID, "builtin:GLM-5.3-Flash", "registry: bare slug → builtin: prefix")
    registry.setSelected("custom-XYZ")
    t.expectEqual(registry.state.selectedID, "custom-XYZ", "registry: custom id passthrough")
    t.expectEqual(ModelRegistry.normalizedID(""), "", "registry: empty stays empty")
    t.expectEqual(ModelRegistry.normalizedID("  GLM-5.3-Flash  "),
                  "builtin:GLM-5.3-Flash", "registry: selected id trims pasted whitespace")

    // MARK: remove 清除选中（用真实存在的自定义模型 id）
    let realID = reloaded.customModels[0].id
    reloaded.setSelected(realID)
    t.expectEqual(reloaded.state.selectedID, realID, "selected set to custom id")
    reloaded.remove(id: realID)
    t.expectEqual(reloaded.state.selectedID, "", "remove: clears selection when deleting selected model")

    // MARK: file permissions 0600
    let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
    t.expectEqual((attrs?[.posixPermissions] as? NSNumber)?.int16Value, Int16(0o600),
                  "registry: file written 0600")

    // MARK: v0.5.52 校验：URL 仅 https（除本地）、apiKey 必填、多错误一次性列出
    let publicHTTP = CustomModel(
        id: "custom-HTTP", displayName: "Public HTTP", apiModel: "any",
        brand: "Brand", baseURL: "http://example.com/v1",
        apiKey: "sk-x", contextWindow: 128_000)
    t.expect(publicHTTP.validationErrors.contains(where: { $0.contains("明文 HTTP") }),
             "registry: rejects public http with 明文 HTTP hint")
    let localHTTP = CustomModel(
        id: "custom-LH", displayName: "Local HTTP", apiModel: "any",
        brand: "Brand", baseURL: "http://127.0.0.1:8080/v1",
        apiKey: "sk-x", contextWindow: 128_000)
    t.expectNil(localHTTP.validationError, "registry: accepts http to 127.0.0.1")
    let localhostHTTP = CustomModel(
        id: "custom-LO", displayName: "Localhost", apiModel: "any",
        brand: "Brand", baseURL: "http://localhost:9999",
        apiKey: "sk-x", contextWindow: 128_000)
    t.expectNil(localhostHTTP.validationError, "registry: accepts http to localhost")
    let noKey = CustomModel(
        id: "custom-NK", displayName: "No Key", apiModel: "any",
        brand: "Brand", baseURL: "https://example.com/v1",
        apiKey: "", contextWindow: 128_000)
    t.expect(noKey.validationErrors.contains(where: { $0.contains("API Key") }),
             "registry: empty apiKey flagged when required")
    let noKeyButExisting = noKey.validationErrors(requireAPIKey: false)
    t.expect(!noKeyButExisting.contains(where: { $0.contains("API Key") }),
             "registry: editing existing custom skips apiKey check")
    let multiError = CustomModel(
        id: "custom-ME", displayName: "", apiModel: "",
        brand: "", baseURL: "not-a-url",
        apiKey: "", contextWindow: 0)
    t.expect(multiError.validationErrors.count >= 4,
             "registry: validationErrors lists all missing fields at once")
    let supportedSizes = Set(CustomModel.contextWindowOptions)
    t.expect(supportedSizes.contains(8_192) && supportedSizes.contains(1_000_000),
             "registry: contextWindowOptions spans 8K to 1M")
    t.expectEqual(CustomModel.normalizedContextWindow(8_192), 8_192,
                  "registry: normalizedContextWindow keeps known size")
    t.expectEqual(CustomModel.normalizedContextWindow(123_456), 1_000_000,
                  "registry: normalizedContextWindow falls back to 1M for unknown")
}
