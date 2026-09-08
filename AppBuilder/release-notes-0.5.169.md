# Tapgo AICoding 0.5.169

## Sidebar thread item 右键菜单加"在 Finder 中显示附件"

之前 sidebar thread item 右键菜单只有"打开项目目录"（仅本地 project）和"复制/置顶/删除"等。user 想知道 thread 的图片附件存哪了，但找不到入口。加"在 Finder 中显示附件"——打开 `~/Library/Application Support/Tapgo AICoding/codex/attachments/<threadId>/` 目录。

- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - `contextMenu(for: Thread)` 加"在 Finder 中显示附件" Button（paperclip icon）。
  - 加 `openThreadAttachmentsDir(_:)` helper：目录存在时 NSWorkspace.open；不存在时弹 NSAlert 提示"该会话尚未保存任何图片附件"（不静默失败）。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
