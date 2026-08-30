// TapgoComputerUseMCP — 电脑控制 MCP stdio server (v0.5.20)。
//
// 由 codex harness 按隔离 Codex home `config.toml` 里
// `[mcp_servers.tapgo_computer_use]` 的 command 拉起, 让模型
// (MiniMax-M3 等) 能直接调用截屏 / 鼠标 / 键盘工具, 完成
// Computer Use 风格的桌面自动化工作流。
//
// 协议: JSON-RPC 2.0 over stdio, 一行一条消息 (MCP stdio 规约)。
// 协议分发与工具注册表在 TapgoCore/ComputerUseMCP.swift (可单测),
// 真实执行走 TapgoComputerUse/ComputerUse.swift (CGEvent/截屏)。
// 诊断日志一律走 stderr, stdout 只输出 MCP 响应。

import Foundation
import Darwin
import TapgoComputerUse
import TapgoCore

func stderrLog(_ message: String) {
    FileHandle.standardError.write(Data(("[tapgo-computer-use] \(message)\n").utf8))
}

func permissionStatusData() -> Data? {
    let payload: [String: Any] = [
        "accessibility": ComputerUse.accessibilityAllowed,
        "screen_recording": ComputerUse.screenCaptureAllowed,
        "bundle_identifier": Bundle.main.bundleIdentifier ?? "",
    ]
    return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
}

