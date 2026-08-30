import Foundation

/// 电脑控制 MCP server 的协议层 (v0.5.20) — 纯 Foundation, 不依赖
/// AppKit/CoreGraphics, 方便单测覆盖。
///
/// 让 App 里的模型 (经 Codex harness) 能调用电脑操作工具, 完成
/// Computer Use 风格的桌面自动化工作流。二进制 `TapgoComputerUseMCP`
/// 以 stdio MCP server 形态被 codex 拉起 (注册在隔离 Codex home 的
/// `config.toml` `[mcp_servers.tapgo_computer_use]`), 真实的截屏 /
/// CGEvent 注入实现放在 `TapgoComputerUse` 库, 本文件只负责:
///
/// * 工具注册表 (名称 / 描述 / inputSchema)
/// * JSON-RPC 2.0 分发 (initialize / tools/list / tools/call / ping)
/// * 工具调用结果的 MCP content 封装
/// * config.toml 里 `[mcp_servers.tapgo_computer_use]` 段的幂等写入/移除
public enum ComputerUseMCP {

    /// MCP 服务器握手时声明的协议版本 (codex 兼容 2025-06-18)。
    public static let protocolVersion = "2025-06-18"
    public static let serverName = "tapgo-computer-use"
    public static let serverVersion = "1.0.0"

    /// config.toml 里的 server 键名 (`[mcp_servers.<key>]`)。
    public static let configServerKey = "tapgo_computer_use"

    /// The actual TCC identity used for Accessibility and Screen Recording.
    /// Keep the MCP executable inside a real helper `.app`, because macOS
    /// privacy settings authorize application bundles rather than an
    /// unrelated host UI process.
    public static let helperDirectoryName = "computer-use-helper"
    public static let helperInstallDirectoryName = "computer-use"
    public static let helperAppName = "Tapgo Computer Use.app"
    public static let helperExecutableName = "TapgoComputerUseMCP"

    /// Injected into every new model session so desktop control follows a
    /// verified observe-act-observe loop instead of guessing global positions.
    public static let agentInstructions = """
    【电脑控制工作流·使用电脑控制工具时强制执行】
    - 先用 list_applications 确认目标应用，再调用 get_app_state(app, include_screenshot=true) 同时读取深层元素树与目标应用窗口。
    - 始终把操作绑定到目标 app；优先用 click_element 和 set_element_value。只有元素树中确实没有可操作元素时，才使用同一张应用窗口截图里的 app 相对坐标。
    - 每次导航、点击、输入或滚动后重新调用 get_app_state 核对结果；元素编号在界面变化后立即失效，不得复用。
    - 不得根据旧截图或全屏位置反复盲点。连续两次未达到预期时，停止坐标猜测，重新读取当前应用与窗口状态后再决定。
    """

    public static func helperExecutablePath(helperAppPath: String) -> String {
        URL(fileURLWithPath: helperAppPath, isDirectory: true)
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(helperExecutableName, isDirectory: false)
            .path
    }

    public static func installedHelperAppPath(applicationSupportPath: String) -> String {
        URL(fileURLWithPath: applicationSupportPath, isDirectory: true)
            .appendingPathComponent(helperInstallDirectoryName, isDirectory: true)
            .appendingPathComponent(helperAppName, isDirectory: true)
            .path
    }

    /// Build the stable executable path inside the packaged helper app.
    /// `resourcesPath` is the parent app's `Contents/Resources` directory.
    public static func bundledHelperExecutablePath(resourcesPath: String) -> String {
        let helperAppPath = URL(fileURLWithPath: resourcesPath, isDirectory: true)
            .appendingPathComponent(helperDirectoryName, isDirectory: true)
            .appendingPathComponent(helperAppName, isDirectory: true)
            .path
        return helperExecutablePath(helperAppPath: helperAppPath)
    }

    // MARK: - Tool outcome

    /// 一次工具执行的结果; 由 MCP 层封装成 `content` 数组。
    public struct ToolOutcome: Equatable {
        /// true 时 codex 把结果作为工具错误呈现给模型 (模型可自行重试/汇报)。
        public var isError: Bool
        /// 文本内容 (说明/错误/屏幕尺寸等元数据)。
        public var text: String?
        /// 截屏的 JPEG base64, nil 表示无图像。
        public var imageJPEGBase64: String?

