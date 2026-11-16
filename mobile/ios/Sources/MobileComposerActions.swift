import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import WebKit

/// Keeps selected bytes local until Send and retains them after a failed submission.
@MainActor
final class MobileComposerAdditions: ObservableObject {
    @Published var attachments: [MobileDraftAttachment] = []
    @Published var mode: MobileComposerMode = .message
    @Published var showingMenu = false
    @Published var error: String?
    @Published var importing = false
    private var importGeneration = UUID()
    var hasAttachments: Bool { !attachments.isEmpty }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-attachments") {
            attachments = [MobileDraftAttachment(name: "fixture.txt", data: Data("isolated fixture".utf8), image: false)]
            if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-many-attachments") {
                attachments += (1...8).map {
                    MobileDraftAttachment(name: "很长的附件名称-\($0)-reference-notes.txt", data: Data([1]), image: false)
                }
            }
        }
        #endif
    }

    func addImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            error = "无法读取这张照片，请重新选择"
            return
        }
        attachments.append(MobileDraftAttachment(name: "照片.jpg", data: data, image: true))
    }

    func loadPhoto(_ item: PhotosPickerItem) async {
        let generation = UUID()
        importGeneration = generation
        importing = true
        defer { if importGeneration == generation { importing = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { throw MobileComposerFailure.invalidImage }
            guard importGeneration == generation else { return }
            addImage(image)
        } catch {
            if importGeneration == generation { self.error = "无法读取照片，请重新选择" }
        }
    }

    func loadFiles(_ urls: [URL]) async {
        importing = true
        defer { importing = false }
        do {
            let files = try await Task.detached {
                try urls.map { url in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return MobileDraftAttachment(name: url.lastPathComponent,
                                                 data: try Data(contentsOf: url), image: false)
                }
            }.value
            attachments.append(contentsOf: files)
        } catch {
            self.error = "无法读取所选文件，请重新选择"
        }
    }
}

private struct MobileAddAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

struct MobileComposerAddButton: View {
    @ObservedObject var additions: MobileComposerAdditions
    let prepare: () -> Void
    var body: some View {
        Button {
            prepare()
            additions.showingMenu.toggle()
        } label: {
            Image(systemName: additions.showingMenu ? "xmark" : "plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("添加到对话")
        .accessibilityIdentifier("composerAdd")
        .accessibilityValue(additions.showingMenu ? "已展开" : "已收起")
        .anchorPreference(key: MobileAddAnchor.self, value: .bounds) { $0 }
    }
}

struct MobileComposerAttachmentStrip: View {
    @ObservedObject var additions: MobileComposerAdditions
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if additions.importing { ProgressView("正在读取附件…").font(.caption) }
            if let error = additions.error { Text(error).font(.caption).foregroundStyle(.red) }
            if additions.mode != .message {
                HStack {
                    Label(additions.mode.title, systemImage: additions.mode == .plan ? "list.bullet" : "target")
                    Spacer()
                    Button("取消模式") { additions.mode = .message }
                }
                .font(.caption).frame(minHeight: 44)
            }
            if !additions.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(additions.attachments) { attachment in
                            HStack(spacing: 4) {
                                Label(attachment.name, systemImage: attachment.image ? "photo" : "paperclip")
                                    .lineLimit(1).truncationMode(.middle)
                                Button {
                                    additions.attachments.removeAll { $0.id == attachment.id }
                                } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                    .accessibilityLabel("移除\(attachment.name)")
                            }
                            .font(.caption)
                            .padding(.leading, 10)
                            .frame(maxWidth: 240, minHeight: 44)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .frame(height: 44)
            }
        }
    }
}

private enum MobileAddAction: String, CaseIterable, Identifiable {
    case camera, photos, files, plugins, plan, goal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .camera: "相机"
        case .photos: "照片"
        case .files: "文件"
        case .plugins: "插件"
        case .plan: "方案模式"
        case .goal: "追求目标"
        }
    }
    var symbol: String {
        switch self {
        case .camera: "camera"
        case .photos: "photo.on.rectangle"
        case .files: "paperclip"
        case .plugins: "puzzlepiece.extension"
        case .plan: "list.bullet"
        case .goal: "target"
        }
    }
}

