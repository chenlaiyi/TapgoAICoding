import Foundation
import TapgoCore

func runPermissionGuideLayoutTests(_ t: TestRunner) {
    let main = CGRect(x: 0, y: 25, width: 1440, height: 850)
    let settings = CGRect(x: 400, y: 250, width: 640, height: 600)
    let frame = PermissionGuideLayout.frame(below: settings, visibleScreens: [main])!
    t.expectEqual(frame.midX, settings.midX, "guide: centered below settings")
    t.expectEqual(frame.maxY, settings.minY - 12, "guide: 12pt gap below settings")
    let moved = PermissionGuideLayout.frame(below: settings.offsetBy(dx: 70, dy: -20), visibleScreens: [main])!
    t.expectEqual(moved.origin.x - frame.origin.x, 70, "guide: follows horizontal movement")
    t.expectEqual(moved.origin.y - frame.origin.y, -20, "guide: follows vertical movement")
    let bottom = PermissionGuideLayout.frame(below: settings.offsetBy(dx: 0, dy: -230), visibleScreens: [main])!
    t.expectEqual(bottom.minY, main.minY + 12, "guide: stays above Dock when bottom space is tight")
    for x: CGFloat in [-200, 1300] {
        let edge = PermissionGuideLayout.frame(below: CGRect(x: x, y: 200, width: 640, height: 600), visibleScreens: [main])!
        t.expect(main.contains(edge), "guide: clamps horizontal screen edge")
    }
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let leftGuide = PermissionGuideLayout.frame(below: CGRect(x: -1500, y: 400, width: 700, height: 600), visibleScreens: [main, left])!
    t.expect(left.contains(leftGuide), "guide: follows settings to negative-origin display")
    let upper = CGRect(x: 0, y: 900, width: 1440, height: 900)
    let upperGuide = PermissionGuideLayout.frame(below: CGRect(x: 500, y: 1200, width: 640, height: 500), visibleScreens: [main, upper])!
    t.expect(upper.contains(upperGuide), "guide: follows settings to upper display")
    let narrow = CGRect(x: 0, y: 0, width: 500, height: 600)
    let narrowGuide = PermissionGuideLayout.frame(below: CGRect(x: 0, y: 200, width: 450, height: 350), visibleScreens: [narrow])!
    t.expectEqual(narrowGuide.width, 476, "guide: shrinks to fit narrow display")
    t.expect(PermissionGuideLayout.frame(below: settings, visibleScreens: []) == nil, "guide: no screen does not produce a fixed fallback")
    t.expect(PermissionGuideLayout.frame(below: settings.offsetBy(dx: 4000, dy: 0), visibleScreens: [main]) == nil,
             "guide: offscreen target hides guide")
}
