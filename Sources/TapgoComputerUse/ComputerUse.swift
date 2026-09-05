import AppKit
import ApplicationServices
import CoreGraphics
import CryptoKit
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

    public struct ElementActionResult {
        public let success: Bool
        public let message: String

        public init(success: Bool, message: String) {
            self.success = success
            self.message = message
        }
    }

    public struct ApplicationScreenshot {
        public let jpeg: Data
        public let appLabel: String
        public let pointWidth: CGFloat
        public let pointHeight: CGFloat
        public let windowID: CGWindowID
    }

    public struct ApplicationDescriptor: Codable {
        public let id: String
        public let displayName: String?
        public let isRunning: Bool

        public init(id: String, displayName: String?, isRunning: Bool) {
            self.id = id
            self.displayName = displayName
            self.isRunning = isRunning
        }
    }

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
        requestScreenCapturePermission()
        requestAccessibilityPermission()
    }

    /// 只申请屏幕录制，供 Web Remote 的单项权限入口使用。
    public static func requestScreenCapturePermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// 只申请辅助功能，供 Web Remote 的单项权限入口使用。
    public static func requestAccessibilityPermission() {
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

    private struct ApplicationWindowInfo {
        let id: CGWindowID
        let bounds: CGRect
    }

    /// Capture only the target application's frontmost visible normal window.
    /// `/usr/sbin/screencapture -l` is used because the modern SDK removes the
    /// legacy per-window CoreGraphics image API; the child remains attributed
    /// to this signed Helper's Screen Recording identity.
    public static func applicationScreenshotJPEG(
        appName: String?,
        maxSide: CGFloat = 1600
    ) -> ApplicationScreenshot? {
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else { return nil }
        app.activate(options: [.activateAllWindows])
        usleep(180_000)
        guard let window = primaryWindowInfo(for: app) else { return nil }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapgo-window-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(window.id)", "-tjpg", fileURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let raw = try? Data(contentsOf: fileURL),
                  let bitmap = NSBitmapImageRep(data: raw),
                  let image = bitmap.cgImage else { return nil }
            let scaled = scaledImage(image, maxSide: maxSide) ?? image
            let rep = NSBitmapImageRep(cgImage: scaled)
            guard let jpeg = rep.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.76]
            ) else { return nil }
            return ApplicationScreenshot(
                jpeg: jpeg,
                appLabel: app.localizedName ?? app.bundleIdentifier ?? "未知应用",
                pointWidth: window.bounds.width,
                pointHeight: window.bounds.height,
                windowID: window.id
            )
        } catch {
            return nil
        }
    }

    @discardableResult
    public static func activateApplication(named name: String?) -> Bool {
        guard let app = resolveApplication(named: name, launchIfNeeded: true) else { return false }
        let activated = app.activate(options: [.activateAllWindows])
        if activated { usleep(120_000) }
        return activated
    }

    private static func primaryWindowInfo(for app: NSRunningApplication) -> ApplicationWindowInfo? {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        return raw.compactMap { item -> ApplicationWindowInfo? in
            guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == app.processIdentifier,
                  (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = item[kCGWindowNumber as String] as? NSNumber,
                  let boundsDictionary = item[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(
                    dictionaryRepresentation: boundsDictionary as CFDictionary
                  ),
                  bounds.width >= 120, bounds.height >= 80 else { return nil }
            return .init(id: CGWindowID(number.uint32Value), bounds: bounds)
        }.first // CGWindowList is front-to-back: dialogs must win over larger background windows.
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

    /// 归一化坐标 (0...1, 相对主屏截图、原点左上) → 全局 CG 坐标。
    public static func displayPoint(nx: Double, ny: Double) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: bounds.minX + CGFloat(nx) * bounds.width,
                       y: bounds.minY + CGFloat(ny) * bounds.height)
    }

    // MARK: - Semantic UI access

    /// Enumerate user-facing running applications. This gives the model a
    /// stable bundle identifier to pass to `get_app_state` / `click_element`.
    public static func runningApplicationsDescription() -> String {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .sorted {
                ($0.localizedName ?? $0.bundleIdentifier ?? "")
                    .localizedCaseInsensitiveCompare($1.localizedName ?? $1.bundleIdentifier ?? "") == .orderedAscending
            }
        guard !apps.isEmpty else { return "没有可枚举的前台应用。" }
        return apps.map { app in
            let name = app.localizedName ?? "未知应用"
            let bundle = app.bundleIdentifier ?? "无 bundle id"
            let active = app.processIdentifier == frontmostPID ? " · 当前前台" : ""
            return "- \(name) (\(bundle), pid \(app.processIdentifier))\(active)"
        }.joined(separator: "\n")
    }

    /// Codex Computer Use-compatible application discovery. Installed regular
    /// applications are included in addition to running ones, so a later
    /// `get_app_state` can transparently launch a selected app.
    public static func applicationDescriptors() -> [ApplicationDescriptor] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
        var byID: [String: ApplicationDescriptor] = [:]
        for app in running {
            let id = app.bundleIdentifier ?? app.bundleURL?.path ?? app.localizedName ?? "pid:\(app.processIdentifier)"
            byID[id.lowercased()] = .init(
                id: id,
                displayName: app.localizedName,
                isRunning: true
            )
        }

        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
        let keys: Set<URLResourceKey> = [.isApplicationKey, .isDirectoryKey, .nameKey]
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                let bundle = Bundle(url: url)
                let id = bundle?.bundleIdentifier ?? url.path
                let key = id.lowercased()
                guard byID[key] == nil else { continue }
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                byID[key] = .init(id: id, displayName: displayName, isRunning: false)
            }
        }
        return byID.values.sorted {
            ($0.displayName ?? $0.id).localizedCaseInsensitiveCompare($1.displayName ?? $1.id)
                == .orderedAscending
        }
    }

    /// Read a bounded, flattened Accessibility tree. Values from secure text
    /// fields are always redacted. Indices are ephemeral and must be refreshed
    /// after navigation/state changes before `click_element` is called.
    public static func appStateDescription(appName: String?, maxElements: Int = 600) -> String? {
        observationToken = nil
        observedNodes.removeAll()
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else { return nil }
        app.activate(options: [.activateAllWindows])
        usleep(120_000)
        let nodes = accessibilityNodes(for: app, maxElements: maxElements)
        guard !nodes.isEmpty else { return nil }
        let appLabel = app.localizedName ?? app.bundleIdentifier ?? "未知应用"
        let lines = nodes.enumerated().map { index, node in
            "\(index) " + accessibilityLine(for: node.element, depth: node.depth)
        }
        observedNodes[app.processIdentifier] = nodes
        let window = primaryWindowInfo(for: app)
        let identity = "pid=\(app.processIdentifier);launch=\(app.launchDate?.timeIntervalSince1970 ?? 0);window=\(window?.id ?? 0);bounds=\(String(describing: window?.bounds))"
        let evidence = identity + "\n" + lines.joined(separator: "\n") + "\n" + nodes.map {
            String(describing: elementFrame($0.element))
        }.joined(separator: "\n")
        observationToken = SHA256.hash(data: Data(evidence.utf8)).map { String(format: "%02x", $0) }.joined()
        let suffix = nodes.count >= maxElements ? "\n… 已达到 \(maxElements) 个元素上限" : ""
        return "App: \(appLabel) (\(app.bundleIdentifier ?? "无 bundle id"))\n"
            + lines.joined(separator: "\n") + suffix
    }

    /// Perform the standard Accessibility `press` action on a freshly
    /// resolved element index. The app is activated first so the action lands
    /// in the same visible context the model just inspected.
    public static func pressElement(appName: String?, index: Int) -> ElementActionResult {
        guard index >= 0 else {
            return .init(success: false, message: "element_index 必须是非负整数。")
        }
        guard let app = resolveApplication(named: appName) else {
            return .init(success: false, message: "未找到目标应用。请先调用 list_applications。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(120_000)
        let nodes = validatedNodes(for: app)
        guard nodes.indices.contains(index) else {
            return .init(success: false, message: "元素索引 \(index) 已失效或不存在；请重新调用 get_app_state。")
        }
        let error = AXUIElementPerformAction(nodes[index].element, kAXPressAction as CFString)
        guard error == .success else {
            return .init(success: false, message: "元素 \(index) 不支持按下操作（AXError \(error.rawValue)）。")
        }
        return .init(success: true, message: "已按下元素 \(index)。请重新调用 get_app_state 或 screenshot 核对结果。")
    }

    /// Invoke a non-default Accessibility action exposed by an element. The
    /// action must be present in the latest AX state; guessed action names are
    /// rejected. Both raw AX names (`AXShowMenu`) and localized descriptions
    /// (`Show Menu`) are accepted.
    public static func performSecondaryAction(
        appName: String?,
        index: Int,
        action: String
    ) -> ElementActionResult {
        guard index >= 0 else {
            return .init(success: false, message: "element_index 必须是非负整数。")
        }
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else {
            return .init(success: false, message: "未找到目标应用。请先调用 list_apps。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(120_000)
        let nodes = validatedNodes(for: app)
        guard nodes.indices.contains(index) else {
            return .init(success: false, message: "元素索引 \(index) 已失效或不存在；请重新调用 get_app_state。")
        }
        var names: CFArray?
        guard AXUIElementCopyActionNames(nodes[index].element, &names) == .success,
              let supported = names as? [String], !supported.isEmpty else {
            return .init(success: false, message: "元素 \(index) 没有可用的次级 AX 动作。")
        }
        let requested = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = supported.first { raw in
            if raw.caseInsensitiveCompare(requested) == .orderedSame { return true }
            if String(raw.dropFirst(raw.hasPrefix("AX") ? 2 : 0))
                .caseInsensitiveCompare(requested.replacingOccurrences(of: " ", with: "")) == .orderedSame {
                return true
            }
            var localized: CFString?
            guard AXUIElementCopyActionDescription(
                nodes[index].element,
                raw as CFString,
                &localized
            ) == .success, let localized else { return false }
            return (localized as String).caseInsensitiveCompare(requested) == .orderedSame
        }
        guard let matched else {
            return .init(
                success: false,
                message: "元素 \(index) 不支持动作 \(requested)。可用动作: \(supported.joined(separator: ", "))。"
            )
        }
        let error = AXUIElementPerformAction(nodes[index].element, matched as CFString)
        guard error == .success else {
            return .init(success: false, message: "执行 \(matched) 失败（AXError \(error.rawValue)）。")
        }
        return .init(success: true, message: "已对元素 \(index) 执行 \(matched)。请重新调用 get_app_state 核对。")
    }

    /// Directly set an editable Accessibility element's value. This is much
    /// more reliable than coordinate-click + blind typing for Electron forms.
    public static func setElementValue(
        appName: String?,
        index: Int,
        value: String
    ) -> ElementActionResult {
        guard index >= 0 else {
            return .init(success: false, message: "element_index 必须是非负整数。")
        }
        guard let app = resolveApplication(named: appName) else {
            return .init(success: false, message: "未找到目标应用。请先调用 list_applications。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(120_000)
        let nodes = validatedNodes(for: app)
        guard nodes.indices.contains(index) else {
            return .init(success: false, message: "元素索引 \(index) 已失效或不存在；请重新调用 get_app_state。")
        }
        let element = nodes[index].element
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else {
            return .init(success: false, message: "元素 \(index) 不支持设置值；请重新读取并选择可编辑文本框。")
        }
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let error = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
        guard error == .success else {
            return .init(success: false, message: "设置元素 \(index) 失败（AXError \(error.rawValue)）。")
        }
        return .init(
            success: true,
            message: "已设置元素 \(index) 的内容（\(value.count) 个字符，内容不回显）。请重新调用 get_app_state 核对。"
        )
    }

    /// Select matching text or place the insertion cursor before/after it in a
    /// text element. Prefix/suffix context disambiguates repeated occurrences.
    public static func selectText(
        appName: String?,
        index: Int,
        text: String,
        prefix: String?,
        suffix: String?,
        selectionType: String
    ) -> ElementActionResult {
        guard index >= 0 else {
            return .init(success: false, message: "element_index 必须是非负整数。")
        }
        guard !text.isEmpty else {
            return .init(success: false, message: "text 不能为空。")
        }
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else {
            return .init(success: false, message: "未找到目标应用。请先调用 list_apps。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(120_000)
        let nodes = validatedNodes(for: app)
        guard nodes.indices.contains(index) else {
            return .init(success: false, message: "元素索引 \(index) 已失效或不存在；请重新调用 get_app_state。")
        }
        let element = nodes[index].element
        guard !isSecureTextElement(element),
              let value = attribute(element, kAXValueAttribute) as? String else {
            return .init(success: false, message: "元素 \(index) 不是可选择文本的普通文本控件。")
        }

        let source = value as NSString
        var search = NSRange(location: 0, length: source.length)
        var match: NSRange?
        while search.location <= source.length {
            let found = source.range(of: text, options: [], range: search)
            guard found.location != NSNotFound else { break }
            let prefixOK: Bool
            if let prefix, !prefix.isEmpty {
                let start = found.location - (prefix as NSString).length
                prefixOK = start >= 0
                    && source.substring(with: NSRange(location: start, length: (prefix as NSString).length)) == prefix
            } else { prefixOK = true }
            let suffixOK: Bool
            if let suffix, !suffix.isEmpty {
                let start = found.location + found.length
                suffixOK = start + (suffix as NSString).length <= source.length
                    && source.substring(with: NSRange(location: start, length: (suffix as NSString).length)) == suffix
            } else { suffixOK = true }
            if prefixOK && suffixOK {
                match = found
                break
            }
            let next = found.location + max(1, found.length)
            guard next <= source.length else { break }
            search = NSRange(location: next, length: source.length - next)
        }
        guard var selected = match else {
            return .init(success: false, message: "元素 \(index) 中找不到带指定上下文的目标文本。")
        }
        switch selectionType {
        case "cursor_before": selected.length = 0
        case "cursor_after": selected.location += selected.length; selected.length = 0
        default: break
        }
        var range = CFRange(location: selected.location, length: selected.length)
        guard let axRange = AXValueCreate(.cfRange, &range) else {
            return .init(success: false, message: "无法创建文本选择范围。")
        }
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let error = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        guard error == .success else {
            return .init(success: false, message: "选择文本失败（AXError \(error.rawValue)）。")
        }
        return .init(success: true, message: "已在元素 \(index) 完成 \(selectionType) 文本选择。")
    }

    public private(set) static var observationToken: String?
    private static var observedNodes: [pid_t: [AccessibilityNode]] = [:]

    /// Bind actions to exactly the objects just verified by the one-shot worker.
    /// A new enumeration must never silently reinterpret a previous index.
    private static func validatedNodes(for app: NSRunningApplication) -> [AccessibilityNode] {
        guard let observed = observedNodes[app.processIdentifier] else { return [] }
        let current = accessibilityNodes(for: app, maxElements: 600)
        guard current.count == observed.count,
              zip(current, observed).allSatisfy({ CFEqual($0.element, $1.element) }) else { return [] }
        return observed
    }

    private struct AccessibilityNode {
        let element: AXUIElement
        let depth: Int
    }

    private static func resolveApplication(
        named name: String?,
        launchIfNeeded: Bool = false
    ) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        guard let needle = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !needle.isEmpty else {
            return NSWorkspace.shared.frontmostApplication
        }
        let lowered = needle.lowercased()
        if let exact = apps.first(where: {
            $0.bundleURL?.standardizedFileURL.path.lowercased() == lowered
                || $0.bundleIdentifier?.lowercased() == lowered
                || $0.localizedName?.lowercased() == lowered
        }) { return exact }
        let partials = apps.filter {
            $0.bundleIdentifier?.lowercased().contains(lowered) == true
                || $0.localizedName?.lowercased().contains(lowered) == true
        }
        if partials.count == 1 { return partials[0] }
        if partials.count > 1 { return nil }
        guard launchIfNeeded, openApplication(named: needle) else { return nil }
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let launched = resolveApplication(named: needle, launchIfNeeded: false) {
                return launched
            }
            usleep(50_000)
        } while Date() < deadline
        return nil
    }

    private static func accessibilityNodes(
        for app: NSRunningApplication,
        maxElements: Int
    ) -> [AccessibilityNode] {
        guard accessibilityAllowed, maxElements > 0 else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var result: [AccessibilityNode] = []

        func walk(_ element: AXUIElement, depth: Int) {
            guard result.count < maxElements, depth <= 32 else { return }
            result.append(.init(element: element, depth: depth))
            // Closed menu trees can contain hundreds of irrelevant items and
            // used to exhaust the scan before Electron web controls appeared.
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == kAXMenuBarRole || role == kAXMenuRole { return }
            guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
            for child in children {
                walk(child, depth: depth + 1)
                if result.count >= maxElements { break }
            }
        }

        walk(root, depth: 0)
        return result
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func accessibilityLine(for element: AXUIElement, depth: Int) -> String {
        let role = attribute(element, kAXRoleAttribute) as? String ?? "AXUnknown"
        var details: [String] = []
        if let title = attribute(element, kAXTitleAttribute) as? String, !title.isEmpty {
            details.append("title=\"\(compact(title))\"")
        }
        if let description = attribute(element, kAXDescriptionAttribute) as? String,
           !description.isEmpty {
            details.append("description=\"\(compact(description))\"")
        }
        let secureText = isSecureTextElement(element)
        if !secureText,
           let value = attribute(element, kAXValueAttribute),
           let rendered = renderAccessibilityValue(value), !rendered.isEmpty {
            details.append("value=\"\(compact(rendered))\"")
        } else if secureText {
            details.append("value=\"[已隐藏]\"")
        }
        if let placeholder = attribute(element, kAXPlaceholderValueAttribute) as? String,
           !placeholder.isEmpty {
            details.append("placeholder=\"\(compact(placeholder))\"")
        }
        if let identifier = attribute(element, kAXIdentifierAttribute) as? String,
           !identifier.isEmpty {
            details.append("id=\"\(compact(identifier))\"")
        }
        if (attribute(element, kAXSelectedAttribute) as? NSNumber)?.boolValue == true {
            details.append("selected=true")
        }
        if (attribute(element, kAXFocusedAttribute) as? NSNumber)?.boolValue == true {
            details.append("focused=true")
        }
        if (attribute(element, kAXEnabledAttribute) as? NSNumber)?.boolValue == false {
            details.append("enabled=false")
        }
        var valueSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &valueSettable
        ) == .success, valueSettable.boolValue, !secureText {
            details.append("settable=true")
        }
        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success,
           let names = actionNames as? [String], !names.isEmpty {
            details.append("actions=[\(names.map(compact).joined(separator: ","))]")
        }
        let indent = String(repeating: "  ", count: min(depth, 12))
        return indent + role + (details.isEmpty ? "" : " " + details.joined(separator: " "))
    }

    private static func renderAccessibilityValue(_ value: AnyObject) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func isSecureTextElement(_ element: AXUIElement) -> Bool {
        let role = attribute(element, kAXRoleAttribute) as? String
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    private static func compact(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return String(singleLine.prefix(180))
    }

    // MARK: - Mouse / keyboard

    /// 在主屏或指定应用窗口的归一化坐标处单击 / 双击。CoreGraphics
    /// 全局鼠标坐标与窗口列表均为左上原点，不再做错误的 Y 轴翻转。
    @discardableResult
    public static func click(
        nx: Double,
        ny: Double,
        doubleClick: Bool,
        appName: String? = nil
    ) -> ElementActionResult {
        let pt: CGPoint
        if let appName {
            guard let app = resolveApplication(named: appName) else {
                return .init(success: false, message: "未找到目标应用 \(appName)。")
            }
            app.activate(options: [.activateAllWindows])
            usleep(120_000)
            guard let window = primaryWindowInfo(for: app) else {
                return .init(success: false, message: "未找到 \(appName) 的可见主窗口。")
            }
            pt = CGPoint(
                x: window.bounds.minX + CGFloat(nx) * window.bounds.width,
                y: window.bounds.minY + CGFloat(ny) * window.bounds.height
            )
        } else {
            let bounds = CGDisplayBounds(CGMainDisplayID())
            pt = CGPoint(
                x: bounds.minX + CGFloat(nx) * bounds.width,
                y: bounds.minY + CGFloat(ny) * bounds.height
            )
        }
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
        let scope = appName.map { "应用 \($0) 窗口" } ?? "主屏"
        return .init(success: true, message: "已在\(scope)相对坐标 (\(nx), \(ny)) 完成点击。")
    }

    /// Codex-compatible click: use a semantic AX element when supplied;
    /// otherwise use point coordinates relative to the target app window.
    @discardableResult
    public static func click(
        appName: String,
        elementIndex: Int?,
        x: Double?,
        y: Double?,
        mouseButton: String,
        clickCount: Int
    ) -> ElementActionResult {
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else {
            return .init(success: false, message: "未找到目标应用 \(appName)。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(120_000)
        if let elementIndex, x == nil, y == nil, ["left", "l"].contains(mouseButton), clickCount == 1 {
            return pressElement(appName: appName, index: elementIndex)
        }
        guard let point = targetPoint(
            for: app,
            elementIndex: elementIndex,
            x: x,
            y: y
        ) else {
            return .init(
                success: false,
                message: "需要有效的 element_index，或同时提供目标应用窗口内的 x/y 点坐标。"
            )
        }
        guard let button = cgMouseButton(mouseButton) else {
            return .init(success: false, message: "mouse_button 必须是 left/right/middle（或 l/r/m）。")
        }
        postMouseClick(at: point, button: button, count: max(1, min(3, clickCount)))
        return .init(
            success: true,
            message: "已在应用 \(appName) 执行 \(mouseButton) 键 \(max(1, min(3, clickCount))) 次点击。"
        )
    }

    @discardableResult
    public static func drag(
        appName: String,
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double
    ) -> ElementActionResult {
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else {
            return .init(success: false, message: "未找到目标应用 \(appName)。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(120_000)
        guard let window = primaryWindowInfo(for: app) else {
            return .init(success: false, message: "未找到 \(appName) 的可见主窗口。")
        }
        let start = CGPoint(x: window.bounds.minX + CGFloat(fromX),
                            y: window.bounds.minY + CGFloat(fromY))
        let end = CGPoint(x: window.bounds.minX + CGFloat(toX),
                          y: window.bounds.minY + CGFloat(toY))
        guard window.bounds.contains(start), window.bounds.contains(end) else {
            return .init(success: false, message: "拖拽坐标必须位于目标应用窗口内。")
        }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(20_000)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
        for step in 1...12 {
            let fraction = CGFloat(step) / 12
            let point = CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                    mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
        return .init(success: true, message: "已在应用 \(appName) 完成拖拽。")
    }

    @discardableResult
    public static func scroll(
        appName: String,
        elementIndex: Int?,
        x: Double?,
        y: Double?,
        direction: String,
        pages: Int
    ) -> ElementActionResult {
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else {
            return .init(success: false, message: "未找到目标应用 \(appName)。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(120_000)
        let hasTarget = elementIndex != nil || x != nil || y != nil
        let point = targetPoint(for: app, elementIndex: elementIndex, x: x, y: y)
        let fallback = hasTarget ? nil : primaryWindowInfo(for: app).map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
        guard let point = point ?? fallback else {
            return .init(success: false, message: "无法确定目标应用的滚动位置。")
        }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        let amount = Int32(max(1, min(10, pages)) * 8)
        let vertical: Int32
        let horizontal: Int32
        switch direction {
        case "up", "u": vertical = amount; horizontal = 0
        case "down", "d": vertical = -amount; horizontal = 0
        case "left", "l": vertical = 0; horizontal = amount
        case "right", "r": vertical = 0; horizontal = -amount
        default:
            return .init(success: false, message: "direction 必须是 up/down/left/right（或 u/d/l/r）。")
        }
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
        return .init(success: true, message: "已在应用 \(appName) 向 \(direction) 滚动 \(pages) 页。")
    }

    private static func targetPoint(
        for app: NSRunningApplication,
        elementIndex: Int?,
        x: Double?,
        y: Double?
    ) -> CGPoint? {
        if let elementIndex {
            let nodes = validatedNodes(for: app)
            guard nodes.indices.contains(elementIndex),
                  let frame = elementFrame(nodes[elementIndex].element) else { return nil }
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        guard let x, let y, x >= 0, y >= 0,
              let window = primaryWindowInfo(for: app) else { return nil }
        let point = CGPoint(x: window.bounds.minX + CGFloat(x),
                            y: window.bounds.minY + CGFloat(y))
        return window.bounds.contains(point) ? point : nil
    }

    private static func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func cgMouseButton(_ name: String) -> CGMouseButton? {
        switch name {
        case "left", "l": return .left
        case "right", "r": return .right
        case "middle", "m": return .center
        default: return nil
        }
    }

    private static func postMouseClick(at point: CGPoint, button: CGMouseButton, count: Int) {
        let downType: CGEventType
        let upType: CGEventType
        switch button {
        case .right: downType = .rightMouseDown; upType = .rightMouseUp
        case .center: downType = .otherMouseDown; upType = .otherMouseUp
        default: downType = .leftMouseDown; upType = .leftMouseUp
        }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
        usleep(20_000)
        for state in 1...count {
            let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                               mouseCursorPosition: point, mouseButton: button)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                             mouseCursorPosition: point, mouseButton: button)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
            up?.post(tap: .cghidEventTap)
            if state < count { usleep(100_000) }
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
    public static func typeText(_ text: String, targetPID: pid_t? = nil) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        for ch in text {
            if ch == "\n" || ch == "\r" {
                postKey(CGKeyCode(36), source: src, flags: [], targetPID: targetPID)
                continue
            }
            let units = Array(String(ch).utf16)
            for keyDown in [true, false] {
                let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: keyDown)
                ev?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                postEvent(ev, targetPID: targetPID)
            }
            usleep(2_000)
        }
    }

    @discardableResult
    public static func typeText(_ text: String, appName: String) -> ElementActionResult {
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else {
            return .init(success: false, message: "未找到目标应用 \(appName)。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(80_000)
        typeText(text, targetPID: app.processIdentifier)
        return .init(success: true, message: "已向应用 \(appName) 输入 \(text.count) 个字符。")
    }

    /// Paste plain text, Markdown, or HTML while preserving every existing
    /// pasteboard item and UTI. The user's clipboard is restored after Cmd+V.
    @discardableResult
    public static func paste(appName: String, text: String, format: String) -> ElementActionResult {
        guard ["text", "md", "html"].contains(format) else {
            return .init(success: false, message: "format 必须是 text、md 或 html。")
        }
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else {
            return .init(success: false, message: "未找到目标应用 \(appName)。")
        }
        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) { result[type] = data }
            }
        } ?? []
        func restorePasteboard() {
            pasteboard.clearContents()
            let items = snapshot.map { stored -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in stored { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        switch format {
        case "md":
            item.setData(Data(text.utf8), forType: .init("net.daringfireball.markdown"))
        case "html":
            item.setData(Data(text.utf8), forType: .html)
        case "text": break
        default:
            restorePasteboard()
            return .init(success: false, message: "format 必须是 text、md 或 html。")
        }
        guard pasteboard.writeObjects([item]) else {
            restorePasteboard()
            return .init(success: false, message: "无法写入临时剪贴板。")
        }
        let temporaryChangeCount = pasteboard.changeCount
        app.activate(options: [.activateAllWindows])
        usleep(80_000)
        guard pasteboard.changeCount == temporaryChangeCount else {
            return .init(success: false, message: "剪贴板已被其他操作修改；已取消粘贴并保留新内容。")
        }
        let pasted = pressKeySyntax("super+v", targetPID: app.processIdentifier)
        usleep(180_000)
        let unchanged = pasteboard.changeCount == temporaryChangeCount
        if unchanged { restorePasteboard() }
        let clipboardStatus = unchanged ? "已恢复原剪贴板" : "已保留用户新复制的内容"
        return .init(
            success: pasted,
            message: pasted
                ? "已发送粘贴快捷键，\(clipboardStatus)。请读取目标控件核对内容。"
                : "粘贴快捷键发送失败，\(clipboardStatus)。"
        )
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

    /// xdotool-style key syntax used by Codex Computer Use, including examples
    /// such as `Return`, `super+c`, `Up`, and `KP_0`.
    @discardableResult
    public static func pressKeySyntax(_ syntax: String, targetPID: pid_t? = nil) -> Bool {
        let parts = syntax.split(separator: "+").map(String.init)
        guard let keyName = parts.last, !keyName.isEmpty else { return false }
        var flags: CGEventFlags = []
        for raw in parts.dropLast().map({ $0.lowercased() }) {
            switch raw {
            case "super", "command", "cmd": flags.insert(.maskCommand)
            case "control", "ctrl": flags.insert(.maskControl)
            case "option", "alt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: return false
            }
        }
        guard let mapping = keyCode(for: keyName) else {
            guard targetPID == nil else { return false }
            return pressKey(name: keyName, modifiers: Array(parts.dropLast()))
        }
        if mapping.requiresShift { flags.insert(.maskShift) }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        postKey(mapping.code, source: source, flags: flags, targetPID: targetPID)
        return true
    }

    @discardableResult
    public static func pressKeySyntax(_ syntax: String, appName: String) -> ElementActionResult {
        guard let app = resolveApplication(named: appName, launchIfNeeded: true) else {
            return .init(success: false, message: "未找到目标应用 \(appName)。")
        }
        app.activate(options: [.activateAllWindows])
        usleep(80_000)
        guard pressKeySyntax(syntax, targetPID: app.processIdentifier) else {
            return .init(success: false, message: "无法解析或定向发送按键 \(syntax)。")
        }
        return .init(success: true, message: "已向应用 \(appName) 发送按键 \(syntax)。")
    }

    private static func keyCode(for rawName: String) -> (code: CGKeyCode, requiresShift: Bool)? {
        let lower = rawName.lowercased()
        let named: [String: CGKeyCode] = [
            "return": 36, "enter": 36, "tab": 48, "space": 49,
            "backspace": 51, "delete": 117, "escape": 53, "esc": 53,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "home": 115, "end": 119, "page_up": 116, "pageup": 116,
            "page_down": 121, "pagedown": 121,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
            "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
            "f11": 103, "f12": 111,
            "kp_0": 82, "kp_1": 83, "kp_2": 84, "kp_3": 85,
            "kp_4": 86, "kp_5": 87, "kp_6": 88, "kp_7": 89,
            "kp_8": 91, "kp_9": 92, "kp_enter": 76,
            "kp_add": 69, "kp_subtract": 78, "kp_multiply": 67,
            "kp_divide": 75, "kp_decimal": 65,
        ]
        if let code = named[lower] { return (code, false) }
        let keys: [Character: (CGKeyCode, Bool)] = [
            "a": (0, false), "s": (1, false), "d": (2, false), "f": (3, false),
            "h": (4, false), "g": (5, false), "z": (6, false), "x": (7, false),
            "c": (8, false), "v": (9, false), "b": (11, false), "q": (12, false),
            "w": (13, false), "e": (14, false), "r": (15, false), "y": (16, false),
            "t": (17, false), "1": (18, false), "2": (19, false), "3": (20, false),
            "4": (21, false), "6": (22, false), "5": (23, false), "=": (24, false),
            "9": (25, false), "7": (26, false), "-": (27, false), "8": (28, false),
            "0": (29, false), "]": (30, false), "o": (31, false), "u": (32, false),
            "[": (33, false), "i": (34, false), "p": (35, false), "l": (37, false),
            "j": (38, false), "'": (39, false), "k": (40, false), ";": (41, false),
            "\\": (42, false), ",": (43, false), "/": (44, false), "n": (45, false),
            "m": (46, false), ".": (47, false), "`": (50, false),
            "!": (18, true), "@": (19, true), "#": (20, true), "$": (21, true),
            "^": (22, true), "%": (23, true), "+": (24, true), "(": (25, true),
            "&": (26, true), "_": (27, true), "*": (28, true), ")": (29, true),
            "}": (30, true), "{": (33, true), "\"": (39, true), ":": (41, true),
            "|": (42, true), "<": (43, true), "?": (44, true), ">": (47, true),
            "~": (50, true),
        ]
        guard rawName.count == 1, let character = rawName.first else { return nil }
        if character.isUppercase, let base = character.lowercased().first,
           let mapping = keys[base] { return (mapping.0, true) }
        return keys[character]
    }

    private static func postKey(
        _ code: CGKeyCode,
        source: CGEventSource?,
        flags: CGEventFlags,
        targetPID: pid_t? = nil
    ) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        postEvent(down, targetPID: targetPID)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        postEvent(up, targetPID: targetPID)
    }

    private static func postEvent(_ event: CGEvent?, targetPID: pid_t?) {
        guard let event else { return }
        if let targetPID {
            event.postToPid(targetPID)
        } else {
            event.post(tap: .cghidEventTap)
        }
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

    /// 按名字启动一个 macOS 应用。先走 `open -a`（英文 bundle 名、路径
    /// 与 bundle id），失败后用 Spotlight 的本地化显示名索引兜底，例如
    /// 中文系统里的“计算器”可解析到 `Calculator.app`。
    @discardableResult
    public static func openApplication(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if FileManager.default.fileExists(atPath: trimmed),
           URL(fileURLWithPath: trimmed).pathExtension.lowercased() == "app",
           runOpen(arguments: [trimmed]) {
            return true
        }

        if runOpen(arguments: ["-a", trimmed]) {
            return true
        }
        if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed),
           runOpen(arguments: [bundleURL.path]) {
            return true
        }
        guard let localizedURL = localizedApplicationURL(named: trimmed) else {
            return false
        }
        return runOpen(arguments: [localizedURL.path])
    }

    private static func runOpen(arguments: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func localizedApplicationURL(named name: String) -> URL? {
        let displayName = name.lowercased().hasSuffix(".app")
            ? String(name.dropLast(4))
            : name
        let escapedName = displayName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let query = "kMDItemContentType == 'com.apple.application-bundle' && "
            + "kMDItemDisplayName == '\(escapedName).app'cd"

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return text.split(whereSeparator: \.isNewline)
                .map(String.init)
                .map(URL.init(fileURLWithPath:))
                .first(where: {
                    $0.pathExtension.lowercased() == "app"
                        && FileManager.default.fileExists(atPath: $0.path)
                })
        } catch {
            return nil
        }
    }
}
