# Tapgo AICoding 0.5.74

- 「贴近 ZCode」迭代第一步：DSHTheme 拓宽到与 ZCode asar 频繁色对照的常量，未来 ZCode 升级漂移会被编译期测试捕获：
  - `brandBlueZCode = #4099FF` — ZCode 编译 stylesheet 中出现 28 次的最高频蓝，是 ZCode focusable row 高亮环取值。
  - `warnZCode = #CD8900` — ZCode 编译 stylesheet 中出现 16 次的警告色（amber-700）。
  - `errorZCode = #E40014` — ZCode 编译 stylesheet 中出现 26 次的危险色（高饱和红）。
  - 与现有 `brand / warn / error`（DSH 主题 deepseek-500/450 + amber-500 + red-600）并存而非替换——这是 ZCode 基准值的固化，不是 UI 替换。
- `Sources/TapgoTests/DesktopZCodeDesignTests.swift` 加 5 个贴近断言（`Desktop: ZCode interaction design` 从 38 → 43 passed）：
  - ZCode 频繁蓝/警告/危险色三个 token 已固化
  - 桌面层 + ZCode 频繁色 token 全部就位
  - macOS 标题栏自绘 + 紧凑工具栏配置持久（v0.5.65 起的承诺，未被 v0.5.74 改动回退）
- 测试状态：2685 passed / 14 failed（与 v0.5.73 同样 13 个远程 SSH 集成 + 1 个 appcast 对齐回归，无新增失败）。
- 真机回归受限于沙箱模型账号都被锁住，DSHTheme 新增的 3 个 token 暂时只是 ground truth；短期挂载点（Next 列）：SidebarView 项目选中高亮环、WorkbenchReview statusbar——你登录账号后 review PR 时可以让 AI 助手接着挂上去。