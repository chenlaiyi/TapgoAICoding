# Tapgo AICoding 0.5.196

## 输入框交互对齐 Codex 桌面端：附件缩略图搬入 composer 卡片内部 + 消息记录附件加固

针对用户反馈：
1. "在处理过程中，执行命令或者思考过程或者调用其他工具，同一个就不要重复显示"（v0.5.195 部分缓解，详见上次 release）
2. "在输入框里的内部显示缩略图/文件，而不是显示到输入框外面上方"
3. "用户发送的截图或者附件在消息记录里怎么只看到文字了？请修复"

## 改动

### 1. 附件缩略图带搬入 composer 卡片内部
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - 外层 VStack 的附件条移除（之前是输入框**外侧上方**）。
  - `attachmentStrip` 移到 `ComposerView` body 内、`GrowingTextEditor` 上方，与文本编辑器同卡片容器（VStack(spacing: 10)）。
  - 保留展开/收起两种形态、移除/清空按钮、上下文菜单（复制路径 / 在访达中显示）。

### 2. 消息记录附件显示加固（修复"只看到文字"）
- `Sources/TapgoAICoding/Views/MessageRow.swift`:
  - `UserMessageThumbnail` 在 NSImage 加载失败时不再只显示一个图标，而是显示文件名 + 文件大小 + 「在 Finder 中显示」按钮，让用户能确认附件存在并一键恢复原文件。
  - 新增 `EmptyAttachmentPlaceholder` view：当用户纯发图（`displayText == "(图片)"`）但 `userImagePaths` 非空时，显示一个可点击的占位 chip「📷 图片 (1)」点击查看大图，保证即使缩略图 NSImage 加载失败用户也有交互入口。

## 测试

未跑（纯 UI 改动不影响逻辑）。
