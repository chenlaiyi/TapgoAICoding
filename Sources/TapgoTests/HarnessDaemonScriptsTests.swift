// TapgoTests/HarnessDaemonScriptsTests.swift
// v0.5.319：harness daemon 部署链路的 shell 脚本回归。
//
// 覆盖三个真实踩过的坑：
//   1. API key 提取只认 `sk-cp-` 前缀 —— 供应商精简成 DeepSeek 后配置里是
//      `sk-…`，`install-harness-daemon.sh` 直接报「找不到 API key」；
//      模板里还有一行注释形式的 `# experimental_bearer_token …` 不能被误取。
//   2. 遗留注册表/多供应商配置下要优先取 `[model_providers.deepseek]` 段。
//   3. 探针必须能在「socket 缺失 / socket 存在但无人监听」时明确失败，
//      否则部署脚本会把坏的 daemon 当成成功。

import Foundation

private struct ScriptResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

@discardableResult
private func runScript(_ path: String, _ args: [String]) -> ScriptResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [path] + args
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do {
        try process.run()
    } catch {
        return ScriptResult(status: -1, stdout: "", stderr: "launch failed: \(error)")
    }
    process.waitUntilExit()
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    return ScriptResult(
        status: process.terminationStatus,
        stdout: String(data: outData, encoding: .utf8) ?? "",
        stderr: String(data: errData, encoding: .utf8) ?? ""
    )
}

func runHarnessDaemonScripts(_ t: TestRunner) {
    t.section("Harness daemon 脚本: key 提取 / 探针 / dry-run")

    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Sources/TapgoTests
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // repo root
    let apiKeyScript = root.appendingPathComponent("scripts/harness-api-key.sh").path
    let probeScript = root.appendingPathComponent("scripts/harness-daemon-probe.sh").path
    let deployScript = root.appendingPathComponent("scripts/deploy-harness-daemon.sh").path

    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-daemon-scripts-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    func fixture(_ name: String, _ body: String) -> String {
        let url = dir.appendingPathComponent(name)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // 1) DeepSeek-only 配置（真实线上形态）：注释行必须跳过，sk- 前缀必须接受
    let deepseekOnly = fixture("config-deepseek.toml", """
    model = "deepseek-flash"
    model_provider = "deepseek"

    [model_providers.deepseek]
    name = "DeepSeek"
    base_url = "https://api.deepseek.com"
    experimental_bearer_token = "sk-deepseek-real-key"

    [notice]
    # experimental_bearer_token 已由 App 注入真实 key,
    """)
    let r1 = runScript(apiKeyScript, [deepseekOnly])
    t.expectEqual(r1.status, 0, "api-key: DeepSeek-only 配置提取成功")
    t.expectEqual(r1.stdout, "sk-deepseek-real-key",
                  "api-key: 取到 sk- 前缀 token 而不是空（旧的 sk-cp- 正则在这里必挂）")

    // 2) 多供应商配置：必须优先 DeepSeek 段，而不是文件里第一个 token
    let mixed = fixture("config-mixed.toml", """
    [model_providers.minimax]
    experimental_bearer_token = "sk-cp-legacy-minimax"

    [model_providers.deepseek]
    experimental_bearer_token = "sk-deepseek-preferred"
    """)
    let r2 = runScript(apiKeyScript, [mixed])
    t.expectEqual(r2.status, 0, "api-key: 多供应商配置提取成功")
    t.expectEqual(r2.stdout, "sk-deepseek-preferred",
                  "api-key: 优先取 [model_providers.deepseek] 段")

    // 3) 无 deepseek 段时回退到第一个非注释 token
    let fallback = fixture("config-fallback.toml", """
    # experimental_bearer_token = "sk-commented-should-be-skipped"
    [model_providers.custom]
    experimental_bearer_token = "sk-custom-fallback"
    """)
    let r3 = runScript(apiKeyScript, [fallback])
    t.expectEqual(r3.stdout, "sk-custom-fallback", "api-key: 回退取第一个非注释 token")
    t.expect(r3.stdout != "sk-commented-should-be-skipped", "api-key: 不取注释行")

    // 4) 完全没有 token → 非零退出（调用方据此报错）
    let empty = fixture("config-empty.toml", """
    model = "deepseek-flash"
    """)
    let r4 = runScript(apiKeyScript, [empty])
    t.expect(r4.status != 0, "api-key: 没有 token 时非零退出")
    let r5 = runScript(apiKeyScript, [dir.appendingPathComponent("missing.toml").path])
    t.expect(r5.status != 0, "api-key: 配置文件不存在时非零退出")

    // 5) 探针：socket 缺失 → 退出码 3（部署脚本必须能识别为「没在服务」）
    let r6 = runScript(probeScript, [dir.appendingPathComponent("nope.sock").path])
    t.expectEqual(r6.status, 3, "probe: socket 缺失返回 3")
    t.expect(r6.stderr.contains("socket 不存在"), "probe: 缺失时给出可读原因")

    // 6) 探针：socket 文件存在但无人监听 → 失败（不能误判为成功）
    let fakeSock = dir.appendingPathComponent("fake.sock").path
    FileManager.default.createFile(atPath: fakeSock, contents: Data())
    let r7 = runScript(probeScript, [fakeSock])
    t.expect(r7.status != 0, "probe: 无人监听时失败（不会把坏 daemon 当成功）")

    // 7) 部署脚本 dry-run：不改动任何东西且不报错
    let r8 = runScript(deployScript, ["--dry-run", "--only", "local"])
    t.expectEqual(r8.status, 0, "deploy-harness-daemon: --dry-run --only local 退出 0")
    t.expect(r8.stdout.contains("[dry-run]"), "deploy-harness-daemon: dry-run 打印计划")
    t.expect(r8.stdout.contains("并发探针"), "deploy-harness-daemon: 计划里包含探针校验")
}