/// Read-only status probe used by the settings UI. The file form is launched
/// through Launch Services so macOS evaluates the helper app's own TCC
/// identity rather than inheriting the calling terminal/application context.
let commandArguments = Array(CommandLine.arguments.dropFirst())
if commandArguments.first == "--permission-status" {
    if let data = permissionStatusData() {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(EXIT_SUCCESS)
    }
    exit(EXIT_FAILURE)
}
if commandArguments.first == "--permission-status-file",
   commandArguments.count == 2,
   let data = permissionStatusData() {
    do {
        try data.write(to: URL(fileURLWithPath: commandArguments[1]), options: .atomic)
        exit(EXIT_SUCCESS)
    } catch {
        stderrLog("permission status write failed: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}

/// 权限缺失时的统一提示 (模型可把这段话转述给用户)。
let screenPermissionHint =
    "截屏失败: Tapgo Computer Use 没有 macOS「屏幕录制」权限。请在 Tapgo AICoding 的电脑控制设置中打开对应系统页面并完成授权，然后重启会话重试。"
let accessibilityHint =
    "操作失败: Tapgo Computer Use 没有 macOS「辅助功能」权限。请在 Tapgo AICoding 的电脑控制设置中打开对应系统页面并完成授权，然后重启会话重试。"
let invalidCoordHint = "参数错误: x/y 必须是 0...1 的归一化坐标（左上原点）。处理应用窗口时先调用 screenshot(app=...)，点击时也传同一个 app。"

/// 工具执行器: MCP 协议层 → ComputerUse 原语。
let executor: ComputerUseMCP.Executor = { tool, args in
    switch tool {
    case "list_applications":
        return ComputerUseMCP.ToolOutcome(
            isError: false,
            text: ComputerUse.runningApplicationsDescription())

    case "get_app_state":
        guard ComputerUse.accessibilityAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: accessibilityHint)
        }
        guard let app = ComputerUseMCP.appNameArg(args) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "参数错误: 需要非空 app（应用名或 bundle id）。")
        }
        guard let state = ComputerUse.appStateDescription(appName: app) else {
            return ComputerUseMCP.ToolOutcome(
                isError: true,
                text: "无法读取 \(app) 的辅助功能界面树。请先调用 list_applications，并确认辅助功能权限。")
        }
        if ComputerUseMCP.boolArg(args, "include_screenshot") {
            guard ComputerUse.screenCaptureAllowed else {
                return ComputerUseMCP.ToolOutcome(
                    isError: true,
                    text: state + "\n\n" + screenPermissionHint
                )
            }
            guard let capture = ComputerUse.applicationScreenshotJPEG(appName: app) else {
                return ComputerUseMCP.ToolOutcome(
                    isError: true,
                    text: state + "\n\n应用窗口截图失败；目标窗口可能未显示在主桌面。"
                )
            }
            let metadata = "\n\n窗口截图: \(capture.appLabel) \(Int(capture.pointWidth))x\(Int(capture.pointHeight)) pt，window_id=\(capture.windowID)。坐标工具传 app 时相对这张图。"
            return ComputerUseMCP.ToolOutcome(
                isError: false,
                text: state + metadata,
                imageJPEGBase64: capture.jpeg.base64EncodedString()
            )
        }
        return ComputerUseMCP.ToolOutcome(isError: false, text: state)

    case "click_element":
        guard ComputerUse.accessibilityAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: accessibilityHint)
        }
        guard let app = ComputerUseMCP.appNameArg(args),
              let index = ComputerUseMCP.elementIndex(args) else {
            return ComputerUseMCP.ToolOutcome(
                isError: true,
                text: "参数错误: 需要非空 app 与非负整数 element_index。请先调用 get_app_state。")
        }
        let result = ComputerUse.pressElement(appName: app, index: index)
        return ComputerUseMCP.ToolOutcome(isError: !result.success, text: result.message)

    case "set_element_value":
        guard ComputerUse.accessibilityAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: accessibilityHint)
        }
        guard let app = ComputerUseMCP.appNameArg(args),
              let index = ComputerUseMCP.elementIndex(args),
              let text = ComputerUseMCP.elementValueArg(args) else {
            return ComputerUseMCP.ToolOutcome(
                isError: true,
                text: "参数错误: 需要 app、element_index 与字符串 text。请先调用 get_app_state。"
            )
        }
        let result = ComputerUse.setElementValue(appName: app, index: index, value: text)
        return ComputerUseMCP.ToolOutcome(isError: !result.success, text: result.message)

    case "screenshot":
        guard ComputerUse.screenCaptureAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: screenPermissionHint)
        }
        if let app = ComputerUseMCP.appNameArg(args) {
            guard let capture = ComputerUse.applicationScreenshotJPEG(appName: app) else {
                return ComputerUseMCP.ToolOutcome(
                    isError: true,
                    text: "截取 \(app) 窗口失败；请先调用 open_application 或 list_applications 确认应用正在运行。"
                )
            }
            return ComputerUseMCP.ToolOutcome(
                isError: false,
                text: "应用窗口 \(capture.appLabel) \(Int(capture.pointWidth))x\(Int(capture.pointHeight)) pt，window_id=\(capture.windowID)。坐标工具传 app 时相对本图，左上原点。",
                imageJPEGBase64: capture.jpeg.base64EncodedString()
            )
        }
        guard let jpeg = ComputerUse.screenshotJPEG(maxSide: 1600) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "主屏截图失败: CGDisplayCreateImage 返回空。")
        }
        let size = ComputerUse.mainScreenSize()
        return ComputerUseMCP.ToolOutcome(
            isError: false,
            text: String(format: "主屏 %.0fx%.0f pt (像素 %dx%d, scale %.0fx)。图像按最长边 1600 等比缩放；主屏点击省略 app 并使用相对本图坐标。",
                         size.pointWidth, size.pointHeight, size.pixelWidth, size.pixelHeight, size.scale),
            imageJPEGBase64: jpeg.base64EncodedString())

    case "get_screen_size":
        let size = ComputerUse.mainScreenSize()
        return ComputerUseMCP.ToolOutcome(
            isError: false,
            text: String(format: "主屏 %.0fx%.0f pt, 像素 %dx%d, 缩放 %.0fx。",
                         size.pointWidth, size.pointHeight, size.pixelWidth, size.pixelHeight, size.scale))

    case "left_click", "double_click":
        guard ComputerUse.accessibilityAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: accessibilityHint)
        }
        guard let (x, y) = ComputerUseMCP.normalizedCoord(args) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: invalidCoordHint)
        }
        let result = ComputerUse.click(
            nx: x,
            ny: y,
            doubleClick: tool == "double_click",
            appName: ComputerUseMCP.appNameArg(args)
        )
        return ComputerUseMCP.ToolOutcome(isError: !result.success, text: result.message)

    case "type_text":
        guard ComputerUse.accessibilityAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: accessibilityHint)
        }
        guard let text = ComputerUseMCP.textArg(args) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "参数错误: 需要非空 text 字符串。")
        }
        if let app = ComputerUseMCP.appNameArg(args),
           !ComputerUse.activateApplication(named: app) {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "无法聚焦目标应用 \(app)。")
        }
        ComputerUse.typeText(text)
        return ComputerUseMCP.ToolOutcome(isError: false,
                                          text: "已输入 \(text.count) 个字符。建议截屏核对结果。")

    case "press_key":
        guard ComputerUse.accessibilityAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: accessibilityHint)
        }
        guard let key = ComputerUseMCP.keyArg(args) else {
            let names = PhoneRemote.ControlKey.allCases.map(\.rawValue).sorted().joined(separator: ", ")
            return ComputerUseMCP.ToolOutcome(
                isError: true,
                text: "参数错误: key 必须是命名按键之一 (\(names))。")
        }
        let modifiers = ComputerUseMCP.modifierFlags(args)
        if let app = ComputerUseMCP.appNameArg(args),
           !ComputerUse.activateApplication(named: app) {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "无法聚焦目标应用 \(app)。")
        }
        ComputerUse.pressKey(name: key.rawValue, modifiers: modifiers)
        let combo = modifiers.isEmpty ? key.rawValue : key.rawValue + " + " + modifiers.joined(separator: "+")
        return ComputerUseMCP.ToolOutcome(isError: false, text: "已按键 \(combo)。")

    case "scroll":
        guard ComputerUse.accessibilityAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: accessibilityHint)
        }
        guard let dy = ComputerUseMCP.lineDelta(args) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "参数错误: dy 必须是非 0 数值 (行数, 正=向下)。")
        }
        if let app = ComputerUseMCP.appNameArg(args),
           !ComputerUse.activateApplication(named: app) {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "无法聚焦目标应用 \(app)。")
        }
        ComputerUse.scroll(lines: dy)
        return ComputerUseMCP.ToolOutcome(isError: false, text: "已滚动 \(Int(dy)) 行。")

    case "open_application":
        guard let name = (args["name"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "参数错误: 需要非空 name (应用名, 如 Safari)。")
        }
        guard ComputerUse.openApplication(named: name) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "启动 \(name) 失败 (open -a 返回错误)。")
        }
        return ComputerUseMCP.ToolOutcome(
            isError: false,
            text: "已启动并切到 \(name)。请调用 get_app_state(app=\"\(name)\", include_screenshot=true) 确认。"
        )

    default:
        return ComputerUseMCP.ToolOutcome(isError: true, text: "未知工具: \(tool)")
    }
}

