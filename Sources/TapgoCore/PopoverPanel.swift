import SwiftUI
import AppKit

/// v0.5.199: 用 NSPopover with transient behavior + 手动 contentSize 控制 panel 宽度。
/// SwiftUI Menu 在 macOS 26.5 SDK 渲染成小弹窗（~130pt 宽），
/// .menuStyle(.borderlessButton) 不再让它变成 push-out 卡片。
/// NSPopover 通过 NSHostingController + contentSize 控制显示尺寸。
public struct PopoverPanel<PopoverContent: View>: NSViewControllerRepresentable {
    @Binding var isPresented: Bool
    let contentSize: NSSize
    let popoverContent: () -> PopoverContent

    public init(
        isPresented: Binding<Bool>,
        contentSize: NSSize,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) {
        self._isPresented = isPresented
        self.contentSize = contentSize
        self.popoverContent = content
    }

    public func makeNSViewController(context: Context) -> NSViewController {
        let host = PopoverHostViewController()
        return host
    }

    public func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        guard let host = nsViewController as? PopoverHostViewController else { return }
        host.update(isPresented: isPresented, contentSize: contentSize, content: popoverContent)
    }
}

/// v0.5.199: NSViewController 宿主 — 持有 NSPopover 引用，根据 isPresented 显示/隐藏。
final class PopoverHostViewController: NSViewController {
    private var popover: NSPopover?

    func update<PopoverContent: View>(
        isPresented: Bool,
        contentSize: NSSize,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) {
        if isPresented {
            show(contentSize: contentSize, content: content)
        } else {
            dismiss()
        }
    }

    private func show<PopoverContent: View>(contentSize: NSSize, content: () -> PopoverContent) {
        // 已经显示 — 检查尺寸或内容变化
        if let existing = popover {
            existing.contentSize = contentSize
            existing.contentViewController?.view.frame = NSRect(origin: .zero, size: contentSize)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let hostController = NSHostingController(rootView: content())
        hostController.view.frame = NSRect(origin: .zero, size: contentSize)
        // NSPopover 强引用 contentViewController
        popover.contentViewController = hostController
        popover.contentSize = contentSize

        // 显示：从宿主 view 的 frame 上方弹出，宽度 = contentSize.width
        let view = self.view
        guard let window = view.window, let contentView = window.contentView else { return }
        let rect = view.convert(view.bounds, to: contentView)
        popover.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        self.popover = popover
    }

    private func dismiss() {
        popover?.performClose(nil)
        popover = nil
    }

    deinit {
        dismiss()
    }
}
