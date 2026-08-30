import AppKit
import Foundation
import SwiftUI

enum ComputerUsePermissionKind: String, Sendable {
    case accessibility
    case screenRecording = "screen_recording"

    var title: String {
        switch self {
        case .accessibility: return "辅助功能"
        case .screenRecording: return "屏幕录制"
        }
    }

    var settingsButtonTitle: String {
        switch self {
        case .accessibility: return "打开辅助功能设置"
        case .screenRecording: return "打开屏幕录制设置"
        }
    }

    var settingsURL: URL? {
        let suffix: String
        switch self {
        case .accessibility: suffix = "Privacy_Accessibility"
        case .screenRecording: suffix = "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(suffix)")
    }
}

struct ComputerUsePermissionState: Equatable, Sendable {
    var accessibility: Bool?
    var screenRecording: Bool?
    var helperBundleIdentifier: String?
    var error: String?

    static let loading = ComputerUsePermissionState(
        accessibility: nil,
        screenRecording: nil,
        helperBundleIdentifier: nil,
        error: nil
    )
}

enum ComputerUsePermissionProbe {
    private struct Payload: Decodable {
        let accessibility: Bool
        let screen_recording: Bool
        let bundle_identifier: String
    }

    static func read(helperAppURL: URL?) async -> ComputerUsePermissionState {
        await Task.detached(priority: .utility) {
            readSynchronously(helperAppURL: helperAppURL)
        }.value
    }

    private static func readSynchronously(helperAppURL: URL?) -> ComputerUsePermissionState {
        guard let helperAppURL else {
            return ComputerUsePermissionState(
                accessibility: nil,
                screenRecording: nil,
                helperBundleIdentifier: nil,
                error: "未找到随 App 分发的 Tapgo Computer Use Helper。"
            )
        }

        let statusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapgo-computer-use-permission-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: statusURL) }

        let errors = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n", "-g", helperAppURL.path,
            "--args", "--permission-status-file", statusURL.path,
        ]
        process.standardError = errors

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ComputerUsePermissionState(
                accessibility: nil,
                screenRecording: nil,
                helperBundleIdentifier: nil,
                error: "无法启动权限检测：\(error.localizedDescription)"
            )
        }

        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ComputerUsePermissionState(
                accessibility: nil,
                screenRecording: nil,
                helperBundleIdentifier: nil,
                error: detail?.isEmpty == false ? detail : "权限检测没有返回有效结果。"
            )
        }

        let deadline = Date().addingTimeInterval(4)
        var data: Data?
        while Date() < deadline {
            if let value = try? Data(contentsOf: statusURL), !value.isEmpty {
                data = value
                break
            }
            Thread.sleep(forTimeInterval: 0.08)
        }
        guard let data,
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return ComputerUsePermissionState(
                accessibility: nil,
                screenRecording: nil,
                helperBundleIdentifier: nil,
                error: "Tapgo Computer Use Helper 未返回权限状态。"
            )
        }

        return ComputerUsePermissionState(
            accessibility: payload.accessibility,
            screenRecording: payload.screen_recording,
            helperBundleIdentifier: payload.bundle_identifier,
            error: nil
        )
    }
}

/// A small floating panel that remains visible above System Settings. The user
/// drags the actual helper app into the selected privacy list; the panel never
/// edits TCC records or simulates consent on the user's behalf.
@MainActor
final class ComputerUsePermissionGuideController: NSObject, NSWindowDelegate {
    static let shared = ComputerUsePermissionGuideController()

    private var panel: NSPanel?
    private var completion: (() -> Void)?

    func present(
        permission: ComputerUsePermissionKind,
        helperAppURL: URL,
        completion: @escaping () -> Void
    ) {
        dismiss()
        self.completion = completion

        let icon = NSWorkspace.shared.icon(forFile: helperAppURL.path)
        icon.size = NSSize(width: 40, height: 40)
        let view = ComputerUsePermissionGuideView(
            permission: permission,
            helperAppURL: helperAppURL,
            helperIcon: icon,
            dismiss: { [weak self] in self?.dismiss() }
        )

        let size = NSSize(width: 590, height: 142)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // The panel itself must stay anchored above System Settings. If
        // background movement is enabled, AppKit consumes the pointer drag
        // before SwiftUI's `.onDrag` can export the helper `.app`, so the
        // entire guide window follows the cursor instead of the app tile.
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        position(panel: panel, size: size)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func dismiss() {
        guard let panel else { return }
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        let completion = completion
        self.completion = nil
        completion?()
    }

    private func position(panel: NSPanel, size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 34
        ))
    }
}

private struct ComputerUsePermissionGuideView: View {
    let permission: ComputerUsePermissionKind
    let helperAppURL: URL
    let helperIcon: NSImage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                HStack(spacing: 9) {
                    Image(nsImage: helperIcon)
                        .resizable()
                        .frame(width: 34, height: 34)
                    Text("Tapgo Computer Use")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .overlay {
                    HelperAppNativeDragSource(
                        helperAppURL: helperAppURL,
                        helperIcon: helperIcon
                    )
                }
                .help("拖动到系统设置的\(permission.title)允许列表")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("拖动左侧 App 到上方的“\(permission.title)”列表")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                Text("松手即可加入允许列表；如系统要求，请确认并打开对应开关。完成后返回 Tapgo AICoding 重新检测。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            .help("关闭授权引导")
        }
        .padding(.horizontal, 20)
        .frame(width: 590, height: 142)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
    }
}

/// System Settings' privacy lists accept the same native local-file drag
/// session as Finder/Electron `startDrag(file:)`. SwiftUI's `NSItemProvider`
/// path advertises similar UTTypes but does not create that AppKit file drag,
/// so the drop can animate without adding the application to the list.
private struct HelperAppNativeDragSource: NSViewRepresentable {
    let helperAppURL: URL
    let helperIcon: NSImage

    func makeNSView(context: Context) -> HelperAppNativeDragSourceView {
        HelperAppNativeDragSourceView(
            helperAppURL: helperAppURL,
            helperIcon: helperIcon
        )
    }

    func updateNSView(_ nsView: HelperAppNativeDragSourceView, context: Context) {
        nsView.helperAppURL = helperAppURL
        nsView.helperIcon = helperIcon
    }
}

private final class HelperAppNativeDragSourceView: NSView, NSDraggingSource {
    var helperAppURL: URL
    var helperIcon: NSImage
    private var hasStartedDrag = false

    init(helperAppURL: URL, helperIcon: NSImage) {
        self.helperAppURL = helperAppURL
        self.helperIcon = helperIcon
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasStartedDrag,
              FileManager.default.fileExists(atPath: helperAppURL.path) else { return }
        hasStartedDrag = true

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            helperAppURL.absoluteString,
            forType: .fileURL
        )
        pasteboardItem.setPropertyList(
            [helperAppURL.path],
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        )

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let imageSize = NSSize(width: 48, height: 48)
        let point = convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            NSRect(
                x: point.x - imageSize.width / 2,
                y: point.y - imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            ),
            contents: helperIcon
        )
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}
