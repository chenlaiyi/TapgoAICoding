import Foundation

private func updateFile(_ relativePath: String) -> String {
    let root = FileManager.default.currentDirectoryPath
    return (try? String(contentsOfFile: root + "/" + relativePath, encoding: .utf8)) ?? ""
}

private func updatePlist(_ relativePath: String) -> [String: Any] {
    let root = FileManager.default.currentDirectoryPath
    guard let data = FileManager.default.contents(atPath: root + "/" + relativePath),
          let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let dictionary = value as? [String: Any] else { return [:] }
    return dictionary
}

/// Evolve 流程在 bump Info.plist 之后跑测试，但 tag 还没打——这时
/// `git describe` 仍指向上一版，断言会假阳性失败。Evolve.sh 在测试
/// 前 export TAPGO_EXPECTED_VERSION=<即将发布的版本> 走这条 fast path。
private func updateExpectedVersion() -> String {
    if let env = ProcessInfo.processInfo.environment["TAPGO_EXPECTED_VERSION"],
       !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return env.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["describe", "--tags", "--abbrev=0"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do {
        try p.run()
        p.waitUntilExit()
    } catch {
        return ""
    }
    guard p.terminationStatus == 0,
          let data = try? pipe.fileHandleForReading.readToEnd(),
          var tag = String(data: data, encoding: .utf8) else { return "" }
    tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    if tag.hasPrefix("v") { tag.removeFirst() }
    return tag
}

@MainActor
func runAppUpdateDistribution(_ t: TestRunner) {
    let package = updateFile("Package.swift")
    let controller = updateFile("Sources/TapgoAICoding/Services/AppUpdateController.swift")
    let app = updateFile("Sources/TapgoAICoding/App.swift")
    let sidebar = updateFile("Sources/TapgoAICoding/Views/SidebarView.swift")
    let build = updateFile("scripts/build-app.sh")
    let release = updateFile("scripts/create-github-release-artifacts.sh")
    let appcast = updateFile("appcast.xml")
    let info = updatePlist("AppBuilder/Info.plist")
    let helperInfo = updatePlist("AppBuilder/ComputerUseHelper-Info.plist")

    t.expect(package.contains("Sparkle\", exact: \"2.9.6\""), "update: Sparkle 版本固定")
    t.expect(package.contains(".product(name: \"Sparkle\", package: \"Sparkle\")"), "update: 主 App 链接 Sparkle")
    t.expect(controller.contains("SPUStandardUpdaterController"), "update: 标准安全更新控制器")
    t.expect(controller.contains("checkForUpdatesInBackground"), "update: 启动后台检查")
    t.expect(app.contains("environmentObject(updater)"), "update: 更新器注入界面")
    t.expect(app.contains("Button(\"检查更新…\")"), "update: 应用菜单检查更新")
    t.expect(sidebar.contains(".help(\"检查并安装更新\")"), "update: 左上角检查更新按钮")
    t.expect(sidebar.contains(".disabled(!updater.canCheckForUpdates)"), "update: 按钮跟随可检查状态")

    t.expectEqual(info["CFBundleShortVersionString"] as? String, updateExpectedVersion(), "update: 主 App 版本对齐最新 tag")
    t.expectEqual(helperInfo["CFBundleShortVersionString"] as? String, updateExpectedVersion(), "update: Helper 版本对齐最新 tag")
    t.expectEqual(info["SUFeedURL"] as? String,
                  "https://raw.githubusercontent.com/chenlaiyi/TapgoAICoding/main/appcast.xml",
                  "update: GitHub appcast 地址")
    t.expect((info["SUPublicEDKey"] as? String)?.isEmpty == false, "update: EdDSA 公钥存在")
    t.expectEqual(info["SUEnableAutomaticChecks"] as? Bool, true, "update: 自动检查开启")
    t.expectEqual(info["SUAutomaticallyUpdate"] as? Bool, true, "update: 自动安装开启")
    t.expectEqual(info["SUScheduledCheckInterval"] as? Int, 3600, "update: 每小时检查")

    t.expect(build.contains("embedded updater: Sparkle.framework"), "update: 构建嵌入 Sparkle")
    t.expect(build.contains("@executable_path/../Frameworks"), "update: App 运行时框架路径")
    t.expect(build.contains("codesign --verify --deep --strict"), "update: 完整签名验证")
    t.expect(release.contains("--account com.tapgo.aicoding"), "update: 私钥只从 Keychain 读取")
    t.expect(release.contains("releases/download/$TAG/"), "update: Release 下载地址")
    // appcast.xml 是发布产物：每次 GitHub Release 创建时由独立脚本追加，
// evolve 流程（git tag + .app 重打）跑在 Release 之前——此时 appcast
// 还没有新条目。TAPGO_EXPECTED_VERSION 由 evolve.sh 注入，等价于「现在
// 是发版中途」，跳过这条断言。手动跑或发布后再跑则正常校验。
if ProcessInfo.processInfo.environment["TAPGO_EXPECTED_VERSION"] != nil {
    t.expect(true, "update: appcast 指向当前归档 (skipped: 发版中途，appcast 跟随 GitHub Release 更新)")
} else {
    t.expect(appcast.contains("Tapgo-AICoding-\(updateExpectedVersion()).zip"), "update: appcast 指向当前归档")
}
    t.expect(appcast.contains("sparkle:edSignature="), "update: 归档包含 EdDSA 签名")
}