        public init(isError: Bool = false, text: String? = nil, imageJPEGBase64: String? = nil) {
            self.isError = isError
            self.text = text
            self.imageJPEGBase64 = imageJPEGBase64
        }
    }

    /// 真实执行器: 工具名 + 已解析参数 → 结果。协议层不关心实现。
    public typealias Executor = (_ tool: String, _ arguments: [String: Any]) -> ToolOutcome

    // MARK: - Tool registry

    /// 工具全集。press_key 的 key 参数枚举复用 PhoneRemote.ControlKey
    /// (H5 电脑控制与 MCP 共用同一套键名)。
    public static let toolNames: [String] = [
        "list_applications", "get_app_state", "click_element", "set_element_value",
        "screenshot", "get_screen_size", "left_click", "double_click",
        "type_text", "press_key", "scroll", "open_application",
    ]

    /// 工具 JSON Schema 声明。坐标一律归一化 0...1 (主屏, 左上原点),
    /// 与分辨率/多屏缩放无关。
    public static func toolsListResult() -> [String: Any] {
        let keyEnum = PhoneRemote.ControlKey.allCases.map(\.rawValue).sorted()
        let tools: [[String: Any]] = [
            tool("list_applications",
                 "列出当前运行的用户应用、bundle id 与前台状态。需要语义读取/按元素操作时先用它确认 app 参数。",
                 ["type": "object", "properties": [:], "additionalProperties": false]),
            tool("get_app_state",
                 "把目标应用切到前台，读取深层 macOS Accessibility 元素树并给元素临时编号；支持 Electron/WebArea。include_screenshot=true 时同时返回该应用主窗口截图。导航或界面变化后编号会失效，操作前必须重新读取。",
                 object(["app": str(), "include_screenshot": bool()], required: ["app"])),
            tool("click_element",
                 "按下 get_app_state 最近一次状态中的元素编号。适合按钮、菜单项、复选框等语义控件；操作后重新读取状态核对。",
                 object(["app": str(), "element_index": integer(minimum: 0, maximum: 999)],
                        required: ["app", "element_index"])),
            tool("set_element_value",
                 "直接给 get_app_state 返回的可编辑文本框设置值，比坐标点击后盲打可靠；不会在结果中回显内容。设置后必须重新读取状态核对。",
                 object(["app": str(),
                         "element_index": integer(minimum: 0, maximum: 999),
                         "text": str()],
                        required: ["app", "element_index", "text"])),
            tool("screenshot",
                 "返回 JPEG。处理某个应用时必须传 app，只截取并聚焦该应用主窗口；省略 app 才截整个主屏。点击后再次截图核对。",
                 object(["app": str()], required: [])),
            tool("get_screen_size",
                 "获取 Mac 主屏尺寸 (逻辑点数与像素)。只想知道屏幕大小/比例时用这个, 不需要图像。",
                 ["type": "object", "properties": [:], "additionalProperties": false]),
            tool("left_click",
                 "优先使用 click_element。仅在无语义元素时，按最近 screenshot 的左上原点归一化坐标单击；传 app 时坐标相对该应用窗口并先聚焦，省略 app 才相对主屏。",
                 object(["app": str(), "x": num(), "y": num()], required: ["x", "y"])),
            tool("double_click",
                 "按归一化坐标双击；传 app 时相对该应用窗口并先聚焦，省略 app 才相对主屏。",
                 object(["app": str(), "x": num(), "y": num()], required: ["x", "y"])),
            tool("type_text",
                 "向当前焦点控件逐字符输入文本；建议传 app 以先聚焦目标应用。表单输入优先使用 set_element_value；\\n 会转成回车。",
                 object(["app": str(), "text": str()], required: ["text"])),
            tool("press_key",
                 "在指定 app 中按一个命名按键，可选组合修饰键；建议始终传 app，避免按键落到其他应用。key 枚举: \(keyEnum.joined(separator: ", "))。",
                 object(["app": str(),
                         "key": ["type": "string", "enum": keyEnum],
                         "modifiers": ["type": "array",
                                       "items": ["type": "string",
                                                 "enum": ["command", "control", "option", "shift"]]],
                         "example": ["key": "return", "modifiers": ["command"]]],
                        required: ["key"])),
            tool("scroll",
                 "在指定 app 中滚轮滚动；建议始终传 app。dy 为行数，正数向下、负数向上，限幅 ±20。",
                 object(["app": str(), "dy": num()], required: ["dy"])),
            tool("open_application",
                 "按应用名、中文本地化名或 bundle id 启动并切到前台；会检查真实退出状态。启动后用 get_app_state(app, include_screenshot=true) 确认。",
                 object(["name": str()], required: ["name"])),
        ]
        return ["tools": tools]
    }

