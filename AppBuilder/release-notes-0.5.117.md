# Tapgo AICoding 0.5.117

## 稳定性

- 根治回合结尾永远卡在"正在处理"的真因：codex app-server 长回合结束时只发 `thread/status: idle`、不发 `turn/completed`，原解析器忽略前者导致 UI 终结态只认后者；现在把 `thread/status: idle` 映射为 `turnCompleted`（幂等），并在 `SessionStore` 加终结态保护，已 completed/failed/interrupted 的回合不再被覆盖。

## 文件变更卡

- **Git 兜底文件变更卡**：当 codex 用 `mkdir` / `cat` 之类命令写文件、协议里没有 per-file `fileChange` / `turn/diff` 事件时，`WorktreeChangeTracker.collect` 升级为 per-file 明细；turn 完成时按 baseline 差集生成真正的 `FileChange`（文件名+路径+±行数+可展开 diff），`TurnPresentation` 折叠成批次卡。已有协议级 diff 的回合不重复生成。
- **HTML 内部浏览器预览**：`FileChangeRowView` 对 `html` / `htm` 新增"在内部浏览器预览"（右键菜单），用 WKWebView `loadFileURL` 弹窗并允许同目录相对资源；关闭按钮支持 Esc。
- **修复兜底变更卡的崩溃**：原 `untrackedDiff` 对已跟踪文件的修改也套用 `--- /dev/null +++ path` 的合成 diff，hunk 头声称 0 旧行但行内容与删除/修改矛盾，导致 `DiffView` split 模式对齐时 `ViewDimensions` 下标越界、窗口重布局时 EXC_BREAKPOINT。现在 `untrackedDiff` 区分来源——untracked 纯新增才合成全 + diff，tracked 修改直接走 `git diff HEAD -- path`；`FileChange.kind` 按来源标 create/update。

测试覆盖 Harness thread/status idle 终结态、WorktreeChangeTracker per-file diff / HTML 预览、Sparkle 私钥校验、Markdown 列表深度——本机 fafamacmini 3078 passed / 14 failed（其中 9 项 SSH 远程集成与 auth.json 环境性失败，2 项 AppUpdateDistributionTests 在 tag v0.5.117 后自动通过）；jkmacmini 3080 passed / 0 failed 与 v0.5.116 一致无回归。开发者签名有效；尚未完成 Apple 公证。
