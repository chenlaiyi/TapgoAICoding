import Foundation

/// GUI App 从 Finder/Dock 启动时只有最小 PATH（/usr/bin:/bin:/usr/sbin:/sbin）。
/// npm 版 `/opt/homebrew/bin/codex` 是 `#!/usr/bin/env node` 脚本，PATH 里
/// 解析不到 node 就以 127 退出 —— 表现为设置页永远报“Codex CLI 版本过旧或
/// 无法识别”，且每次 `npm i -g @openai/codex` 升级都会复发（v0.5.109 修）。
/// 所有 spawn codex 的子进程（版本探测、LocalHarnessTransport、
/// HarnessDaemonLauncher、TapgoHarness daemon）都必须用这份环境。
public enum HarnessChildEnvironment {
    /// 继承（或以 `base` 为底）并把 Homebrew / 本地 bin 目录前置到 PATH。
    /// `base` 仅供测试注入模拟的 GUI 最小环境。
    public static func make(base: [String: String]? = nil) -> [String: String] {
        var env = base ?? ProcessInfo.processInfo.environment
        let prefix = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (prefix + [existing]).joined(separator: ":")
        return env
    }
}
