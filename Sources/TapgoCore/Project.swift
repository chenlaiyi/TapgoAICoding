import Foundation

/// A user-curated workspace. Each thread is bound to exactly one
/// project; the project carries the cwd we feed to `thread/start`
/// and `turn/start` so model tool calls land in the right directory.
///
/// - `local`  projects point at a directory on this Mac. The path is
///   remembered as a security-scoped bookmark so a sandboxed build
///   could still re-acquire access across launches (we ship
///   un-sandboxed today, but the bookmark is the right shape to keep).
/// - `remote` projects carry a `remoteHostId` + `remotePath`. The
///   actual cwd we hand to codex is the *local* mirror path; UI
///   shows the remote target, and `RemoteExecutor` runs the same
///   command over SSH and surfaces the remote output.
public struct Project: Identifiable, Codable, Hashable {
    public let id: String
    public var displayName: String
    public var kind: Kind
    public var addedAt: Date
    public var lastUsedAt: Date
    /// The directory we hand to codex as `cwd`. For local projects this
    /// is the user-picked path; for remote projects it is the local
    /// mirror dir.
    public var worktreeRoot: URL
    /// security-scoped bookmark for the picked directory. Optional —
    /// only present when the user used NSOpenPanel.
    public var bookmark: Data?
    /// Set when `kind == .remote`.
    public var remoteHostId: String?
    public var remotePath: String?

    public init(
        id: String,
        displayName: String,
        kind: Kind,
        addedAt: Date,
        lastUsedAt: Date,
        worktreeRoot: URL,
        bookmark: Data? = nil,
        remoteHostId: String? = nil,
        remotePath: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt
        self.worktreeRoot = worktreeRoot
        self.bookmark = bookmark
        self.remoteHostId = remoteHostId
        self.remotePath = remotePath
    }

    public enum Kind: String, Codable, Hashable {
        case local
        case remote
    }

    /// Display path shown in the UI. For remote projects we *never*
    /// pretend the local mirror is the real path — we always render
    /// the remote target.
    public var displayPath: String {
        if kind == .remote, let remotePath, let host = remoteHostId {
            return "remote://\(host)\(remotePath.hasPrefix("/") ? "" : "/")\(remotePath)"
        }
        return worktreeRoot.path
    }

    /// True if this project is remote. UI uses this to draw the
    /// "remote" banner + SSH hooks.
    public var isRemote: Bool { kind == .remote }

    /// Convenience for code that needs the actual path the harness
    /// will see in `cwd`.
    public var harnessCwd: String { worktreeRoot.path }
}

/// An SSH host that a `Project(.remote)` can be bound to. We never
/// store passwords or private keys here. Authentication is delegated
/// to the user's existing `~/.ssh/config`, the macOS Keychain (via
/// `ssh-agent`), or an explicit `identityHint` pointing at a public-key
/// path (the *file path only*; the file itself is read at run-time by
/// the user's `ssh` binary).
public struct RemoteHost: Identifiable, Codable, Hashable {
    public let id: String
    public var alias: String
    public var host: String
    public var user: String
    public var port: Int
    /// One of: "default" (let ssh resolve via config + agent),
    /// "~/.ssh/<keyname>", or any other path the user types in.
    /// We do NOT store private key material; ssh-agent or the
    /// passphrased key file is the user's responsibility.
    public var identityHint: String?
    public var addedAt: Date
    public var lastTestedAt: Date?
    public var lastTestedOK: Bool?
    public var lastTestOutput: String?
    /// Where the non-sensitive remote `codex` config bundle lives.
    /// Defaults to `~/.tapgo-aicoding/remote`. The Mac pushes a
    /// `config.toml` + `model-catalogs/` here; the API key is
    /// delivered at runtime through the SSH subprocess env, never
    /// written to this directory.
    public var codexHomePath: String

    public init(
        id: String,
        alias: String,
        host: String,
        user: String,
        port: Int,
        identityHint: String? = nil,
        addedAt: Date,
        lastTestedAt: Date? = nil,
        lastTestedOK: Bool? = nil,
        lastTestOutput: String? = nil,
        codexHomePath: String = RemoteCodexHomeSync.defaultRemoteHome
    ) {
        self.id = id
        self.alias = alias
        self.host = host
        self.user = user
        self.port = port
        self.identityHint = identityHint
        self.addedAt = addedAt
        self.lastTestedAt = lastTestedAt
        self.lastTestedOK = lastTestedOK
        self.lastTestOutput = lastTestOutput
        self.codexHomePath = codexHomePath
    }

    /// Returns a list of candidate CLI argument arrays that
    /// `RemoteCommandBuilder` will try in order, stopping at the
    /// first one that ssh accepts. The `host` and `user` are
    /// *separately validated* by the caller; do NOT trust user-
    /// supplied `alias`/`identityHint` for path-of-ssh invocation.
    public static let probeSSHCommand = "/bin/sh -c 'command -v ssh'"

    /// Shell-quoted, escape-aware command used to *test* the host.
    /// We run `ssh -p <port> [-i <id>] <user>@<host> 'pwd && uname -a'`
    /// with strict argv construction (no shell interpolation).
    public static func probeCommand(
        sshPath: String, port: Int, user: String, host: String,
        identityHint: String?
    ) -> [String] {
        var args: [String] = [sshPath]
        if port != 22 {
            args += ["-p", String(port)]
        }
        if let id = identityHint, !id.isEmpty, id != "default" {
            args += ["-i", id]
        }
        args += ["-o", "BatchMode=yes"]
        args += ["-o", "ConnectTimeout=8"]
        args += ["-o", "StrictHostKeyChecking=accept-new"]
        args += ["\(user)@\(host)", "pwd; uname -a"]
        return args
    }
}

/// Persistent store for projects + remote hosts + active selection.
/// Versioned so we can migrate in flight.
public struct WorkspaceState: Codable, Equatable {
    public static let currentVersion: Int = 1

    public var version: Int
    public var projects: [Project]
    public var remoteHosts: [RemoteHost]
    public var activeProjectId: String?
    /// last project id used for a given remote host id, so re-opening
    /// a host jumps back to where you were.
    public var lastProjectIdByHost: [String: String]

    public init(
        version: Int,
        projects: [Project],
        remoteHosts: [RemoteHost],
        activeProjectId: String?,
        lastProjectIdByHost: [String: String]
    ) {
        self.version = version
        self.projects = projects
        self.remoteHosts = remoteHosts
        self.activeProjectId = activeProjectId
        self.lastProjectIdByHost = lastProjectIdByHost
    }

    public static let empty = WorkspaceState(
        version: WorkspaceState.currentVersion,
        projects: [],
        remoteHosts: [],
        activeProjectId: nil,
        lastProjectIdByHost: [:]
    )

    public var activeProject: Project? {
        guard let id = activeProjectId else { return nil }
        return projects.first(where: { $0.id == id })
    }
}
