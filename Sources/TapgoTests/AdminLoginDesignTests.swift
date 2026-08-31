import Foundation

private func loginDesignFile(_ relativePath: String) -> String {
    let root = FileManager.default.currentDirectoryPath
    return (try? String(contentsOfFile: root + "/" + relativePath, encoding: .utf8)) ?? ""
}

@MainActor
func runAdminLoginDesign(_ t: TestRunner) {
    let source = loginDesignFile("Sources/TapgoAICoding/Views/AdminLoginView.swift")
    let app = loginDesignFile("Sources/TapgoAICoding/App.swift")
    let build = loginDesignFile("scripts/build-app.sh")
    let artworkPath = FileManager.default.currentDirectoryPath + "/AppBuilder/LoginBrandBackground.png"
    let artwork = try? Data(contentsOf: URL(fileURLWithPath: artworkPath))

    t.expect(source.contains("GeometryReader"), "login-design: 响应式左右分栏")
    t.expect(source.contains("brandWidthRatio"), "login-design: 品牌区比例受控")
    t.expect(source.contains("NSApplication.shared.applicationIconImage"), "login-design: 复用真实 App 图标")
    t.expect(source.contains("LoginBrandBackground"), "login-design: 使用独立品牌背景资产")
    t.expect(source.contains("微信扫码登录"), "login-design: 主标题清晰")
    t.expect(source.contains("打开微信扫一扫，确认后自动登录"), "login-design: 扫码指引保留")
    t.expect(source.contains("等待扫码 ·"), "login-design: 倒计时状态保留")
    t.expect(source.contains("刷新二维码"), "login-design: 刷新交互保留")
    t.expect(source.contains("重新获取二维码"), "login-design: 失败重试保留")
    t.expect(source.contains("accessibilityLabel(\"微信登录二维码\")"), "login-design: 二维码辅助功能标签")
    t.expect(app.contains("TAPGO_ADMIN_LOGIN_PREVIEW"), "login-design: 无损真实界面验收入口")
    t.expect(build.contains("LoginBrandBackground.png"), "login-design: Release 构建嵌入背景资产")
    t.expect((artwork?.count ?? 0) > 100_000, "login-design: 品牌背景资产存在且非占位图")
}
