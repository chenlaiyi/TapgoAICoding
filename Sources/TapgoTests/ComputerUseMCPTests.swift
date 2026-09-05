// TapgoTests/ComputerUseMCPTests.swift
// v0.5.20 电脑控制 MCP server — 协议层回归 (TapgoCore/ComputerUseMCP.swift)。
// 覆盖: JSON-RPC 分发、工具注册表 schema、参数解析助手、config.toml 幂等写入。
import Foundation
@testable import TapgoCore

// MARK: - JSON-RPC 分发 + 工具注册表

func runComputerUseMCPProtocol(_ t: TestRunner) {
    let noop: ComputerUseMCP.Executor = { _, _ in ComputerUseMCP.ToolOutcome(text: "ok") }

    runComputerUseObservationSession(t)

    // initialize 握手
    let initReq = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#
    if let data = ComputerUseMCP.handle(requestData: Data(initReq.utf8), executor: noop),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = obj["result"] as? [String: Any] {
        t.expectEqual(obj["id"] as? Int, 1, "mcp: initialize id 透传")
        t.expectEqual(result["protocolVersion"] as? String, ComputerUseMCP.protocolVersion,
                      "mcp: protocolVersion")
        let serverInfo = result["serverInfo"] as? [String: Any]
        t.expectEqual(serverInfo?["name"] as? String, ComputerUseMCP.serverName, "mcp: serverInfo.name")
        let caps = result["capabilities"] as? [String: Any]
        t.expect((caps?["tools"] as? [String: Any]) != nil, "mcp: capabilities.tools 存在")
    } else {
        t.expect(false, "mcp: initialize 可回包且可解析")
    }

    // 通知不回包
    let note = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
    t.expect(ComputerUseMCP.handle(requestData: Data(note.utf8), executor: noop) == nil,
             "mcp: initialized 通知不回包")

    // tools/list: Codex Computer Use 1:1 主 API + 旧版兼容别名
    let listReq = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
    if let data = ComputerUseMCP.handle(requestData: Data(listReq.utf8), executor: noop),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = obj["result"] as? [String: Any],
       let tools = result["tools"] as? [[String: Any]] {
        t.expectEqual(tools.count, ComputerUseMCP.toolNames.count, "mcp: 工具数与注册表一致")
        t.expectEqual(tools.count, 22, "mcp: 11 个原生动作 + 3 个分离观察工具 + 8 个旧版别名")
        let names = tools.compactMap { $0["name"] as? String }
        for required in ComputerUseMCP.toolNames {
            t.expect(names.contains(required), "mcp: 工具 \(required) 已注册")
        }
        // 每个工具都有 object 形态的 inputSchema 与描述
        for tool in tools {
            let schema = tool["inputSchema"] as? [String: Any]
            t.expectEqual(schema?["type"] as? String, "object",
                          "mcp: \(tool["name"] ?? "?") schema 是 object")
            t.expect((tool["description"] as? String)?.isEmpty == false,
                     "mcp: \(tool["name"] ?? "?") 有描述")
        }
        t.expectEqual(ComputerUseMCP.codexCompatibleToolNames.count, 11,
                      "mcp: Codex Computer Use API 11 个工具")
        for required in ["click", "drag", "get_app_state", "list_apps", "paste",
                         "perform_secondary_action", "press_key", "scroll", "select_text",
                         "set_value", "type_text"] {
            t.expect(ComputerUseMCP.codexCompatibleToolNames.contains(required),
                     "mcp: Codex 主工具 \(required) 已注册")
        }

        // press_key 与 Codex 一样接受 xdotool 风格字符串，不再受旧枚举限制。
        let press = tools.first { ($0["name"] as? String) == "press_key" }
        let props = ((press?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        t.expectEqual((props?["key"] as? [String: Any])?["type"] as? String,
                      "string", "mcp: press_key 接受 xdotool 字符串")
        t.expect((props?["key"] as? [String: Any])?["enum"] == nil,
                 "mcp: press_key 不限制为旧枚举")
        let pressRequired = ((press?["inputSchema"] as? [String: Any])?["required"] as? [String]) ?? []
        t.expect(Set(pressRequired) == Set(["app", "key"]),
                 "mcp: Codex press_key 强制绑定目标 app")

        let typeText = tools.first { ($0["name"] as? String) == "type_text" }
        let typeRequired = ((typeText?["inputSchema"] as? [String: Any])?["required"] as? [String]) ?? []
        t.expect(Set(typeRequired) == Set(["app", "text"]),
                 "mcp: Codex type_text 强制绑定目标 app")

        let state = tools.first { ($0["name"] as? String) == "get_app_state" }
        let stateProps = ((state?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        t.expectEqual((stateProps?["include_screenshot"] as? [String: Any])?["type"] as? String,
                      "boolean", "mcp: get_app_state 可同时请求应用窗口截图")
        t.expectEqual((stateProps?["disableDiff"] as? [String: Any])?["type"] as? String,
                      "boolean", "mcp: get_app_state 支持 Codex disableDiff")

        let screenshot = tools.first { ($0["name"] as? String) == "screenshot" }
        let screenshotProps = ((screenshot?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        t.expectEqual((screenshotProps?["app"] as? [String: Any])?["type"] as? String,
                      "string", "mcp: screenshot 支持指定应用窗口")

        let setValue = tools.first { ($0["name"] as? String) == "set_element_value" }
        let setValueRequired = ((setValue?["inputSchema"] as? [String: Any])?["required"] as? [String]) ?? []
        t.expect(Set(setValueRequired) == Set(["app", "element_index", "text"]),
                 "mcp: 语义赋值要求 app/index/text")

        let codexSetValue = tools.first { ($0["name"] as? String) == "set_value" }
        let codexRequired = ((codexSetValue?["inputSchema"] as? [String: Any])?["required"] as? [String]) ?? []
        t.expect(Set(codexRequired) == Set(["app", "element_index", "value"]),
                 "mcp: Codex set_value 参数完全对齐")

        let click = tools.first { ($0["name"] as? String) == "click" }
        let clickProps = ((click?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
        for key in ["app", "element_index", "x", "y", "mouse_button", "click_count"] {
            t.expect(clickProps[key] != nil, "mcp: click 含参数 \(key)")
        }
    } else {
        t.expect(false, "mcp: tools/list 可回包且可解析")
    }

    // tools/call: 执行器收到的参数 + content 封装 (文本 + 图像)
    let callReq = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"screenshot","arguments":{}}}"#
    var executedTool: String?
    var executedArgs: [String: Any]?
    if let data = ComputerUseMCP.handle(requestData: Data(callReq.utf8), executor: { tool, args in
        executedTool = tool
        executedArgs = args
        return ComputerUseMCP.ToolOutcome(text: "meta", imageJPEGBase64: "QUJD")
    }),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = obj["result"] as? [String: Any] {
        t.expectEqual(executedTool, "screenshot", "mcp: 执行器收到工具名")
        t.expect(executedArgs != nil, "mcp: 执行器收到 arguments (可为空字典)")
        t.expectEqual(result["isError"] as? Bool, false, "mcp: 成功结果 isError=false")
        let content = result["content"] as? [[String: Any]]
        t.expectEqual(content?.count, 2, "mcp: 文本+图像两段 content")
        t.expectEqual(content?.first?["type"] as? String, "text", "mcp: 第一段 text")
        t.expectEqual(content?.last?["type"] as? String, "image", "mcp: 第二段 image")
        t.expectEqual(content?.last?["mimeType"] as? String, "image/jpeg", "mcp: mimeType jpeg")
        t.expectEqual(content?.last?["data"] as? String, "QUJD", "mcp: base64 数据透传")
    } else {
        t.expect(false, "mcp: tools/call 可回包且可解析")
    }

    // 坐标参数透传给执行器
    let clickReq = #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"left_click","arguments":{"x":0.25,"y":0.75}}}"#
    var seenArgs: [String: Any] = [:]
    _ = ComputerUseMCP.handle(requestData: Data(clickReq.utf8), executor: { _, args in
        seenArgs = args
        return ComputerUseMCP.ToolOutcome(text: "ok")
    })
    t.expectEqual(ComputerUseMCP.normalizedCoord(seenArgs)?.x, 0.25, "mcp: click x 到达执行器")
    t.expectEqual(ComputerUseMCP.normalizedCoord(seenArgs)?.y, 0.75, "mcp: click y 到达执行器")

    // 未知工具 → 工具级 isError (不是协议层错误)
    let unknownTool = #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"format_disk","arguments":{}}}"#
    if let data = ComputerUseMCP.handle(requestData: Data(unknownTool.utf8), executor: noop),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = obj["result"] as? [String: Any] {
        t.expectEqual(result["isError"] as? Bool, true, "mcp: 未知工具 isError=true")
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        t.expect(text.contains("format_disk"), "mcp: 未知工具名出现在错误文本里")
    } else {
        t.expect(false, "mcp: 未知工具可回包")
    }

    // 未知 method → -32601; 缺 params.name 的 tools/call → 工具级错误
    let unknownMethod = #"{"jsonrpc":"2.0","id":10,"method":"resources/list"}"#
    if let data = ComputerUseMCP.handle(requestData: Data(unknownMethod.utf8), executor: noop),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let error = obj["error"] as? [String: Any] {
        t.expectEqual(error["code"] as? Int, -32601, "mcp: 未知 method → -32601")
    } else {
        t.expect(false, "mcp: 未知 method 有错误回包")
    }
    let noName = #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{}}"#
    if let data = ComputerUseMCP.handle(requestData: Data(noName.utf8), executor: noop),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = obj["result"] as? [String: Any] {
        t.expectEqual(result["isError"] as? Bool, true, "mcp: 缺 name → isError")
    } else {
        t.expect(false, "mcp: 缺 name 可回包")
    }

    // 坏 JSON → -32700; ping → 空 result
    if let data = ComputerUseMCP.handle(requestData: Data("not json".utf8), executor: noop),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let error = obj["error"] as? [String: Any] {
        t.expectEqual(error["code"] as? Int, -32700, "mcp: 坏 JSON → -32700")
    } else {
        t.expect(false, "mcp: 坏 JSON 有错误回包")
    }
    let pingReq = #"{"jsonrpc":"2.0","id":12,"method":"ping"}"#
    if let data = ComputerUseMCP.handle(requestData: Data(pingReq.utf8), executor: noop),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = obj["result"] as? [String: Any] {
        t.expect(result.isEmpty, "mcp: ping 返回空 result")
    } else {
        t.expect(false, "mcp: ping 可回包")
    }

    // 参数解析助手
    t.expect(ComputerUseMCP.normalizedCoord(["x": 0.0, "y": 1.0]) != nil, "coord: 边界 0/1 合法")
    t.expect(ComputerUseMCP.normalizedCoord(["x": 1.5, "y": 0.5]) == nil, "coord: 越界拒绝")
    t.expect(ComputerUseMCP.normalizedCoord(["x": -0.1, "y": 0.5]) == nil, "coord: 负数拒绝")
    t.expect(ComputerUseMCP.normalizedCoord(["x": true, "y": 0.5]) == nil, "coord: Bool 不算数值")
    t.expect(ComputerUseMCP.normalizedCoord(["y": 0.5]) == nil, "coord: 缺 x 拒绝")
    t.expectEqual(ComputerUseMCP.lineDelta(["dy": -3]), -3, "coord: dy 负数")
    t.expect(ComputerUseMCP.lineDelta(["dy": 0]) == nil, "coord: dy=0 拒绝")
    t.expectEqual(ComputerUseMCP.textArg(["text": "你好 world"]), "你好 world", "text: UTF-8")
    t.expect(ComputerUseMCP.textArg(["text": ""]) == nil, "text: 空串拒绝")
    t.expectEqual(ComputerUseMCP.elementValueArg(["text": ""]), "", "element value: 允许清空字段")
    t.expect(ComputerUseMCP.elementValueArg(["text": 1]) == nil, "element value: 拒绝非字符串")
    t.expectEqual(ComputerUseMCP.appNameArg(["app": " com.apple.Safari "]), "com.apple.Safari",
                  "app: 去除首尾空白")
    t.expect(ComputerUseMCP.appNameArg(["app": "  "]) == nil, "app: 空串拒绝")
    t.expect(ComputerUseMCP.boolArg(["include_screenshot": true], "include_screenshot"),
             "bool: true 读取")
    t.expect(!ComputerUseMCP.boolArg(["include_screenshot": 1], "include_screenshot"),
             "bool: 数字不算 Bool")
    t.expect(!ComputerUseMCP.boolArg([:], "include_screenshot"), "bool: 缺省 false")
    t.expect(ComputerUseMCP.agentInstructions.contains("list_apps"),
             "workflow: 使用 Codex 同名应用发现")
    t.expect(ComputerUseMCP.agentInstructions.contains("disableDiffing=true"),
             "workflow: 说明状态差量与完整树")
    t.expect(ComputerUseMCP.agentInstructions.contains("连续两次"),
             "workflow: 禁止反复盲点坐标")
    t.expect(ComputerUseMCP.agentInstructions.contains("动作发生前确认"),
             "workflow: 注入 Computer Use 风险确认策略")
    t.expectEqual(ComputerUseMCP.elementIndex(["element_index": 42]), 42,
                  "element: 非负整数合法")
    t.expect(ComputerUseMCP.elementIndex(["element_index": -1]) == nil,
             "element: 负数拒绝")
    t.expect(ComputerUseMCP.elementIndex(["element_index": 2.5]) == nil,
             "element: 小数拒绝")
    t.expect(ComputerUseMCP.elementIndex(["element_index": 1000]) == nil,
             "element: 超过扫描上限拒绝")
    t.expect(ComputerUseMCP.elementIndex(["element_index": true]) == nil,
             "element: Bool 不算整数")
    t.expectEqual(ComputerUseMCP.keyArg(["key": "volumeUp"]), .volumeUp, "key: 媒体键名")
    t.expect(ComputerUseMCP.keyArg(["key": "nope"]) == nil, "key: 未知键名拒绝")
    t.expectEqual(ComputerUseMCP.modifierFlags(["modifiers": ["command", "bad", "shift"]]),
                  ["command", "shift"], "modifiers: 白名单过滤")
    t.expect(ComputerUseMCP.modifierFlags([:]).isEmpty, "modifiers: 缺省为空")
    t.expectEqual(ComputerUseMCP.pointArg(["x": 144.5], "x"), 144.5,
                  "codex point: 窗口点坐标合法")
    t.expect(ComputerUseMCP.pointArg(["x": -1], "x") == nil,
             "codex point: 负坐标拒绝")
    t.expectEqual(ComputerUseMCP.clickCount(["click_count": 3]), 3,
                  "codex click: 三击合法")
    t.expect(ComputerUseMCP.clickCount(["click_count": 4]) == nil,
             "codex click: 超过三击拒绝")
    t.expectEqual(ComputerUseMCP.pagesArg(["pages": 10]), 10,
                  "codex scroll: 十页上限合法")
    t.expect(ComputerUseMCP.pagesArg(["pages": 0]) == nil,
             "codex scroll: 零页拒绝")
    t.expectEqual(ComputerUseMCP.stringArg(["value": ""], "value", allowEmpty: true), "",
                  "codex set_value: 允许清空")

    let previous = "App: Demo (com.example.demo)\n0 AXApplication\n1 AXButton title=\"旧\"\n2 AXTextField"
    let current = "App: Demo (com.example.demo)\n0 AXApplication\n1 AXButton title=\"新\"\n3 AXCheckBox"
    let diff = ComputerUseMCP.appStateDiff(previous: previous, current: current)
    t.expect(diff.contains("~ 1 AXButton title=\"新\""), "codex diff: 输出当前变化值")
    t.expect(diff.contains("- 2 AXTextField"), "codex diff: 输出移除元素")
    t.expect(diff.contains("+ 3 AXCheckBox"), "codex diff: 输出新增元素")
    t.expect(ComputerUseMCP.appStateDiff(previous: current, current: current).contains("未变化"),
             "codex diff: 相同状态压缩")
}

// MARK: - config.toml 幂等写入

func runComputerUseMCPConfigSection(_ t: TestRunner) {
    let resources = "/Applications/Tapgo AICoding.app/Contents/Resources"
    let cmd = ComputerUseMCP.bundledHelperExecutablePath(resourcesPath: resources)
    t.expectEqual(
        cmd,
        "/Applications/Tapgo AICoding.app/Contents/Resources/computer-use-helper/Tapgo Computer Use.app/Contents/MacOS/TapgoComputerUseMCP",
        "helper: MCP 指向独立 App 内的真实执行进程"
    )
    t.expect(cmd.contains(ComputerUseMCP.helperDirectoryName), "helper: 路径含稳定 helper 目录")
    t.expect(cmd.contains(ComputerUseMCP.helperAppName), "helper: 路径含可拖拽 App bundle")
    t.expect(cmd.hasSuffix(ComputerUseMCP.helperExecutableName), "helper: 路径以 MCP 可执行文件结尾")

    let installedApp = ComputerUseMCP.installedHelperAppPath(
        applicationSupportPath: "/Users/test/Library/Application Support/Tapgo AICoding"
    )
    t.expectEqual(
        installedApp,
        "/Users/test/Library/Application Support/Tapgo AICoding/computer-use/Tapgo Computer Use.app",
        "helper: 独立安装路径稳定"
    )
    t.expectEqual(
        ComputerUseMCP.helperExecutablePath(helperAppPath: installedApp),
        "/Users/test/Library/Application Support/Tapgo AICoding/computer-use/Tapgo Computer Use.app/Contents/MacOS/TapgoComputerUseMCP",
        "helper: MCP 与权限拖拽共享独立 App"
    )

    // 全新 config: 追加段
    let fresh = "model = \"MiniMax-M3\"\n"
    let up1 = ComputerUseMCP.upsertSection(inConfig: fresh, commandPath: cmd)
    t.expect(up1.contains("[mcp_servers.\(ComputerUseMCP.configServerKey)]"), "toml: 段头写入")
    t.expect(up1.contains("command = \"\(cmd)\""), "toml: command 路径写入")
    t.expect(up1.hasPrefix("model = \"MiniMax-M3\"\n"), "toml: 原有内容保留在前")

    // 幂等: 相同输入再跑一遍, 输出不变
    let up2 = ComputerUseMCP.upsertSection(inConfig: up1, commandPath: cmd)
    t.expectEqual(up2, up1, "toml: 幂等 (重复 upsert 不变)")

    // 路径变化: 只替换 command 行, 不新增段
    let newCmd = "/Users/x/.build/release/TapgoComputerUseMCP"
    let up3 = ComputerUseMCP.upsertSection(inConfig: up1, commandPath: newCmd)
    t.expect(up3.contains("command = \"\(newCmd)\""), "toml: 路径变更被替换")
    t.expect(!up3.contains(cmd), "toml: 旧路径消失")
    t.expectEqual(up3.components(separatedBy: "[mcp_servers.\(ComputerUseMCP.configServerKey)]").count - 1, 1,
                  "toml: 段始终唯一")

    // 段内缺 command 行 (手改坏): 插回 header 之后
    let broken = "a = 1\n[mcp_servers.\(ComputerUseMCP.configServerKey)]\n[other]\nx = 1"
    let up4 = ComputerUseMCP.upsertSection(inConfig: broken, commandPath: cmd)
    if let range = up4.range(of: "[mcp_servers.\(ComputerUseMCP.configServerKey)]\n") {
        t.expect(up4[range.upperBound...].hasPrefix("command = "), "toml: 空段内补插 command")
        t.expect(!up4[range.upperBound...].contains("[other]\ncommand ="), "toml: 不污染下一个段")
    } else {
        t.expect(false, "toml: 段头仍存在")
    }

    // 尾部无换行 / 空文件两种边界
    let up5 = ComputerUseMCP.upsertSection(inConfig: "model = \"m\"", commandPath: cmd)
    t.expect(up5.contains("model = \"m\"\n\n# 电脑控制"), "toml: 无尾换行时补空行")
    let up6 = ComputerUseMCP.upsertSection(inConfig: "", commandPath: cmd)
    t.expect(up6.contains("[mcp_servers.\(ComputerUseMCP.configServerKey)]"), "toml: 空文件可写入")

    // 段文本本身: 指向二进制的 command 形态
    let section = ComputerUseMCP.configSection(commandPath: cmd)
    t.expect(section.hasPrefix("\n"), "toml: section 前有空行分隔")
    t.expect(section.contains("command = \"\(cmd)\""), "toml: section 含 command")

    // 总开关关闭时只移除电脑控制 table，不损坏其它配置；重复关闭幂等。
    let configWithProvider = ComputerUseMCP.upsertSection(
        inConfig: "model = \"MiniMax-M3\"\n\n[model_providers.minimax]\nbase_url = \"https://example.test\"\n",
        commandPath: cmd
    )
    let removed = ComputerUseMCP.removeSection(fromConfig: configWithProvider)
    t.expect(!removed.contains("[mcp_servers.\(ComputerUseMCP.configServerKey)]"),
             "toml: 关闭后移除电脑控制段头")
    t.expect(!removed.contains("# 电脑控制 MCP server"),
             "toml: 关闭后移除生成注释")
    t.expect(removed.contains("model = \"MiniMax-M3\""),
             "toml: 关闭后保留模型配置")
    t.expect(removed.contains("[model_providers.minimax]"),
             "toml: 关闭后保留后续 provider")
    t.expectEqual(ComputerUseMCP.removeSection(fromConfig: removed), removed,
                  "toml: 重复关闭保持幂等")

    let followedByOtherMCP = up6 + "[mcp_servers.keep_me]\ncommand = \"/bin/true\"\n"
    let removedMiddle = ComputerUseMCP.removeSection(fromConfig: followedByOtherMCP)
    t.expect(removedMiddle.contains("[mcp_servers.keep_me]"),
             "toml: 移除电脑控制时保留相邻 MCP")
    t.expect(removedMiddle.contains("command = \"/bin/true\""),
             "toml: 相邻 MCP command 不被误删")
}

// Exercise the persistent bridge with independent simulated one-shot workers.
func runComputerUseObservationSession(_ t: TestRunner) {
    t.expectEqual(ComputerUseMCP.pagesArg(["pages": 0.5]), 0.5, "scroll: accepts fractional pages")
    t.expect(ComputerUseMCP.pagesArg(["pages": true]) == nil, "scroll: rejects boolean pages")
    t.expect(ComputerUseMCP.pagesArg(["pages": Double.infinity]) == nil, "scroll: rejects infinite pages")
    t.expectEqual(ComputerUseMCP.scrollPixelAmount(pages: 1, viewport: 800), 720, "scroll: scales to viewport")
    t.expectEqual(ComputerUseMCP.scrollPixelAmount(pages: 0.5, viewport: 400), 180, "scroll: half-page distance")
    t.expect(ComputerUseMCP.scrollPixelAmount(pages: 1, viewport: 0) == nil, "scroll: rejects unknown viewport")
    t.expect(ComputerUseMCP.scrollPixelAmount(pages: -1, viewport: 800) == nil, "scroll: rejects negative pages")
    let session = ComputerUseObservationSession()
    var calls = 0
    var receivedToken: String?
    var failObservation = false
    let instant = Date(timeIntervalSince1970: 1000)
    func request(_ tool: String, _ args: [String: Any] = [:]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 31, "method": "tools/call", "params": ["name": tool, "arguments": args]])
    }
    func call(_ tool: String, _ args: [String: Any] = [:], at date: Date? = nil) -> Bool {
        let response = session.respond(to: request(tool, args), now: date ?? instant) { data in
            calls += 1
            return ComputerUseMCP.handle(requestData: data) { name, forwarded in
                receivedToken = forwarded["_observation_token"] as? String
                let isState = ComputerUseObservationSession.stateTools.contains(name)
                return .init(isError: isState && failObservation, text: "state", observationToken: isState && !failObservation ? "worker-hash" : nil)
            }
        }
        let object = response.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        return (object?["result"] as? [String: Any])?["isError"] as? Bool == true
    }
    let index: [String: Any] = ["app": "Editor", "element_index": 4]
    t.expect(call("click", index), "observation: unobserved index rejected")
    t.expectEqual(calls, 0, "observation: rejected action never dispatches")
    t.expect(!call("get_ax_state", ["app": "Editor", "_observation_token": "forged"]), "observation: AX-only read succeeds")
    t.expect(receivedToken == nil, "observation: caller cannot inject internal token")
    t.expect(call("click", ["app": "Other", "element_index": 4]), "observation: index cannot cross apps")
    t.expect(!call("click", index), "observation: recent same-app index dispatches")
    t.expectEqual(receivedToken, "worker-hash", "observation: exact prior worker hash forwarded")
    t.expect(call("click", index), "observation: second action requires fresh observation")
    _ = call("get_app_state", ["app": "Editor"])
    _ = call("get_screenshot", ["app": "Editor"])
    t.expect(call("set_value", index), "observation: screenshot invalidates AX indexes")
    _ = call("get_ax_state_and_screenshot", ["app": "Editor"])
    t.expect(!call("set_value", index), "observation: combined read provides valid indexes")
    _ = call("get_ax_state", ["app": "Editor"])
    t.expect(call("click", index, at: instant.addingTimeInterval(121)), "observation: old snapshot expires")
    t.expect(call("click", index, at: instant.addingTimeInterval(-1)), "observation: clock reversal rejects snapshot")
    _ = call("get_ax_state", ["app": "Editor"])
    failObservation = true
    t.expect(call("get_ax_state", ["app": "Editor"]), "observation: failed observation surfaced")
    t.expect(call("click", index), "observation: failed reread discards previous snapshot")
    failObservation = false
    _ = call("get_ax_state", ["app": "Editor"])
    _ = call("press_key", ["app": "Other", "key": "Return"])
    t.expect(call("click", index), "observation: cross-app mutation invalidates stale focus")
    _ = call("get_ax_state", ["app": "Editor"])
    _ = call("list_apps")
    t.expect(!call("click", index), "observation: discovery preserves observation")
    let newSession = ComputerUseObservationSession()
    var dispatched = false
    _ = newSession.respond(to: request("click", index)) { _ in dispatched = true; return nil }
    t.expect(!dispatched, "observation: restarted bridge does not inherit stale state")
}
