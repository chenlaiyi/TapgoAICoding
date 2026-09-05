import AppKit

/// A visible agent pointer, independent of the user's hardware pointer. Enabled
/// only in the Launch Services action worker, never in the host UI or stdio bridge.
public enum AgentCursor {
    private static var enabled = false
    private static var panel: NSPanel?
    private static var glyph: AgentCursorView?

    public static func enable() {
        guard Thread.isMainThread else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        enabled = true
    }

    public static func show(at point: CGPoint, action: String) {
        guard enabled, Thread.isMainThread else { return }
        if panel == nil {
            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            window.title = "Tapgo 操作光标"
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = AgentCursorView(frame: NSRect(x: 0, y: 0, width: 92, height: 92))
            window.contentView = view
            glyph = view
            panel = window
        }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        // Arrow tip is (39, 36); transparent padding keeps the soft glow unclipped.
        panel?.setFrame(NSRect(x: point.x - 39, y: top - point.y - 56, width: 92, height: 92), display: false)
        glyph?.action = action
        glyph?.needsDisplay = true
        panel?.orderFrontRegardless()
        panel?.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.015))
    }

    /// Let the action indicator paint before the one-shot worker exits. No
    /// windows remain after completion, failure or process termination.
    public static func finish() {
        guard enabled, Thread.isMainThread else { return }
        if panel != nil { RunLoop.main.run(until: Date().addingTimeInterval(0.32)) }
        panel?.orderOut(nil)
        panel = nil
        glyph = nil
        enabled = false
    }

}

/// Small, rounded hollow pointer with a soft mint halo. No label covers the UI.
final class AgentCursorView: NSView {
    var action = "点击"
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let glow = NSColor(calibratedRed: 0.66, green: 0.87, blue: 0.84, alpha: 1)
        let center = NSPoint(x: 45, y: 44)
        let gradient = NSGradient(colorsAndLocations:
            (glow.withAlphaComponent(0.23), 0),
            (glow.withAlphaComponent(0.10), 0.38),
            (glow.withAlphaComponent(0), 1))!
        gradient.draw(fromCenter: center, radius: 0, toCenter: center, radius: 37, options: [])

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 39, y: 36))
        arrow.curve(to: NSPoint(x: 41.2, y: 35.5), controlPoint1: NSPoint(x: 39.5, y: 35.4), controlPoint2: NSPoint(x: 40.3, y: 35.2))
        arrow.line(to: NSPoint(x: 51.2, y: 39.2))
        arrow.curve(to: NSPoint(x: 51.6, y: 42), controlPoint1: NSPoint(x: 53.2, y: 40), controlPoint2: NSPoint(x: 53.1, y: 41.3))
        arrow.line(to: NSPoint(x: 47, y: 44.3))
        arrow.line(to: NSPoint(x: 45, y: 49.5))
        arrow.curve(to: NSPoint(x: 42.2, y: 49.6), controlPoint1: NSPoint(x: 44.3, y: 51.2), controlPoint2: NSPoint(x: 42.7, y: 51.3))
        arrow.line(to: NSPoint(x: 38.8, y: 38))
        arrow.curve(to: NSPoint(x: 39, y: 36), controlPoint1: NSPoint(x: 38.4, y: 37), controlPoint2: NSPoint(x: 38.5, y: 36.5))
        arrow.close()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = glow.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor(calibratedWhite: 0.20, alpha: 0.16).setFill()
        arrow.fill()
        NSColor(calibratedRed: 0.86, green: 0.94, blue: 0.92, alpha: 0.97).setStroke()
        arrow.lineWidth = 1.45
        arrow.lineJoinStyle = .round
        arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