private struct MobileComposerActions: ViewModifier {
    @ObservedObject var additions: MobileComposerAdditions
    let computer: SavedComputer
    var planActive: Bool
    var onPlanOff: (() -> Void)?
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingPlugins = false
    @State private var photo: PhotosPickerItem?
    @Environment(\.sizeCategory) private var sizeCategory

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(MobileAddAnchor.self) { anchor in
                GeometryReader { geometry in
                    if additions.showingMenu, let anchor {
                        let button = geometry[anchor]
                        let width = min(CGFloat(280), geometry.size.width - 32)
                        let available = max(CGFloat(44), button.minY - 16)
                        ZStack(alignment: .topLeading) {
                            Color.black.opacity(0.08)
                                .contentShape(Rectangle())
                                .onTapGesture { additions.showingMenu = false }
                                .accessibilityLabel("收起添加菜单")
                                .accessibilityIdentifier("composerMenuDismiss")
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(MobileAddAction.allCases) { action in
                                        Button { select(action) } label: {
                                            HStack(spacing: 13) {
                                                Image(systemName: action.symbol).frame(width: 30)
                                                Text(action.title)
                                                Spacer(minLength: 0)
                                                if (action == .plan && (additions.mode == .plan || planActive))
                                                    || (action == .goal && additions.mode == .goal) {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 14)
                                            .frame(minHeight: 48)
                                            .padding(.vertical, sizeCategory.isAccessibilityCategory ? 6 : 0)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("composerAction-\(action.rawValue)")
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .frame(width: width, height: min(available, sizeCategory.isAccessibilityCategory ? 440 : 304))
                            .mobileGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .offset(x: max(16, min(button.minX, geometry.size.width - width - 16)),
                                    y: max(8, button.minY - min(available, sizeCategory.isAccessibilityCategory ? 440 : 304) - 8))
                            .accessibilityIdentifier("composerQuickMenu")
                        }
                    }
                }
            }
            .photosPicker(isPresented: $showingPhotos, selection: $photo, matching: .images)
            .onChange(of: photo) { item in
                guard let item else { return }
                Task { await additions.loadPhoto(item); photo = nil }
            }
            .sheet(isPresented: $showingCamera) {
                MobileComposerCamera { image in
                    additions.addImage(image)
                    showingCamera = false
                }
            }
            .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await additions.loadFiles(urls) }
                case .failure: additions.error = "无法打开文件，请重试"
                }
            }
            .sheet(isPresented: $showingPlugins) { MobileComposerPlugins(computer: computer) }
    }

    private func select(_ action: MobileAddAction) {
        additions.showingMenu = false
        additions.error = nil
        switch action {
        case .camera:
            if UIImagePickerController.isSourceTypeAvailable(.camera) { showingCamera = true }
            else { additions.error = "此设备无法使用相机，请选择照片" }
        case .photos: showingPhotos = true
        case .files: showingFiles = true
        case .plugins: showingPlugins = true
        case .plan:
            if planActive, let onPlanOff { onPlanOff() }
            else { additions.mode = additions.mode == .plan ? .message : .plan }
        case .goal: additions.mode = additions.mode == .goal ? .message : .goal
        }
    }
}

extension View {
    func mobileComposerActions(_ additions: MobileComposerAdditions, computer: SavedComputer,
                               planActive: Bool = false, onPlanOff: (() -> Void)? = nil) -> some View {
        modifier(MobileComposerActions(additions: additions, computer: computer,
                                       planActive: planActive, onPlanOff: onPlanOff))
    }
}

