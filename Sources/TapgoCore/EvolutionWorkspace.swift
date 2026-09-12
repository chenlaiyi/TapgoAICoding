import Foundation

/// 自进化专属会话的共享逻辑（纯 Foundation，TapgoTests 可直接覆盖）。
///
/// 自进化 = 让 AI 对 Tapgo AICoding 项目自身做迭代开发。它是一个
/// **独立入口 + 独立对话 + 独立开发** 的专属会话：
///   - 独立入口：侧边栏「自进化」菜单直接进入，不再只是只读日志弹窗；
///   - 独立对话：`Thread.mode == Thread.evolutionMode`，在侧边栏单独
///     分组，不与普通项目会话混排；
///   - 独立开发：会话 cwd 固定在本项目根目录，AI 在该会话内读约定、
///     改代码、跑全量回归、对齐版本号。
public enum EvolutionWorkspace {
    /// 目录看起来像 Tapgo AICoding 项目根：同时存在 Package.swift
    /// （SPM 源码树）与 AGENTS.md（开发约定入口）。
    public static func looksLikeProjectRoot(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
            && fm.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path)
    }

    /// 定位本项目根目录。v0.5.255 起不再只认 `~/TapgoAICoding` ——
    /// 其他用户从 GitHub clone 时目录名/位置各不相同,这里按优先级探测:
    ///
    ///   1. `TAPGO_PROJECT_ROOT` 环境变量(显式指定,最高优先)
    ///   2. 约定的 `~/TapgoAICoding`
    ///   3. 常见变体:`~/TapgoAICoding-main`、`~/tapgo-aicoding`、
    ///      `~/dev/TapgoAICoding`、`~/Projects/TapgoAICoding`、`~/src/...`
    ///
    /// 找到即返回;都不像项目根时返回 nil,调用方据此禁用独立开发入口。
    public static func locateProjectRoot(home: URL) -> URL? {
        let fm = FileManager.default

        // 1) 显式指定
        if let raw = ProcessInfo.processInfo.environment["TAPGO_PROJECT_ROOT"],
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            if looksLikeProjectRoot(url) { return url }
        }

        // 2) 约定 + 常见变体
        // 注:刻意不检查 cwd —— GUI app 的 cwd 通常是 `/`,而且该探测会让
        // 「home 下没有项目」的判定失真(调用方依赖 nil 来禁用入口)。
        let candidates = [
            home.appendingPathComponent("TapgoAICoding", isDirectory: true),
            home.appendingPathComponent("TapgoAICoding-main", isDirectory: true),
            home.appendingPathComponent("tapgo-aicoding", isDirectory: true),
            home.appendingPathComponent("tapgo", isDirectory: true),
            home.appendingPathComponent("dev/TapgoAICoding", isDirectory: true),
            home.appendingPathComponent("Projects/TapgoAICoding", isDirectory: true),
            home.appendingPathComponent("src/TapgoAICoding", isDirectory: true),
        ]
        for candidate in candidates where looksLikeProjectRoot(candidate) {
            return candidate
        }
        return nil
    }

    /// 自进化会话的标题（固定，不参与 auto-title：hasDefaultTitle 只
    /// 认「新」前缀占位标题）。
    public static let threadTitle = "自进化"

    /// 进入自进化会话后「开始自进化」按钮发出的第一条指令。内容对齐
    /// AGENTS.md 的开发约定：先核对仓库状态，再自主选改进点，实现后
    /// 跑全量核心回归，最后按五层分开报告并对齐版本同步点。
    public static func kickoffPrompt(projectName: String = "Tapgo AICoding") -> String {
        """
        【自进化指令】你是 \(projectName) 的自进化开发代理。本会话是自进化专属会话，独立于其它对话，工作目录就是 \(projectName) 项目根。请独立完成一轮自进化开发：

        1. 背景核对：读 AGENTS.md（开发约定）、AGENT_MEMORY.md（长期记忆快照）、EVOLUTION.md 最新 3 条版本记录；执行 git fetch origin 并报告本地工作树、main 与 origin/main 的差异，存在未提交改动时先说明再决定是否继续。
        2. 选定改进点：从 EVOLUTION.md 各条目的 Next、evolution_state.json 的 nextActions、以及你自己在代码里发现的真实问题中，选定 1 个本回合能完整闭环的改进（修复或小特性），先给出 2–4 行计划。
        3. 实现：修改源码并保持既有代码风格；不引入新依赖。
        4. 验证：跑全量核心回归 `swift run TapgoTests`（默认跳过远程集成段），报告通过/失败的具体数字；涉及界面时另行说明需真机回归的范围。
        5. 收尾：把版本同步点全部对齐（project.yml、Info.plist、EVOLUTION.md、EvolutionLogView.swift 的 makeHistory()、git tag），给出建议版本号与 commit 信息，等我确认后再提交推送。

        报告约定：简体中文；每完成一个有意义步骤立即用 1–3 行报告；源码、测试、App 构建、已安装版本、真实界面回归五层分开报告，不用其中一层代替另一层。
        """
    }
}
