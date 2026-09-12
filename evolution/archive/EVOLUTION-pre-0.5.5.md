# Evolution Archive — pre-v0.5.5

> v0.5.4 及更早的 Mac 历史，于 v0.5.270 从主 `EVOLUTION.md` 分离。
> 主日志只保留 v0.5.5 之后；本文件不参与 tag / Info.plist / makeHistory 校验。

## v0.3.0 — feat: 目标卡(进行中+实时耗时+清除) + 输入框目标模式
**Date**: 2026-08-（补）
**Tag**: v0.3.0
**Test status**: 历史
**Why**: 补齐 v0.5.5 之前历史版本段，便于 MakeHistory parity 双向测试通过。
**Note**: 本条目是 2026-09-08 自动回填的占位记录，commit message 来自 `git log` 检索。

## v0.3.2 — fix: evolve.sh skips SSH-integration tests by default; README test count 110→332
**Date**: 2026-08-（补）
**Tag**: v0.3.2
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.3.3 — fix: 粘贴/添加的图片附件行与输入框左对齐——约束到 contentWidth 并居中
**Date**: 2026-08-（补）
**Tag**: v0.3.3
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.4.0 — feat: upgrade harness protocol and context recovery
**Date**: 2026-08-（补）
**Tag**: v0.4.0
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.4.1 — feat: harness process supervision, JSON-RPC id safety, approval timeout
**Date**: 2026-08-（补）
**Tag**: v0.4.1
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.4.3 — feat: per-conversation runner + harness failure recovery
**Date**: 2026-08-（补）
**Tag**: v0.4.3
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.0 — feat: structured diff view with per-line review comments
**Date**: 2026-08-（补）
**Tag**: v0.5.0
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.1 — fix: restore coding-agent role and durable memory hygiene
**Date**: 2026-08-（补）
**Tag**: v0.5.1
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.4 — fix: persist sent images and stream live progress
**Date**: 2026-08-（补）
**Tag**: v0.5.4
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.3 — 修复截图粘贴被吞掉但未生成附件
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.3`)_
**Tag**: v0.5.3
**Test status**: — 706 passed, 0 failed —
**Changed**:
- ⌘V 监听改用 AppKit 可读对象检测，覆盖图片对象与图片文件 URL。
- 剪贴板没有 PNG 表示时，通过 `NSImage` 解码 TIFF/JPEG/HEIC 等表示并统一转成临时 PNG 附件。
**Why**: 旧代码识别到通用图片后会吞掉 ⌘V，但真正读取时只取 `.png`；macOS 截图常提供 TIFF，导致输入框看起来完全没有反应。
**Next**: 已用 Preview 复制真实截图并在安装版 App 验证缩略图与临时 PNG；继续覆盖更多第三方图片来源。

## v0.5.2 — 强制小步增量输出与异常即时反馈
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.2`)_
**Tag**: v0.5.2
**Test status**: — 706 passed, 0 failed —
**Changed**:
- 新增 `AgentOutputPolicy`，把“小步增量”定义为可测试的强制契约：每完成一个有意义步骤立即输出 1–3 行结果和下一步，不把已完成步骤攒到最终回复。
- 失败、异常或阻塞必须在发现后的下一条消息立即说明影响和处理方向；最终回复只收口结果、验证证据和剩余风险。
- 完整契约注入 `thread/start` / `thread/resume`，短提醒同时放在每个当前用户任务之前，避免长对话或旧上下文稀释规则。
- App 在命令、MCP 工具、文件变更完成时即时插入两行进度；失败事件立即插入异常、影响与处理方向，且这些运行态提示不会被长期记忆提取。
- 模型目录关闭并行工具批处理；`ensureReady()` 会比较并刷新 App 专属模型目录，现有安装不再永久沿用旧 `base_instructions`。
- 新增 21 项 `AgentOutputPolicy` 回归测试；总测试数 685 → 706。
**Why**: v0.5.1 只包含一句宽泛提示；仅加强 Prompt 的首次原生回归中，模型仍把三个工具并行执行后集中总结，因此增加 App 事件层保证。
**Next**: 继续用安装版长任务验证模型在多次工具调用之间真实产生用户可见进度，并跟进 Harness 的原生进度事件能力。