private struct MobileComposerCamera: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MobileComposerCamera
        init(parent: MobileComposerCamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            else { parent.dismiss() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

private struct MobilePluginBundle: Decodable, Identifiable {
    let name: String
    let enabled: Bool
    let optional: Bool
    let installed: Bool
    let availability: String
    let readOnlyReason: String?
    let description: String?
    var id: String { name }
}

/// Bundle changes are explicit, confirmed profile-wide actions, with saved/runtime outcomes kept separate.
private struct MobileComposerPlugins: View {
    let computer: SavedComputer
    @Environment(\.dismiss) private var dismiss
    @State private var bundles: [MobilePluginBundle] = []
    @State private var loading = false
    @State private var changing = false
    @State private var error: String?
    @State private var notice: String?
    @State private var pending: MobilePluginBundle?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("插件作用于 \(computer.name) 上的整个配置，影响所有对话") }
                if loading { ProgressView("正在读取插件…") }
                if let error {
                    Section { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } }
                }
                if let notice { Section { Text(notice) } }
                ForEach(bundles) { bundle in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(bundle.name).font(.headline)
                        if let description = bundle.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Text(bundle.enabled ? "已启用" : "未启用").foregroundStyle(.secondary)
                            Spacer()
                            if bundle.readOnlyReason == nil && (bundle.availability != "missing" && (bundle.installed || bundle.optional)) {
                                Button(bundle.enabled ? "停用" : "启用") { pending = bundle }
                                    .disabled(changing || loading)
                            }
                        }
                        .font(.subheadline)
                    }
                }
                if !loading && bundles.isEmpty && error == nil { Text("此电脑暂无可管理的插件") }
            }
            .navigationTitle("插件")
            .toolbar { Button("完成") { dismiss() }.disabled(changing) }
            .task { await load() }
            .alert("更改电脑插件", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("取消", role: .cancel) { pending = nil }
                Button("确认") {
                    if let bundle = pending { pending = nil; Task { await change(bundle) } }
                }
            } message: {
                Text("将在 \(computer.name) 上\(pending?.enabled == true ? "停用" : "启用")此插件，影响该电脑的所有对话，可能需要重启后生效")
            }
            .interactiveDismissDisabled(changing)
        }
    }
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let transport = try await MobileComposerTransport.open(computer: computer)
            defer { transport.session.invalidateAndCancel() }
            let value = try await transport.call("pluginManager/listBundles", args: [:])
            bundles = try JSONDecoder().decode([MobilePluginBundle].self, from: JSONSerialization.data(withJSONObject: value))
            error = nil
        } catch { self.error = "无法读取插件，此电脑可能不支持插件管理，请重试" }
    }
    private func change(_ bundle: MobilePluginBundle) async {
        changing = true
        error = nil
        notice = nil
        defer { changing = false }
        do {
            let transport = try await MobileComposerTransport.open(computer: computer)
            defer { transport.session.invalidateAndCancel() }
            guard let value = try await transport.call("pluginManager/setBundleEnabled", args: ["name": bundle.name, "enabled": !bundle.enabled]) as? [String: Any] else {
                throw MobileComposerFailure.unavailable
            }
            switch value["application"] as? String {
            case "applied": notice = "插件设置已生效"
            case "restart-required": notice = "插件设置已保存，需要在电脑上重启后生效"
            case "overridden": notice = "设置已保存，但被更高优先级的配置覆盖"
            default: notice = "插件未成功生效，请检查电脑端状态后再操作"
            }
            await load()
        } catch {
            await load()
            self.error = "更改结果尚未确认，已重新读取插件列表，请核对电脑端状态后再操作"
        }
    }
}

extension MobileComposerTransport {
    static func open(computer: SavedComputer) async throws -> MobileComposerTransport {
        guard let origin = URL(string: computer.origin), let pairing = URL(string: computer.connectionURL) else {
            throw MobileComposerFailure.unavailable
        }
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let cookies = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == origin.host {
            configuration.httpCookieStorage?.setCookie(cookie)
        }
        let session = URLSession(configuration: configuration)
        do {
            let (_, response) = try await session.data(from: pairing)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MobileComposerFailure.unavailable }
            return MobileComposerTransport(session: session, origin: origin)
        } catch {
            session.invalidateAndCancel()
            throw error
        }
    }

}
