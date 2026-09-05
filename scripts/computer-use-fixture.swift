// Local, disposable UI used by computer-use-smoke.py. No network or user files.
import AppKit

final class Fixture: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 640, height: 420),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let field = NSTextField(string: "initial")
    let otherField = NSTextField(string: "leave this field unchanged")
    let status = NSTextField(labelWithString: "Idle")
    var dialog: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { event in
            let record = "type=\(event.type.rawValue) window=\(event.windowNumber) local=\(event.locationInWindow) global=\(String(describing: event.cgEvent?.location))\n"
            let path = "/tmp/tapgo-cu-fixture-events.log"
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            if let file = FileHandle(forWritingAtPath: path) {
                file.seekToEndOfFile(); file.write(Data(record.utf8)); try? file.close()
            }
            return event
        }
        let menu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let paste = edit.addItem(withTitle: "Paste", action: #selector(delayedPaste), keyEquivalent: "v")
        paste.target = self
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
        window.title = "Tapgo CU Fixture"
        otherField.frame = NSRect(x: 24, y: 375, width: 580, height: 30)
        otherField.setAccessibilityIdentifier("fixture-other-input")
        window.contentView?.addSubview(otherField)
        field.frame = NSRect(x: 24, y: 330, width: 580, height: 30)
        field.setAccessibilityIdentifier("fixture-input")
        status.frame = NSRect(x: 24, y: 270, width: 580, height: 30)
        status.setAccessibilityIdentifier("fixture-status")
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(status)
        let apply = NSButton(title: "Apply fixture", target: self, action: #selector(apply))
        apply.frame = NSRect(x: 24, y: 210, width: 160, height: 32)
        window.contentView?.addSubview(apply)
        let small = NSButton(title: "Open small dialog", target: self, action: #selector(openDialog))
        small.frame = NSRect(x: 210, y: 210, width: 180, height: 32)
        window.contentView?.addSubview(small)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 20, width: 580, height: 150))
        scroll.hasVerticalScroller = true
        scroll.setAccessibilityIdentifier("fixture-scroll")
        let document = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 2400))
        document.string = (1...120).map { "Fixture row \($0)" }.joined(separator: "\n")
        scroll.documentView = document
        window.contentView?.addSubview(scroll)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(otherField)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func delayedPaste(_ sender: Any?) {
        // Deterministically reproduce apps that consume pasteboard data late.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            (self.window.firstResponder as? NSTextView)?.paste(nil)
        }
    }
    @objc func apply() { status.stringValue = "Applied: " + field.stringValue }
    @objc func openDialog() {
        let panel = NSWindow(contentRect: NSRect(x: 250, y: 250, width: 280, height: 160),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Small fixture dialog"
        let label = NSTextField(labelWithString: "Dialog is the front window")
        label.frame = NSRect(x: 15, y: 70, width: 255, height: 24)
        panel.contentView?.addSubview(label)
        panel.isReleasedWhenClosed = false
        dialog = panel
        panel.makeKeyAndOrderFront(nil)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Fixture()
app.delegate = delegate
app.run()