    private static func tool(_ name: String, _ description: String, _ schema: [String: Any]) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": schema]
    }

    private static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        schema["additionalProperties"] = false
        return schema
    }
    private static func num() -> [String: Any] { ["type": "number", "minimum": 0, "maximum": 1] }
    private static func integer(minimum: Int, maximum: Int) -> [String: Any] {
        ["type": "integer", "minimum": minimum, "maximum": maximum]
    }
    private static func str() -> [String: Any] { ["type": "string"] }
    private static func bool() -> [String: Any] { ["type": "boolean"] }

    // MARK: - Typed argument accessors (执行器与单测共用)

    /// 归一化坐标 (0...1); 缺失/越界/类型不对返回 nil。
    public static func normalizedCoord(_ args: [String: Any]) -> (x: Double, y: Double)? {
        guard let x = doubleArg(args, "x"), let y = doubleArg(args, "y"),
              x >= 0, x <= 1, y >= 0, y <= 1
        else { return nil }
        return (x, y)
    }

    /// 滚动行数; 0 或缺失返回 nil。
    public static func lineDelta(_ args: [String: Any]) -> Double? {
        guard let dy = doubleArg(args, "dy"), dy != 0 else { return nil }
        return dy
    }

    public static func textArg(_ args: [String: Any]) -> String? {
        (args["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Form values may legitimately be empty when clearing an editable field.
    public static func elementValueArg(_ args: [String: Any]) -> String? {
        args["text"] as? String
    }

    public static func appNameArg(_ args: [String: Any]) -> String? {
        guard let raw = args["app"] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func boolArg(_ args: [String: Any], _ key: String) -> Bool {
        args[key] as? Bool ?? false
    }

    public static func elementIndex(_ args: [String: Any]) -> Int? {
        guard let number = args["element_index"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value >= 0, value <= 999, value.rounded(.towardZero) == value else { return nil }
        return Int(exactly: value)
    }

    public static func keyArg(_ args: [String: Any]) -> PhoneRemote.ControlKey? {
        guard let raw = args["key"] as? String else { return nil }
        return PhoneRemote.ControlKey(rawValue: raw)
    }

    /// 修饰键白名单过滤; 非法项直接丢弃。
    public static func modifierFlags(_ args: [String: Any]) -> [String] {
        let allowed: Set<String> = ["command", "control", "option", "shift"]
        return ((args["modifiers"] as? [Any])?.compactMap { $0 as? String } ?? [])
            .filter { allowed.contains($0) }
    }

    /// Darwin 上 JSONSerialization 把数值和 Bool 都解析成 NSNumber,
    /// 用 CFBooleanGetTypeID 严格区分 (Bool 不是合法的数值坐标)。
    private static func doubleArg(_ args: [String: Any], _ key: String) -> Double? {
        guard let number = args[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number.doubleValue
    }

    // MARK: - JSON-RPC dispatch

    /// 处理一条 JSON-RPC 请求; 通知 (无 id) 返回 nil 不回包。
    public static func handle(requestData: Data, executor: Executor) -> Data? {
        guard let obj = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any] else {
            return encode(rpcResult(id: NSNull(), error: ["code": -32700, "message": "Parse error"]))
        }
        let method = obj["method"] as? String
        let isNotification = obj["id"] == nil
        let id = isNotification ? NSNull() : (obj["id"] ?? NSNull())
        switch method {
        case "initialize":
            return encode(rpcResult(id: id, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": serverName, "version": serverVersion],
            ]))
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "tools/list":
            return encode(rpcResult(id: id, result: toolsListResult()))
        case "tools/call":
            guard let params = obj["params"] as? [String: Any],
                  let name = params["name"] as? String
            else {
                return encode(rpcResult(id: id, result: content(ToolOutcome(isError: true, text: "缺少工具名 params.name"))))
            }
            guard toolNames.contains(name) else {
                return encode(rpcResult(id: id, result: content(ToolOutcome(isError: true, text: "未知工具: \(name)"))))
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            return encode(rpcResult(id: id, result: content(executor(name, args))))
        case "ping":
            return encode(rpcResult(id: id, result: [:] as [String: Any]))
        default:
            if isNotification { return nil }
            return encode(rpcResult(id: id,
                                    error: ["code": -32601,
                                            "message": "Method not found: \(method ?? "nil")"]))
        }
    }

    // MARK: - config.toml 幂等写入

    /// 生成要写进 config.toml 的 section 文本 (带前导空行 + 注释)。
    public static func configSection(commandPath: String) -> String {
        """
        
        # 电脑控制 MCP server —— 让模型调用截屏/鼠标/键盘工具 (v0.5.20+)。
        [mcp_servers.\(configServerKey)]
        command = "\(commandPath)"
        """
    }

    /// 把 section 幂等合并进 config 文本: 已有该段则只在 command 路径
    /// 不同时替换那一行; 没有则追加到末尾。纯函数, 方便单测。
    public static func upsertSection(inConfig config: String, commandPath: String) -> String {
        let header = "[mcp_servers.\(configServerKey)]"
        var lines = config.components(separatedBy: "\n")
        if let headerIdx = lines.firstIndex(of: header) {
            // 在该 table 内 (直到下一个 table header) 找 command 行替换。
            var cursor = headerIdx + 1
            while cursor < lines.count, !lines[cursor].hasPrefix("[") {
                if lines[cursor].hasPrefix("command =") {
                    if lines[cursor] == "command = \"\(commandPath)\"" { return config }
                    lines[cursor] = "command = \"\(commandPath)\""
                    return lines.joined(separator: "\n")
                }
                cursor += 1
            }
            // 段内没有 command 行 → 插到 header 后。
            lines.insert("command = \"\(commandPath)\"", at: headerIdx + 1)
            return lines.joined(separator: "\n")
        }
        return config.hasSuffix("\n") || config.isEmpty
            ? config + configSection(commandPath: commandPath) + "\n"
            : config + "\n" + configSection(commandPath: commandPath) + "\n"
    }

    /// 从 config 文本中移除电脑控制 MCP table。只删除本工具自己的
    /// header、字段与紧邻的生成注释，不触碰前后其它 provider/MCP 配置。
    /// section 不存在时原样返回，便于设置开关幂等调用。
    public static func removeSection(fromConfig config: String) -> String {
        let header = "[mcp_servers.\(configServerKey)]"
        var lines = config.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(of: header) else { return config }

        var endIndex = headerIndex + 1
        while endIndex < lines.count {
            let trimmed = lines[endIndex].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            endIndex += 1
        }

        var startIndex = headerIndex
        if startIndex > 0,
           lines[startIndex - 1].trimmingCharacters(in: .whitespaces)
            .hasPrefix("# 电脑控制 MCP server") {
            startIndex -= 1
        }
        if startIndex > 0,
           lines[startIndex - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            startIndex -= 1
        }

        lines.removeSubrange(startIndex..<endIndex)
        var result = lines.joined(separator: "\n")
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result
    }

    // MARK: - Response shaping

    static func content(_ outcome: ToolOutcome) -> [String: Any] {
        var items: [[String: Any]] = []
        if let text = outcome.text {
            items.append(["type": "text", "text": text])
        }
        if let image = outcome.imageJPEGBase64 {
            items.append(["type": "image", "data": image, "mimeType": "image/jpeg"])
        }
        if items.isEmpty {
            items.append(["type": "text", "text": outcome.isError ? "失败" : "完成"])
        }
        return ["content": items, "isError": outcome.isError]
    }

    static func rpcResult(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func rpcResult(id: Any, error: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": error]
    }

    private static func encode(_ obj: [String: Any]) -> Data {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        return data
    }
}