/// Resolve the containing helper `.app` from the executable path. The MCP
/// bridge itself is started directly by Codex, but privileged operations must
/// be executed by a fresh Launch Services instance of this app so macOS TCC
/// evaluates `com.tapgo.aicoding.computer-use-helper` instead of the Harness
/// parent-process chain.
func containingHelperAppURL() -> URL? {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let app = executable
        .deletingLastPathComponent() // MacOS
        .deletingLastPathComponent() // Contents
        .deletingLastPathComponent() // Tapgo Computer Use.app
    guard app.pathExtension == "app",
          FileManager.default.fileExists(atPath: app.path) else { return nil }
    return app
}

func bridgeFailureResponse(requestData: Data, message: String) -> Data? {
    ComputerUseMCP.handle(requestData: requestData) { _, _ in
        ComputerUseMCP.ToolOutcome(isError: true, text: message)
    }
}

/// Only accept bridge files created in the helper's own owner-only temporary
/// directory. This prevents one-shot mode from being abused to read from or
/// write to arbitrary paths (including symbolic links).
func bridgeFileURLsAreSafe(requestURL: URL, responseURL: URL) -> Bool {
    let fm = FileManager.default
    let request = requestURL.standardizedFileURL
    let response = responseURL.standardizedFileURL
    let directory = request.deletingLastPathComponent()
    let temporaryRoot = fm.temporaryDirectory.standardizedFileURL
    guard response.deletingLastPathComponent() == directory,
          directory.deletingLastPathComponent() == temporaryRoot,
          directory.lastPathComponent.hasPrefix("tapgo-computer-use-"),
          request.lastPathComponent == "request.json",
          response.lastPathComponent == "response.json",
          !fm.fileExists(atPath: response.path),
          let attributes = try? fm.attributesOfItem(atPath: directory.path),
          (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
          let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
          permissions & 0o777 == 0o700,
          let values = try? request.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          values.isRegularFile == true,
          values.isSymbolicLink != true else { return false }
    return true
}

/// Execute one `tools/call` through Launch Services and return the helper's
/// exact JSON-RPC response. Request/response files live in an owner-only
/// temporary directory and are deleted after every call.
func launchServicesResponse(requestData: Data, helperAppURL: URL) -> Data? {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory
        .appendingPathComponent("tapgo-computer-use-\(UUID().uuidString)", isDirectory: true)
    let requestURL = directory.appendingPathComponent("request.json")
    let responseURL = directory.appendingPathComponent("response.json")
    do {
        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fm.removeItem(at: directory) }
        try requestData.write(to: requestURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n", helperAppURL.path,
            "--args", "--execute-request-file", requestURL.path, responseURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return bridgeFailureResponse(
                requestData: requestData,
                message: "电脑控制 Helper 启动失败（open exit \(process.terminationStatus)）。"
            )
        }

        let deadline = Date().addingTimeInterval(15)
        repeat {
            if let data = try? Data(contentsOf: responseURL), !data.isEmpty {
                return data
            }
            usleep(20_000)
        } while Date() < deadline
        return bridgeFailureResponse(
            requestData: requestData,
            message: "电脑控制 Helper 响应超时，请重新检测权限后重试。"
        )
    } catch {
        return bridgeFailureResponse(
            requestData: requestData,
            message: "电脑控制 Helper 桥接失败：\(error.localizedDescription)"
        )
    }
}

