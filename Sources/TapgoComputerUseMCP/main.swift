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
import TapgoComputerUse
import TapgoCore

func stderrLog(_ message: String) {
    FileHandle.standardError.write(Data(("[tapgo-computer-use] \(message)\n").utf8))
}

/// 权限缺失时的统一提示 (模型可把这段话转述给用户)。
let screenPermissionHint =
    "截屏失败: 本进程没有 macOS「屏幕录制」权限。请让用户在「系统设置 → 隐私与安全性 → 屏幕录制」里为 Tapgo AICoding 勾选授权, 然后重启 App 重试。"
let accessibilityHint =
    "操作失败: 本进程没有 macOS「辅助功能」权限。请让用户在「系统设置 → 隐私与安全性 → 辅助功能」里为 Tapgo AICoding 勾选授权, 然后重启 App 重试。"
let invalidCoordHint = "参数错误: x/y 必须是 0...1 的归一化坐标 (相对主屏截图, 左上原点)。请先调用 screenshot 获取画面。"

/// 工具执行器: MCP 协议层 → ComputerUse 原语。
let executor: ComputerUseMCP.Executor = { tool, args in
    switch tool {
    case "screenshot":
        guard ComputerUse.screenCaptureAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: screenPermissionHint)
        }
        guard let jpeg = ComputerUse.screenshotJPEG(maxSide: 1280) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "截屏失败: CGDisplayCreateImage 返回空。")
        }
        let size = ComputerUse.mainScreenSize()
        return ComputerUseMCP.ToolOutcome(
            isError: false,
            text: String(format: "主屏 %.0fx%.0f pt (像素 %dx%d, scale %.0fx)。图像按最长边 1280 等比缩放; 点击请用相对该图像的归一化坐标。",
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
        ComputerUse.click(nx: x, ny: y, doubleClick: tool == "double_click")
        let verb = tool == "double_click" ? "双击" : "单击"
        return ComputerUseMCP.ToolOutcome(isError: false,
                                          text: "已在 (\(x), \(y)) 完成\(verb)。建议截屏核对结果。")

    case "type_text":
        guard ComputerUse.accessibilityAllowed else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: accessibilityHint)
        }
        guard let text = ComputerUseMCP.textArg(args) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "参数错误: 需要非空 text 字符串。")
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
        ComputerUse.scroll(lines: dy)
        return ComputerUseMCP.ToolOutcome(isError: false, text: "已滚动 \(Int(dy)) 行。")

    case "open_application":
        guard let name = (args["name"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "参数错误: 需要非空 name (应用名, 如 Safari)。")
        }
        guard ComputerUse.openApplication(named: name) else {
            return ComputerUseMCP.ToolOutcome(isError: true, text: "启动 \(name) 失败 (open -a 返回错误)。")
        }
        return ComputerUseMCP.ToolOutcome(isError: false,
                                          text: "已请求启动 \(name)。等 1-2 秒后截屏确认窗口状态。")

    default:
        return ComputerUseMCP.ToolOutcome(isError: true, text: "未知工具: \(tool)")
    }
}

stderrLog("started (pid \(ProcessInfo.processInfo.processIdentifier), tools: \(ComputerUseMCP.toolNames.count))")
while let line = readLine(strippingNewline: true) {
    let data = Data(line.utf8)
    guard !data.isEmpty else { continue }
    guard let response = ComputerUseMCP.handle(requestData: data, executor: executor) else { continue }
    FileHandle.standardOutput.write(response)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
stderrLog("stdin closed, exiting")
