// TapgoTests/ComputerUseMCPTests.swift
// v0.5.20 电脑控制 MCP server — 协议层回归 (TapgoCore/ComputerUseMCP.swift)。
// 覆盖: JSON-RPC 分发、工具注册表 schema、参数解析助手、config.toml 幂等写入。
import Foundation
@testable import TapgoCore

// MARK: - JSON-RPC 分发 + 工具注册表

func runComputerUseMCPProtocol(_ t: TestRunner) {
    let noop: ComputerUseMCP.Executor = { _, _ in ComputerUseMCP.ToolOutcome(text: "ok") }

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

    // tools/list: 全集 + schema 形态 + press_key 枚举
    let listReq = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
    if let data = ComputerUseMCP.handle(requestData: Data(listReq.utf8), executor: noop),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let result = obj["result"] as? [String: Any],
       let tools = result["tools"] as? [[String: Any]] {
        t.expectEqual(tools.count, ComputerUseMCP.toolNames.count, "mcp: 工具数与注册表一致")
        t.expectEqual(tools.count, 11, "mcp: 工具全集 11 个")
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
        // press_key 的 key 枚举复用 PhoneRemote.ControlKey 键名
        let press = tools.first { ($0["name"] as? String) == "press_key" }
        let props = ((press?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        let keyEnum = ((props?["key"] as? [String: Any])?["enum"] as? [String]) ?? []
        t.expect(keyEnum.contains("return"), "mcp: press_key 枚举含 return")
        t.expect(keyEnum.contains("volumeUp"), "mcp: press_key 枚举含媒体键")
        t.expectEqual(keyEnum.count, PhoneRemote.ControlKey.allCases.count, "mcp: press_key 枚举全集")
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
    t.expectEqual(ComputerUseMCP.appNameArg(["app": " com.apple.Safari "]), "com.apple.Safari",
                  "app: 去除首尾空白")
    t.expect(ComputerUseMCP.appNameArg(["app": "  "]) == nil, "app: 空串拒绝")
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
