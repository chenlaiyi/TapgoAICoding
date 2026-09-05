import AppKit
let pt = CGEvent(source: nil)!.location
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String:Any]] ?? []).filter { ($0[kCGWindowName as String] as? String) == "Tapgo 操作光标" }
let data = try! JSONSerialization.data(withJSONObject:["cursor":[pt.x,pt.y], "overlays":windows.map { ["bounds":$0[kCGWindowBounds as String] ?? [:],"layer":$0[kCGWindowLayer as String] ?? -1] }],options:.sortedKeys)
print(String(data:data,encoding:.utf8)!)
