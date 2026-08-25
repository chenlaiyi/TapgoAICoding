// TapgoTests/WorkspaceStoreTests.swift
import Foundation
import TapgoCore

@MainActor
func makeHostForTest(id: String = "host-remotehost") -> RemoteHost {
    RemoteHost(id: id, alias: "remotehost", host: "203.0.113.10", user: "remoteuser",
               port: 22, addedAt: Date(timeIntervalSince1970: 0))
}

@MainActor
func makeRemoteProjectForTest(id: String, hostId: String = "host-remotehost", path: String = "/Users/remoteuser", alias: String = "remotehost") -> Project {
    let parent = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Tapgo AICoding/mirrors", isDirectory: true)
    let sanitizedAlias = alias.replacingOccurrences(of: "/", with: "_")
    let sanitizedPath = path.replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    let mirror = parent.appendingPathComponent("\(sanitizedAlias)__\(sanitizedPath)", isDirectory: true)
    return Project(
        id: id, displayName: "\(alias):~/" + path,
        kind: .remote, addedAt: Date(), lastUsedAt: Date(),
        worktreeRoot: mirror, remoteHostId: hostId, remotePath: path
    )
}

@MainActor
func runWorkspaceStoreLoadFresh(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ws-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = WorkspaceStore(testDirectory: tmp)
    t.expectEqual(store.state.projects.isEmpty, true, "fresh: no projects")
    t.expectEqual(store.state.remoteHosts.isEmpty, true, "fresh: no remote hosts")
    t.expectNil(store.state.activeProjectId, "fresh: no active project")
}

@MainActor
func runWorkspaceStoreAddProjectDedup(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ws-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = WorkspaceStore(testDirectory: tmp)
    store.addRemoteHost(makeHostForTest())
    let p1 = makeRemoteProjectForTest(id: "p1", path: "/Users/remoteuser")
    store.addProject(p1)
    t.expectEqual(store.state.projects.count, 1, "after first add: 1 project")
    t.expectEqual(store.state.activeProjectId, "p1", "first add sets activeProjectId")
    let p1again = makeRemoteProjectForTest(id: "p1", path: "/Users/remoteuser")
    store.addProject(p1again)
    t.expectEqual(store.state.projects.count, 1, "duplicate add: still 1 project")
    let p2 = makeRemoteProjectForTest(id: "p2", path: "/Users/remoteuser/work")
    store.addProject(p2)
    t.expectEqual(store.state.projects.count, 2, "different path: 2 projects")
}

@MainActor
func runWorkspaceStoreEnsureRemoteMirrorExists(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ws-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = WorkspaceStore(testDirectory: tmp)
    store.addRemoteHost(makeHostForTest())
    let project = makeRemoteProjectForTest(id: "mirror-1", path: "/Users/remoteuser/mirror-test-\(UUID().uuidString)")
    store.addProject(project)
    let mirrorURL = project.worktreeRoot
    var isDir: ObjCBool = false
    t.expectEqual(FileManager.default.fileExists(atPath: mirrorURL.path, isDirectory: &isDir), true,
                  "mirror dir: exists")
    t.expectEqual(isDir.boolValue, true, "mirror dir: is a directory")
    let marker = mirrorURL.appendingPathComponent(".tapgo-mirror")
    t.expectEqual(FileManager.default.fileExists(atPath: marker.path), true,
                  "mirror dir: .tapgo-mirror marker exists")
    if let attrs = try? FileManager.default.attributesOfItem(atPath: mirrorURL.path),
       let perm = (attrs[.posixPermissions] as? NSNumber)?.intValue {
        t.expectEqual(perm & 0o777, 0o755, "mirror dir: 0755 permissions")
    } else {
        t.expect(false, "mirror dir: could not stat permissions")
    }
    let ok = store.ensureRemoteMirrorExists(project)
    t.expectEqual(ok, true, "ensureRemoteMirrorExists is idempotent (returns true)")
}

@MainActor
func runWorkspaceStoreLoadAfterSave(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ws-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = WorkspaceStore(testDirectory: tmp)
    store.addRemoteHost(makeHostForTest())
    let p1 = makeRemoteProjectForTest(id: "p1", path: "/Users/remoteuser/rt-\(UUID().uuidString)")
    store.addProject(p1)
    store.save()
    if let attrs = try? FileManager.default.attributesOfItem(atPath: store.stateFileURL.path),
       let perm = (attrs[.posixPermissions] as? NSNumber)?.intValue {
        t.expectEqual(perm & 0o777, 0o600, "workspace.json: 0600 permissions")
    } else {
        t.expect(false, "workspace.json: could not stat permissions")
    }
    let store2 = WorkspaceStore(testDirectory: tmp)
    t.expectEqual(store2.state.projects.count, 1, "reload: 1 project")
    t.expectEqual(store2.state.remoteHosts.count, 1, "reload: 1 remote host")
    t.expectEqual(store2.state.activeProjectId, "p1", "reload: activeProjectId preserved")
}

@MainActor
func runWorkspaceStoreRemoveProject(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ws-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = WorkspaceStore(testDirectory: tmp)
    store.addRemoteHost(makeHostForTest())
    let p1 = makeRemoteProjectForTest(id: "p1", path: "/Users/remoteuser/rm-\(UUID().uuidString)")
    store.addProject(p1)
    t.expectEqual(store.state.activeProjectId, "p1", "active = p1")
    store.removeProject("p1")
    t.expectEqual(store.state.projects.count, 0, "removeProject: project gone")
    t.expectNil(store.state.activeProjectId, "removeProject: activeProjectId cleared when active was removed")
}

@MainActor
func runWorkspaceStoreRemoveRemoteHostCascade(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ws-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = WorkspaceStore(testDirectory: tmp)
    let host = makeHostForTest(id: "host-cascade")
    store.addRemoteHost(host)
    let p1 = makeRemoteProjectForTest(id: "p1", hostId: "host-cascade",
                                      path: "/Users/foo/cascade-\(UUID().uuidString)", alias: "cascade")
    store.addProject(p1)
    t.expectEqual(store.state.projects[0].kind, .remote, "before: project is remote")
    store.removeRemoteHost("host-cascade")
    let after = store.state.projects[0]
    t.expectEqual(after.kind, .local, "after cascade: project is local")
    t.expectNil(after.remoteHostId, "after cascade: remoteHostId cleared")
}
