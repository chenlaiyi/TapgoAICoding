import Foundation

/// Lives in the stdio bridge, across Launch Services one-shot workers.
/// Only opaque hashes are sent back to workers; AX text stays out of requests.
public final class ComputerUseObservationSession {
    public static let stateTools: Set<String> = ["get_app_state", "get_ax_state", "get_ax_state_and_screenshot"]
    public static let screenshotTools: Set<String> = ["screenshot", "get_screenshot"]
    private static let readTools = stateTools.union(screenshotTools).union(["list_apps", "list_applications", "get_screen_size"])
    private var observations: [String: (token: String, date: Date)] = [:]

    public init() {}

    public func respond(to data: Data, now: Date = Date(), execute: (Data) -> Data?) -> Data? {
        guard var request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              request["method"] as? String == "tools/call",
              var params = request["params"] as? [String: Any],
              let tool = params["name"] as? String else { return execute(data) }
        var args = params["arguments"] as? [String: Any] ?? [:]
        // Never accept a model-supplied internal token.
        args.removeValue(forKey: "_observation_token")
        let key = ComputerUseMCP.appNameArg(args)?.lowercased()
        if args["element_index"] != nil {
            guard let key, let observation = observations[key],
                  now.timeIntervalSince(observation.date) >= 0,
                  now.timeIntervalSince(observation.date) <= 120 else {
                return ComputerUseMCP.handle(requestData: data) { _, _ in
                    .init(isError: true, text: "元素编号没有有效的最近观察；请先对同一个 app 调用 get_ax_state（disableDiffing=true）。")
                }
            }
            args["_observation_token"] = observation.token
        }
        if !Self.readTools.contains(tool) || Self.screenshotTools.contains(tool) {
            // Focus, navigation and screenshots can change other app contexts.
            observations.removeAll()
        } else if Self.stateTools.contains(tool), let key {
            observations.removeValue(forKey: key)
        }
        params["arguments"] = args
        request["params"] = params
        guard let forwarded = try? JSONSerialization.data(withJSONObject: request),
              let response = execute(forwarded) else { return nil }
        if Self.stateTools.contains(tool), let key,
           let object = (try? JSONSerialization.jsonObject(with: response)) as? [String: Any],
           let result = object["result"] as? [String: Any], result["isError"] as? Bool != true,
           let structured = result["structuredContent"] as? [String: Any],
           let token = structured["observation_token"] as? String, !token.isEmpty {
            observations[key] = (token, now)
        }
        return response
    }
}
