# v0.5.70 — 2026-09-02

侧栏「自动化」→「自进化日志」（命名错位修正）

## 修复
- 侧栏一级菜单与账户菜单的旧标签「自动化」实际指向 EvolutionLogView（自进化历史），与项目未来计划新增的任务调度面板是两个不同概念。统一改名为「自进化日志」，标签、help 文案与无障碍标签同步更新。
- DesktopDesignParityTests 同步更新两条相关断言。

## 验证
- swift build -c release 通过
- swift run TapgoTests：desktop-design 全部断言通过（含「自进化日志位于一级导航」「自进化日志收进账户菜单」两条新断言）
- 失败的用例全部来自 RemoteDirectoryLister / RemoteSSHHarnessTransportIntegration / CodeXHomeSync（依赖 203.0.113.10 SSH 与 auth.json 环境），与本次改动无关
