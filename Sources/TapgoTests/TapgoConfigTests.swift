// TapgoTests/TapgoConfigTests.swift
// v0.5.52 起新增的探测与删除逻辑搬到 TapgoCore/ModelSettingsProbe。
// 本文件覆盖：
//   * readAPIKey：JSON 凭据文件解析、缺失/空 key 回落
//   * deleteCustomModel：选中态改写 + remove 路径
//   * testConnection：URLProtocol stub 验证 Authorization 注入与延迟返回
import Foundation
@testable import TapgoCore

// MARK: - readAPIKey

@MainActor
func runTapgoConfigReadAPIKey(_ t: TestRunner) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-cfg-readkey-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("auth-test.json")

    let key = "sk-tapgo-cfg-test"
    let payload = "{\"OPENAI_API_KEY\":\"" + key + "\"}"
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: file.path, contents: payload.data(using: .utf8))
    t.expectEqual(ModelSettingsProbe.readAPIKey(at: file), key,
                  "config: readAPIKey returns stored key")

    try? Data().write(to: file)
    t.expectEqual(ModelSettingsProbe.readAPIKey(at: file), "",
                  "config: readAPIKey returns empty for non-JSON file")
    try? FileManager.default.removeItem(at: file)
    t.expectEqual(ModelSettingsProbe.readAPIKey(at: file), "",
                  "config: readAPIKey returns empty for missing file")
}

// MARK: - deleteCustomModel

@MainActor
func runTapgoConfigDeleteCustomModel(_ t: TestRunner) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-cfg-delete-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let registryFile = dir.appendingPathComponent("model-registry.json")
    let registry = ModelRegistry(fileURL: registryFile)
    let model = CustomModel(
        displayName: "Probe", apiModel: "probe",
        brand: "Probe", baseURL: "https://example.com/v1",
        apiKey: "sk-probe", contextWindow: 128_000)
    registry.add(model)
    let customID = registry.customModels[0].id

    let defaults = UserDefaults(suiteName: "tapgo-cfg-delete-\(UUID().uuidString)")!
    defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }
    let selectedKey = "tapgo.model"
    defaults.set(customID, forKey: selectedKey)

    let fallback = "builtin:\(TapgoModel.minimaxM3.rawValue)"
    let removed = ModelSettingsProbe.deleteCustomModel(
        id: customID,
        registry: registry,
        defaults: defaults,
        selectedModelKey: selectedKey,
        fallbackSelectedID: fallback
    )
    t.expect(removed, "config: deleteCustomModel returns true for existing id")
    t.expectEqual(defaults.string(forKey: selectedKey), fallback,
                  "config: deleteCustomModel rewrites selection to fallback")
    t.expectEqual(registry.state.selectedID, fallback,
                  "config: registry.selectedID mirrors UserDefaults")
    t.expectEqual(registry.customModel(id: customID), nil,
                  "config: deleted model is gone")

    // 删除不存在的 id
    let removedAgain = ModelSettingsProbe.deleteCustomModel(
        id: customID, registry: registry,
        defaults: defaults,
        selectedModelKey: selectedKey,
        fallbackSelectedID: fallback
    )
    t.expect(!removedAgain, "config: deleteCustomModel returns false for missing id")
}

// MARK: - testConnection（URLProtocol stub）

final class ProbeURLProtocol: URLProtocol {
    static var lastAuthorization: String?
    static var requestCount = 0
    static var responseStatus = 200
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "probe.local"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.responseStatus, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"object":"list"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
func runTapgoConfigTestConnection(_ t: TestRunner) async {
    URLProtocol.registerClass(ProbeURLProtocol.self)
    defer { URLProtocol.unregisterClass(ProbeURLProtocol.self) }
    ProbeURLProtocol.lastAuthorization = nil
    ProbeURLProtocol.requestCount = 0
    ProbeURLProtocol.responseStatus = 200

    @MainActor
    func awaitResult(apiKey: String?) async -> Result<UInt, Error>? {
        await withCheckedContinuation { (cont: CheckedContinuation<Result<UInt, Error>?, Never>) in
            ModelSettingsProbe.testConnection(
                baseURL: "https://probe.local/v1", apiKey: apiKey
            ) { result in
                cont.resume(returning: result)
            }
        }
    }

    if let result = await awaitResult(apiKey: nil) {
        switch result {
        case .success(let ms):
            t.expect(ms < 4_000, "config: testConnection success latency < 4s")
            t.expect(ProbeURLProtocol.lastAuthorization == nil,
                     "config: no key ⇒ no Authorization header")
        case .failure(let err):
            t.expect(false, "config: testConnection unexpected failure \(err.localizedDescription)")
        }
    } else {
        t.expect(false, "config: testConnection did not call completion (nil)")
    }

    if let result = await awaitResult(apiKey: "sk-test") {
        switch result {
        case .success:
            t.expect(ProbeURLProtocol.lastAuthorization == "Bearer sk-test",
                     "config: apiKey ⇒ Bearer Authorization header")
        case .failure(let err):
            t.expect(false, "config: testConnection unexpected failure \(err.localizedDescription)")
        }
    } else {
        t.expect(false, "config: testConnection did not call completion (nil)")
    }

    ProbeURLProtocol.responseStatus = 401
    if let result = await awaitResult(apiKey: nil) {
        if case .failure(let err) = result,
           let testErr = err as? ModelSettingsProbe.TestError,
           testErr == .unauthorized {
            t.expect(true, "config: HTTP 401 surfaces as TestError.unauthorized")
        } else {
            t.expect(false, "config: HTTP 401 expected unauthorized, got \(String(describing: result))")
        }
    }
    ProbeURLProtocol.responseStatus = 200
}
