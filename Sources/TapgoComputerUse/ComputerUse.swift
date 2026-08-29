import AppKit
import ApplicationServices
import CoreGraphics
import TapgoCore

/// 电脑控制原语 (v0.5.18) — 截屏 + 鼠标/键盘注入 + 系统命令。
///
/// 两个消费者:
/// * `TapgoComputerUseMCP` — MCP stdio server, 把这些能力暴露给模型
///   (Computer Use 风格的桌面自动化工作流)。
/// * App 端 `PhoneRemoteServer` — 手机 H5「电脑控制」页 (v0.5.17)。
///
/// 所有坐标一律归一化 0...1 (主屏, 左上原点), 与分辨率/缩放无关。
/// 需要 TCC 权限: 「屏幕录制」(截屏)、「辅助功能」(鼠标/键盘/锁屏)。
public enum ComputerUse {

    // MARK: - Permissions

    /// 「屏幕录制」TCC 权限预检 (不弹窗)。
    public static var screenCaptureAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 「辅助功能」TCC 权限预检 (不弹窗)。
    public static var accessibilityAllowed: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权弹窗 (App 设置页 / MCP 工具错误提示引导用户授权)。
    public static func requestPermissions() {
        _ = CGRequestScreenCaptureAccess()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Screen

    /// 主屏尺寸: 逻辑点数 + 像素 + 缩放系数 (归一化坐标的换算依据)。
    public static func mainScreenSize() -> (pointWidth: CGFloat, pointHeight: CGFloat,
                                            pixelWidth: Int, pixelHeight: Int, scale: CGFloat) {
        let id = CGMainDisplayID()
        let bounds = CGDisplayBounds(id)
        let scale = bounds.width > 0 ? CGFloat(CGDisplayPixelsWide(id)) / bounds.width : 1
        return (bounds.width, bounds.height, CGDisplayPixelsWide(id), CGDisplayPixelsHigh(id), scale)
    }

    /// 主屏截图 → JPEG。`maxSide` 限制最长边 (控制返回体量;
    /// 归一化坐标与分辨率无关)。
    public static func screenshotJPEG(maxSide: CGFloat) -> Data? {
        let displayID = CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayID) else { return nil }
        let longest = CGFloat(max(image.width, image.height))
        let scaled = scaledImage(image, maxSide: longest > maxSide ? maxSide : longest)
        let rep = NSBitmapImageRep(cgImage: scaled ?? image)
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: 0.72])
    }

    /// 等比缩放 CGImage 到最长边 `maxSide` (若已小于则返回 nil 让调用方用原图)。
    static func scaledImage(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard maxSide > 0, max(w, h) > maxSide else { return nil }
        let scale = maxSide / max(w, h)
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let ctx = CGContext(data: nil, width: tw, height: th,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }

    /// 归一化坐标 (0...1, 相对主屏截图、原点左上) → 全局 CG 坐标 (原点左下)。
    public static func displayPoint(nx: Double, ny: Double) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: bounds.minX + CGFloat(nx) * bounds.width,
                       y: bounds.minY + (1 - CGFloat(ny)) * bounds.height)
    }

    // MARK: - Mouse / keyboard

    /// 在归一化坐标处单击 / 双击 (先移动光标再按抬)。
    public static func click(nx: Double, ny: Double, doubleClick: Bool) {
        let pt = displayPoint(nx: nx, ny: ny)
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                           mouseCursorPosition: pt, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        usleep(20_000)
        let clicks = doubleClick ? 2 : 1
        for state in 1...clicks {
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                               mouseCursorPosition: pt, mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                             mouseCursorPosition: pt, mouseButton: .left)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
            up?.post(tap: .cghidEventTap)
            if state < clicks { usleep(120_000) }
        }
    }

    /// 滚轮: `lines` 行, 正数向下。限幅 ±20 行防误操作把页面滚飞。
    public static func scroll(lines: Double) {
        let clamped = max(-20, min(20, lines))
        let ev = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                         wheel1: Int32(-clamped), wheel2: 0, wheel3: 0)
        ev?.post(tap: .cghidEventTap)
    }

    /// 逐字符注入键盘输入。`kCGKeyboardEventKeycode=0` + UnicodeString 的
    /// 形态对绝大多数 App 生效; 换行转成 Return 键。
    public static func typeText(_ text: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        for ch in text {
            if ch == "\n" || ch == "\r" {
                postKey(CGKeyCode(36), source: src, flags: [])
                continue
            }
            let units = Array(String(ch).utf16)
            for keyDown in [true, false] {
                let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: keyDown)
                ev?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                ev?.post(tap: .cghidEventTap)
            }
            usleep(2_000)
        }
    }

    /// 按命名按键 (普通键/媒体键), 可选修饰键组合。未知键名返回 false。
    @discardableResult
    public static func pressKey(name: String, modifiers: [String] = []) -> Bool {
        guard let key = PhoneRemote.ControlKey(rawValue: name) else { return false }
        var flags: CGEventFlags = []
        for m in modifiers {
            switch m {
            case "command": flags.insert(.maskCommand)
            case "control": flags.insert(.maskControl)
            case "option": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: break
            }
        }
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        if let code = key.virtualKeyCode {
            postKey(CGKeyCode(code), source: src, flags: flags)
        } else if let media = key.mediaKeyType {
            postMediaKey(media)
        }
        return true
    }

    private static func postKey(_ code: CGKeyCode, source: CGEventSource?, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    /// 媒体键 (音量/亮度/播放): `NX_KEYTYPE_*` 打包进 NSEvent systemDefined
    /// subtype 8 的 data1 (高 16 位是按下 0x0A / 抬起 0x0B, 低 16 位是键型),
    /// 再取 CGEvent 投递 —— 这是苹果未文档化但长期稳定的公开接口形态。
    private static func postMediaKey(_ type: Int) {
        for flag in [0x0a, 0x0b] {   // 0x0a = 按下, 0x0b = 抬起
            let data1 = (type << 16) | (flag << 8)
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - System commands

    /// 系统级命令: 锁屏 (Ctrl+Cmd+Q) / 睡眠 (pmset sleepnow)。
    public static func performCommand(_ action: PhoneRemote.ControlAction) {
        switch action {
        case .lock:
            guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
            for keyDown in [true, false] {
                let ev = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: keyDown)
                ev?.flags = [.maskControl, .maskCommand]
                ev?.post(tap: .cghidEventTap)
            }
        case .sleep:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["sleepnow"]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
        }
    }

    /// 按名字启动一个 macOS 应用 (等价 `open -a <name>`)。
    @discardableResult
    public static func openApplication(named name: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", name]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            return true
        } catch {
            return false
        }
    }
}
