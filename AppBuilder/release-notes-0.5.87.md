# Tapgo AICoding 0.5.87

- 「参照目标 IDE 风格」fidelity patch 3/3：剩余 2 处主区域背景切到 fidelityXxx token：
  - `ChatView.swift` L199 主画布 `.background(DSHTheme.bg)` → `.background(DSHTheme.fidelityMainCanvas)`（0x151517 → 0x1E1E1D，差 −9/255）
  - `RightWorkbenchView.swift` L32 外层容器 / L52 环境信息面板顶栏 / L178 Tab 条顶栏共 3 处 `.background(DSHTheme.bg|DSHTheme.titlebarBg)` → `.background(DSHTheme.fidelityRightbarTop)`（0x1A1A1C → 0x212120，差 −11/255）
  - 预期中央 1000x740 像素差从 13.4% 进一步收敛；sidebar_mid 单点差 −15/255 因无独立视图背景位，仍作为后续 patch 候选。
- 发版自动化：`evolve.sh` 在 `git push` 之后自动串接 `scripts/create-github-release-artifacts.sh`：
  - 生成 Sparkle EdDSA 签名 zip
  - 调 `gh release create` 上传到 GitHub Release（已登录 `chenlaiyi`）
  - 把刷新后的 `appcast.xml` 提交并 push，让所有已装客户端 Sparkle 下一轮 poll 自动拉到 v0.5.87
  - 幂等：tag 已存在则只覆盖 zip + release notes；`gh` 缺失时降级为打印手动命令。
- `AppBuilder/project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 不再硬编码：每次 `evolve.sh` 写 Info.plist 时同步注入新版本号，避免 `xcodegen` 重跑时漂移到 0.5.69（此前已漂移 17 个版本）。
- `AgentOutputPolicy` 文案层对齐：5 个状态前缀（✅/❌/⚠️/🔍/💬）强制开头、禁 markdown 装饰、列表 ≤3 项、默认 ≤6 行（要详才 8）、失败 1 行「影响+处理方向」；`AgentOutputPolicyTests` 41 条断言覆盖 `threadInstructions` / `turnReminder` / `catalogInstructions` 与体积预算。
- 测试：2706 通过 / 0 失败（TAPGO_SKIP_REMOTE_INTEGRATION=1）；预存在远程 SSH 集成测试不在本次回归范围；DesktopDesignParityTests 新增 2 条断言锁住 fidelityMainCanvas / fidelityRightbarTop 视图引用。
- 已知限制：sidebar_mid 区域与目标 IDE 仍差 15/255，需后续单独排查；当前未跑自动 pixelmatch 验证。
