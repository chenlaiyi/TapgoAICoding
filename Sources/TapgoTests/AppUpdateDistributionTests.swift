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

    t.expectEqual(info["CFBundleShortVersionString"] as? String, "0.5.65", "update: 主 App 版本")
    t.expectEqual(helperInfo["CFBundleShortVersionString"] as? String, "0.5.65", "update: Helper 版本")
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
    t.expect(appcast.contains("Tapgo-AICoding-0.5.65.zip"), "update: appcast 指向当前归档")
    t.expect(appcast.contains("sparkle:edSignature="), "update: 归档包含 EdDSA 签名")
}
