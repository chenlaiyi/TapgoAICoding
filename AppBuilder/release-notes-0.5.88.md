# Tapgo AICoding 0.5.88

- 「参照目标 IDE 风格」fidelity patch 4/4：剩余最大单点色差 `sidebar_mid` 修复：
  - `SidebarView.swift` L224 视图模式切换器（Projects / Chats / Agents 按钮外层）`.background(DSHTheme.bg.opacity(0.34))` → `.background(DSHTheme.fidelitySidebarMid)`（0x39393B+bg 0.34 混合 ≈ rgb(60,60,62) → 直接 rgb(74,75,75)）
  - 关闭 `artifacts/zcode-vs-tapgo-0.5.75/fidelity-report.md` 中 `sidebar_mid` 单点 delta −15/255 的最大残差，预期中央 1000×740 像素差从 13.4% 进一步收敛。
- 用户消息 zcode 风格左缘蓝色 accent：
  - `MessageRow.swift` `MessageBubble` 用户气泡叠加 `.overlay(alignment: .leading)` 加 2pt 高 18pt `DSHTheme.trajectoryUser.opacity(0.65)` 胶囊（ZCode 用户消息的"左侧色条"语义）
  - 用 `trajectoryUser` 而非新 token，与 `trajectoryReasoning/ToolCall/ToolResult/Assistant` 5 色板一致，dark mode 0x60A5FA、light 0x2563EB
- 测试：2708 通过 / 0 失败（TAPGO_SKIP_REMOTE_INTEGRATION=1）；`DesktopDesignParityTests` 新增 2 条断言（`fidelitySidebarMid` 视图引用 + `trajectoryUser` 用户气泡引用），全量从 66/66 扩到 68/68 设计对等断言。
- 已知限制：自动 pixelmatch 验证仍未跑（需要 screencapture + ImageMagick + region mask 链路）；当前依赖 `DSHTheme.fidelitySidebarMid` token 值与目标 IDE 实测 1:1 锁定，色差收敛可由下次手动对比验证。
- 发版流程沿用 v0.5.87 自动化：`evolve.sh` 推 tag → `create-github-release-artifacts.sh` 签 zip + `gh release create` + 刷 `appcast.xml` 推 main；本次 push 命令收紧为只推新 tag（不再 `--tags`），避免本地历史重复 tag 阻断。
