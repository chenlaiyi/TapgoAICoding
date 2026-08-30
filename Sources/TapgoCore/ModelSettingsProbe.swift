// TapgoCore/ModelSettingsProbe.swift
// v0.5.52 起：模型设置的探测与删除逻辑搬到 TapgoCore，让 TapgoTests
// 不依赖 TapgoAICoding 即可单测。所有 IO 都通过参数注入（selectedModelKey、
// authFiles 字典、UserDefaults），不直接触碰真实 ~/Library。

import Foundation

public enum ModelSettingsProbe {

    public enum TestError: LocalizedError, Equatable {
        case invalidURL
        case http(Int)
        case unauthorized
        case emptyModels
        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "端点 URL 无法解析"
            case .http(let code): return "HTTP \(code)"
            case .unauthorized: return "鉴权失败（401 / 403）"
            case .emptyModels: return "端点返回空模型列表"
            }
        }
    }

    /// 探测内置或自定义模型的连通性。`baseURL` / `apiKey` 由调用方注入；
    /// 成功时 completion(.success(延迟毫秒))，失败时回 `TestError` 或
    /// 上游 `URLError`。始终在主线程回调。
    public static func testConnection(
        baseURL: String,
        apiKey: String?,
        completion: @escaping (Result<UInt, Error>) -> Void
    ) {
        guard let endpoint = URL(string: baseURL) else {
            DispatchQueue.main.async { completion(.failure(TestError.invalidURL)) }
            return
        }
        let url = endpoint.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let started = Date()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let latency = UInt(Date().timeIntervalSince(started) * 1000)
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(TestError.invalidURL))
                    return
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    completion(.failure(TestError.unauthorized))
                    return
                }
                if !(200..<300).contains(http.statusCode) {
                    completion(.failure(TestError.http(http.statusCode)))
                    return
                }
                if let data, !data.isEmpty {
                    completion(.success(latency))
                } else {
                    completion(.failure(TestError.emptyModels))
                }
            }
        }
        task.resume()
    }

    /// 删除自定义模型并按需回写 UserDefaults 选中态。`registry` / `defaults` /
    /// `selectedModelKey` / `fallbackSelectedID` 全部由调用方注入，函数本身
    /// 不接触全局状态或真实文件系统，便于单测。
    /// 返回「是否真的删除了该自定义模型」。
    @discardableResult
    public static func deleteCustomModel(
        id: String,
        registry: ModelRegistry,
        defaults: UserDefaults = .standard,
        selectedModelKey: String,
        fallbackSelectedID: String
    ) -> Bool {
        let raw = defaults.string(forKey: selectedModelKey) ?? ""
        let wasSelected = ModelRegistry.normalizedID(raw) == id
        let removed = registry.remove(id: id)
        if wasSelected {
            defaults.set(fallbackSelectedID, forKey: selectedModelKey)
            registry.setSelected(fallbackSelectedID)
        }
        return removed
    }

    /// 读取 JSON 凭据文件中的 `OPENAI_API_KEY`。返回空串 = 未配置。
    public static func readAPIKey(at path: URL) -> String {
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["OPENAI_API_KEY"] as? String,
              !key.isEmpty
        else { return "" }
        return key
    }
}
