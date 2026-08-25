// TapgoTests/ProjectTests.swift

import Foundation
import TapgoCore

@MainActor
func runProjectDisplayPathHarnessCwd(_ t: TestRunner) {
    let local = Project(
        id: "local-1", displayName: "CPA", kind: .local,
        addedAt: Date(timeIntervalSince1970: 0), lastUsedAt: Date(timeIntervalSince1970: 0),
        worktreeRoot: URL(fileURLWithPath: "/Users/alice/CPA")
    )
    t.expectEqual(local.displayPath, "/Users/alice/CPA", "local.displayPath = worktreeRoot.path")
    t.expectEqual(local.harnessCwd, "/Users/alice/CPA", "local.harnessCwd = worktreeRoot.path")
    t.expectEqual(local.isRemote, false, "local.isRemote = false")

    let mirror = URL(fileURLWithPath: "/tmp/mirror-abc")
    let remote = Project(
        id: "remote-1", displayName: "remotehost:~/", kind: .remote,
        addedAt: Date(timeIntervalSince1970: 0), lastUsedAt: Date(timeIntervalSince1970: 0),
        worktreeRoot: mirror,
        remoteHostId: "host-remotehost", remotePath: "/Users/remoteuser"
    )
    t.expectEqual(remote.isRemote, true, "remote.isRemote = true")
    t.expectEqual(remote.displayPath, "remote://host-remotehost/Users/remoteuser",
                  "remote.displayPath uses remote target, NOT mirror")
    t.expectEqual(remote.harnessCwd, "/tmp/mirror-abc",
                  "remote.harnessCwd = local mirror (the cwd the harness actually sees)")
    t.expectNotEqual(remote.displayPath, remote.harnessCwd,
                     "remote.displayPath != harnessCwd (no fake-cwd rule)")

    let remoteNoSlash = Project(
        id: "remote-2", displayName: "remotehost:home", kind: .remote,
        addedAt: Date(timeIntervalSince1970: 0), lastUsedAt: Date(timeIntervalSince1970: 0),
        worktreeRoot: mirror,
        remoteHostId: "host-remotehost", remotePath: "home/remoteuser"
    )
    t.expectEqual(remoteNoSlash.displayPath, "remote://host-remotehost/home/remoteuser",
                  "remote displayPath with no leading slash still has slash")
}

@MainActor
func runProjectCodableRoundTrip(_ t: TestRunner) {
    let mirror = URL(fileURLWithPath: "/tmp/mirror-abc")
    let remote = Project(
        id: "remote-1", displayName: "remotehost:~/", kind: .remote,
        addedAt: Date(timeIntervalSince1970: 0), lastUsedAt: Date(timeIntervalSince1970: 0),
        worktreeRoot: mirror,
        remoteHostId: "host-remotehost", remotePath: "/Users/remoteuser"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let decoder = JSONDecoder()
    do {
        let data = try encoder.encode(remote)
        let decoded = try decoder.decode(Project.self, from: data)
        t.expectEqual(decoded.id, remote.id, "Codable: id round-trips")
        t.expectEqual(decoded.kind, .remote, "Codable: kind round-trips")
        t.expectEqual(decoded.worktreeRoot, mirror, "Codable: worktreeRoot round-trips")
        t.expectEqual(decoded.remoteHostId, "host-remotehost", "Codable: remoteHostId round-trips")
        t.expectEqual(decoded.remotePath, "/Users/remoteuser", "Codable: remotePath round-trips")
    } catch {
        t.expect(false, "Project Codable round-trip failed: \(error)")
    }
}

@MainActor
func runRemoteHostProbeArgv(_ t: TestRunner) {
    let host = RemoteHost(
        id: "host-remotehost", alias: "remotehost",
        host: "203.0.113.10", user: "remoteuser", port: 22,
        identityHint: nil,
        addedAt: Date(timeIntervalSince1970: 0)
    )
    let probe = RemoteHost.probeCommand(
        sshPath: "/usr/bin/ssh", port: host.port,
        user: host.user, host: host.host, identityHint: host.identityHint
    )
    t.expectEqual(probe.first, "/usr/bin/ssh", "probe[0] = ssh path")
    t.expectEqual(probe.contains("remoteuser@203.0.113.10"), true, "probe has user@host")
    t.expectEqual(probe.contains("BatchMode=yes"), true, "probe has BatchMode")
    t.expectEqual(probe.contains("pwd; uname -a"), true, "probe has pwd; uname -a")
    let probeNonDefault = RemoteHost.probeCommand(
        sshPath: "/usr/bin/ssh", port: 2222,
        user: "alice", host: "10.0.0.1", identityHint: nil
    )
    t.expectEqual(probeNonDefault.contains("-p"), true, "non-22 port adds -p")
    t.expectEqual(probeNonDefault.contains("2222"), true, "non-22 port value present")
}

@MainActor
func runWorkspaceStateVersionAndActive(_ t: TestRunner) {
    let state = WorkspaceState(
        version: WorkspaceState.currentVersion,
        projects: [
            Project(id: "p1", displayName: "P1", kind: .local,
                    addedAt: Date(), lastUsedAt: Date(),
                    worktreeRoot: URL(fileURLWithPath: "/p1"))
        ],
        remoteHosts: [],
        activeProjectId: "p1",
        lastProjectIdByHost: [:]
    )
    t.expectEqual(state.activeProject?.id, "p1", "activeProject lookup works")
    t.expectEqual(state.activeProject?.displayName, "P1", "activeProject.displayName")
    t.expectEqual(WorkspaceState.empty.projects.isEmpty, true, "WorkspaceState.empty is empty")
    t.expectNil(WorkspaceState.empty.activeProject, "WorkspaceState.empty has no active project")
    t.expectEqual(WorkspaceState.currentVersion, 1, "currentVersion = 1")
}
