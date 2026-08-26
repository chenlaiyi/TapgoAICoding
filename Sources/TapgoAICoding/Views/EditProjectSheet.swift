import SwiftUI
import AppKit
import TapgoCore

/// "编辑项目" sheet — rename the project and manage **multiple source
/// folders** (the primary folder is the harness `cwd`; the rest are extra
/// folders the agent can develop across). Mirrors the "源文件夹" editor.
struct EditProjectSheet: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var name: String
    @State private var folders: [URL]
    @State private var errorMessage: String?
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.displayName)
        _folders = State(initialValue: [project.worktreeRoot] + project.sourceFolders)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑项目").font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier)).bold()
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).accessibilityLabel("关闭")
            }
            .padding(20)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nameField
                    sourceFoldersField
                }
                .padding(20)
            }

            Divider()
            HStack {
                Button(role: .destructive) {
                    removeProject()
                } label: {
                    Label("移除本地项目", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("从列表移除该项目（不会删除磁盘上的文件夹）")
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 500, height: 460)
        .onAppear {
            if name.isEmpty { name = project.displayName }
            if folders.isEmpty { folders = [project.worktreeRoot] }
        }
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("项目名").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("项目名", text: $name)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSHTheme.border, lineWidth: 1))
        }
    }

    // MARK: - Source folders

    private var sourceFoldersField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("源文件夹").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.secondary)
            Text("第一个列为主文件夹，其余作为附加源目录，agent 可跨这些目录开发。")
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
            VStack(spacing: 6) {
                ForEach(Array(folders.enumerated()), id: \.offset) { i, f in
                    folderRow(f, isPrimary: i == 0, removable: folders.count > 1) {
                        removeFolder(at: i)
                    }
                }
                Button {
                    addFolder()
                } label: {
                    Label("添加文件夹", systemImage: "folder.badge.plus")
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSHTheme.border, lineWidth: 1))
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.red)
            }
        }
    }

    private func folderRow(_ f: URL, isPrimary: Bool, removable: Bool, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(isPrimary ? DSHTheme.brand : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(isPrimary ? "\(f.lastPathComponent)（主）" : f.lastPathComponent)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                Text(f.path)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .disabled(!removable)
            .help(removable ? "移除该文件夹" : "至少保留一个文件夹")
            .accessibilityLabel(removable ? "移除 \(f.lastPathComponent)" : "至少保留一个文件夹")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSHTheme.border, lineWidth: 1))
    }

    // MARK: - Actions

    private func addFolder() {
        do {
            let result = try LocalDirectoryPicker.pickDirectory()
            let url = result.url.standardizedFileURL
            if !folders.contains(url) {
                folders.append(url)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeFolder(at index: Int) {
        guard folders.count > 1, index < folders.count else { return }
        folders.remove(at: index)
    }

    private func save() {
        guard let primary = folders.first else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = Project(
            id: project.id,
            displayName: trimmedName.isEmpty ? project.displayName : trimmedName,
            kind: project.kind,
            addedAt: project.addedAt,
            lastUsedAt: project.lastUsedAt,
            worktreeRoot: primary,
            sourceFolders: Array(folders.dropFirst()),
            bookmark: project.bookmark,
            remoteHostId: project.remoteHostId,
            remotePath: project.remotePath
        )
        workspace.updateProject(updated)
        dismiss()
    }

    private func removeProject() {
        workspace.removeProject(project.id)
        dismiss()
    }
}
