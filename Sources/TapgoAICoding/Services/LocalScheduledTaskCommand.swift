import AppKit
import TapgoCore

/// Common app-opening schedules work even without a configured model or TCC.
@MainActor
enum LocalScheduledTaskCommand {
    static func reply(to text: String, isRemote: Bool) -> String? {
        guard let request = ScheduledTaskCommands.parse(text) else { return nil }
        guard !isRemote else {
            return "这条对话连接的是远程主机。请切换到要运行应用的 Mac 上的本地对话，再发送此指令，避免把任务创建在错误的电脑上。"
        }
        let normalized = request.applicationName.lowercased()
        let knownID = ["zoom": "us.zoom.xos", "zoom.us": "us.zoom.xos"][normalized]
        let app = ComputerApplicationLookup.find(name: request.applicationName, bundleID: knownID)
        guard let app, let bundleID = Bundle(url: app)?.bundleIdentifier else {
            return "未创建任务：本机未找到“\(request.applicationName)”。请先安装该应用，或使用它在“应用程序”中的完整名称重试。"
        }
        do {
            let result = try ScheduledTaskMCP(applicationExists: {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }).create(name: "打开 \(request.applicationName)", prompt: "打开 \(request.applicationName) app",
                schedule: request.schedule, bundleID: bundleID)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd EEEE HH:mm"
            formatter.locale = Locale(identifier: "zh_CN")
            let next = result.task.nextFireAt.map(formatter.string(from:)) ?? "未定"
            return "\(result.created ? "已创建定时任务" : "该定时任务已存在，无需重复创建")：\(request.schedule.label)打开 \(request.applicationName)。\n\n运行电脑：\(Host.current().localizedName ?? "本机")\n时区：\(TimeZone.current.identifier)\n下次运行：\(next)\n任务 ID：\(result.task.id.uuidString)\n\n届时直接打开应用，无需模型或电脑控制授权。Tapgo 需保持运行，电脑需处于唤醒状态；周一至周五不包含法定节假日调休判断。可在“定时任务”面板查看、停用或删除。"
        } catch {
            return "定时任务未创建：\(error.localizedDescription)"
        }
    }
}

private enum ComputerApplicationLookup {
    static func find(name: String, bundleID: String?) -> URL? {
        if let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID ?? name) { return resolved }
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for root in roots {
            for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let names = [url.deletingPathExtension().lastPathComponent,
                    bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                    bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String].compactMap { $0 }
                if names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return url }
            }
        }
        return nil
    }
}
