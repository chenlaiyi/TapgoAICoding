import Foundation

/// Owns the on-disk persistence for `WorkspaceState` (projects,
/// remote hosts, active selection).
///
/// File layout:
///   ~/Library/Application Support/Tapgo AICoding/state/v1/workspace.json
///
/// Permissions 0700 on the directory, 0600 on the file. We never touch
/// the user's `~/.codex/` (or any other Codex home) from here.
@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public private(set) var state: WorkspaceState
    public let stateFileURL: URL
    public let stateDirURL: URL
    /// Pinned project ids (persisted), sorted to the top of the list.
    @Published public var pinnedProjectIds: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(pinnedProjectIds), forKey: "tapgo.pinnedProjects") }
    }

    private let fileManager = FileManager.default

    public init() {
        // ~/Library/Application Support/Tapgo AICoding/state/v1/
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tapgo AICoding", isDirectory: true)
        self.stateDirURL = base.appendingPathComponent("state/v1", isDirectory: true)
        self.stateFileURL = stateDirURL.appendingPathComponent("workspace.json")
        self.state = .empty
        self.pinnedProjectIds = Set(UserDefaults.standard.stringArray(forKey: "tapgo.pinnedProjects") ?? [])
        load()
    }

    /// Test-only constructor: pin the on-disk location.
    public init(testDirectory: URL) {
        self.stateDirURL = testDirectory
        self.stateFileURL = testDirectory.appendingPathComponent("workspace.json")
        self.state = .empty
        try? fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Load / save

    public func load() {
        do {
            try fileManager.createDirectory(
                at: stateDirURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            NSLog("[WorkspaceStore] mkdir failed: \(error.localizedDescription)")
        }
        guard fileManager.fileExists(atPath: stateFileURL.path) else {
            state = .empty
            return
        }
        do {
            let data = try Data(contentsOf: stateFileURL)
            // 0600 on the file itself even if it pre-existed with
            // looser permissions (fixes accidents from earlier dev).
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateFileURL.path)
            let loaded = try JSONDecoder().decode(WorkspaceState.self, from: data)
            // Migrations live in `migrate(_:)`.
            state = migrate(loaded)
        } catch {
            NSLog("[WorkspaceStore] load failed: \(error.localizedDescription). Using empty state.")
            state = .empty
        }
        // Code path: for every remote project, the local mirror dir
        // *must* exist on disk. codex 0.149.0's unified exec process
        // chdir's into the workspace_root before exec'ing the shell;
        // if that directory is missing, the harness refuses the
        // command and the model is told "shell unavailable". We
        // touch the directory now (idempotent) so the existing
        // workspace doesn't get stuck.
        for project in state.projects where project.kind == .remote {
            ensureRemoteMirrorExists(project)
        }
    }

    /// Create the local mirror directory for a remote project if it
    /// is missing. The mirror never has real content — it's only
    /// there so the harness has a valid cwd to chdir into before
    /// `RemoteExecutor` swaps the result with the SSH output.
    @discardableResult
    public func ensureRemoteMirrorExists(_ project: Project) -> Bool {
        guard project.kind == .remote else { return false }
        let url = project.worktreeRoot
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            // Belt-and-suspenders: a .tapgo-mirror marker file so the
            // user can see why this empty directory exists when they
            // `ls` it. Hidden by default.
            let marker = url.appendingPathComponent(".tapgo-mirror")
            let body = "Tapgo AICoding local mirror for remote project \(project.displayName)\n"
                + "harness cwd: \(url.path)\n"
                + "remote target: \(project.displayPath)\n"
                + "Do not edit by hand. Safe to delete; will be re-created on next launch.\n"
            try? body.data(using: .utf8)?.write(to: marker, options: [.atomic])
            return true
        } catch {
            NSLog("[WorkspaceStore] mirror create failed: \(error.localizedDescription) for \(url.path)")
            return false
        }
    }

    public func save() {
        do {
            try fileManager.createDirectory(
                at: stateDirURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateFileURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateFileURL.path)
        } catch {
            NSLog("[WorkspaceStore] save failed: \(error.localizedDescription)")
        }
    }

    /// Migrate older versions in place. v0 (pre-versioning) is
    /// treated as v1 with no data — projects and remote hosts
    /// start empty. Future versions go here.
    private func migrate(_ loaded: WorkspaceState) -> WorkspaceState {
        if loaded.version == WorkspaceState.currentVersion { return loaded }
        if loaded.version == 0 { return .empty }
        // Unknown future version: load read-only, do not downgrade.
        NSLog("[WorkspaceStore] state file is newer (v\(loaded.version)) than this build (v\(WorkspaceState.currentVersion)). Loading read-only.")
        return loaded
    }

    // MARK: - Project mutations

    public func addProject(_ p: Project) {
        // De-duplicate by `worktreeRoot` for local projects, by
        // (hostId, remotePath) for remote. Re-adding bumps
        // `lastUsedAt` and returns the existing project.
        if let existing = mergeDuplicate(of: p) {
            updateProjectLastUsed(existing.id)
            return
        }
        // Make sure the local mirror exists for a brand-new remote
        // project. codex's harness chdir's into this directory on
        // every turn.
        ensureRemoteMirrorExists(p)
        state.projects.append(p)
        state.activeProjectId = p.id
        if let hostId = p.remoteHostId {
            state.lastProjectIdByHost[hostId] = p.id
        }
        save()
    }

    /// Returns the existing project that already represents this
    /// worktree, so the UI can avoid creating duplicates when the
    /// user picks the same folder twice.
    private func mergeDuplicate(of candidate: Project) -> Project? {
        if candidate.kind == .local {
            return state.projects.first(where: {
                $0.kind == .local &&
                $0.worktreeRoot.standardizedFileURL.path ==
                candidate.worktreeRoot.standardizedFileURL.path
            })
        }
        if candidate.kind == .remote,
           let hostId = candidate.remoteHostId,
           let remotePath = candidate.remotePath {
            return state.projects.first(where: {
                $0.kind == .remote &&
                $0.remoteHostId == hostId &&
                $0.remotePath == remotePath
            })
        }
        return nil
    }

    public func updateProjectLastUsed(_ id: String) {
        guard let idx = state.projects.firstIndex(where: { $0.id == id }) else { return }
        state.projects[idx].lastUsedAt = Date()
        save()
    }

    public func removeProject(_ id: String) {
        state.projects.removeAll { $0.id == id }
        if state.activeProjectId == id { state.activeProjectId = nil }
        for (k, v) in state.lastProjectIdByHost where v == id {
            state.lastProjectIdByHost[k] = nil
        }
        save()
    }

    public func renameProject(_ id: String, to newName: String) {
        guard !newName.isEmpty,
              let idx = state.projects.firstIndex(where: { $0.id == id }) else { return }
        state.projects[idx].displayName = newName
        save()
    }

    /// Replace a project's editable fields in place (name, primary folder,
    /// extra source folders) and persist. Preserves `id` / timestamps.
    public func updateProject(_ updated: Project) {
        guard let idx = state.projects.firstIndex(where: { $0.id == updated.id }) else { return }
        state.projects[idx].displayName = updated.displayName
        state.projects[idx].worktreeRoot = updated.worktreeRoot
        state.projects[idx].sourceFolders = updated.sourceFolders
        state.projects[idx].bookmark = updated.bookmark
        updateProjectLastUsed(updated.id)
        save()
    }

    public func togglePinProject(_ id: String) {
        if pinnedProjectIds.contains(id) {
            pinnedProjectIds.remove(id)
        } else {
            pinnedProjectIds.insert(id)
        }
    }
    public func isProjectPinned(_ id: String) -> Bool {
        pinnedProjectIds.contains(id)
    }

    public func setActiveProject(_ id: String?) {        state.activeProjectId = id
        if let id = id {
            updateProjectLastUsed(id)
        } else {
            save()
        }
    }

    // MARK: - Remote host mutations

    public func addRemoteHost(_ h: RemoteHost) {
        if state.remoteHosts.contains(where: { $0.id == h.id }) { return }
        state.remoteHosts.append(h)
        save()
    }

    public func updateRemoteHost(_ h: RemoteHost) {
        guard let idx = state.remoteHosts.firstIndex(where: { $0.id == h.id }) else { return }
        state.remoteHosts[idx] = h
        save()
    }

    public func removeRemoteHost(_ id: String) {
        state.remoteHosts.removeAll { $0.id == id }
        // Cascade: any project bound to this host becomes "dangling".
        for i in state.projects.indices where state.projects[i].remoteHostId == id {
            state.projects[i].remoteHostId = nil
            state.projects[i].kind = .local
        }
        if let active = state.activeProjectId,
           let idx = state.projects.firstIndex(where: { $0.id == active }),
           state.projects[idx].remoteHostId == nil {
            // keep selection; user just sees it as local now
        }
        state.lastProjectIdByHost[id] = nil
        save()
    }

    // MARK: - Queries

    public func project(byId id: String) -> Project? {
        state.projects.first(where: { $0.id == id })
    }
    public func remoteHost(byId id: String) -> RemoteHost? {
        state.remoteHosts.first(where: { $0.id == id })
    }
    /// Most-recently-used projects first.
    public var recentProjects: [Project] {
        state.projects.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
}