/// One-shot worker mode. This process is launched by Launch Services, so the
/// actual executor sees the helper app's Accessibility/Screen Recording TCC
/// grants. The stdio bridge waits for this response file and forwards it to
/// Codex unchanged.
if commandArguments.first == "--execute-request-file",
   commandArguments.count == 3 {
    let requestURL = URL(fileURLWithPath: commandArguments[1])
    let responseURL = URL(fileURLWithPath: commandArguments[2])
    do {
        guard bridgeFileURLsAreSafe(requestURL: requestURL, responseURL: responseURL) else {
            stderrLog("one-shot request rejected: unsafe bridge paths")
            exit(EXIT_FAILURE)
        }
        let requestData = try Data(contentsOf: requestURL)
        guard requestData.count <= 1_048_576 else {
            stderrLog("one-shot request rejected: request exceeds 1 MiB")
            exit(EXIT_FAILURE)
        }
        guard let response = ComputerUseMCP.handle(requestData: requestData, executor: executor) else {
            exit(EXIT_SUCCESS)
        }
        try response.write(to: responseURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: responseURL.path
        )
        exit(EXIT_SUCCESS)
    } catch {
        stderrLog("one-shot request failed: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}

stderrLog("started (pid \(ProcessInfo.processInfo.processIdentifier), tools: \(ComputerUseMCP.toolNames.count))")
let helperAppURL = containingHelperAppURL()
while let line = readLine(strippingNewline: true) {
    let data = Data(line.utf8)
    guard !data.isEmpty else { continue }
    let method = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["method"] as? String
    let response: Data?
    if method == "tools/call", let helperAppURL {
        response = launchServicesResponse(requestData: data, helperAppURL: helperAppURL)
    } else {
        response = ComputerUseMCP.handle(requestData: data, executor: executor)
    }
    guard let response else { continue }
    FileHandle.standardOutput.write(response)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
stderrLog("stdin closed, exiting")
