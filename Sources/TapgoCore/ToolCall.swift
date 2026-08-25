import Foundation

/// A generic tool call.
public struct ToolCall: Identifiable, Hashable, Codable {
    public let id: String
    public var name: String
    public var arguments: String
    public var result: String?
    public var status: Status

    public enum Status: String, Hashable, Codable {
        case pending
        case awaitingApproval
        case running
        case succeeded
        case failed
        case denied
    }

    public init(id: String, name: String, arguments: String, result: String? = nil, status: Status) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
        self.status = status
    }
}

/// A shell command the agent wants to run. `viaSSH` is set when
/// `RemoteExecutor` reran the command over SSH for a remote project
/// — UI uses it to label the cell "via SSH <alias>".
public struct CommandExecution: Identifiable, Hashable, Codable {
    public let id: String
    public var command: String
    public var cwd: String?
    public var status: Status
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var startedAt: Date
    public var completedAt: Date?
    /// Optional. Present iff the command was re-executed over SSH
    /// (Remote project). UI shows a small badge.
    public var viaSSH: String?

    public enum Status: String, Hashable, Codable {
        case pending
        case awaitingApproval
        case running
        case succeeded
        case failed
        case denied
    }

    public init(
        id: String,
        command: String,
        cwd: String? = nil,
        status: Status = .pending,
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32? = nil,
        startedAt: Date,
        completedAt: Date? = nil,
        viaSSH: String? = nil
    ) {
        self.id = id
        self.command = command
        self.cwd = cwd
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.viaSSH = viaSSH
    }
}

/// File change item.
public struct FileChange: Identifiable, Hashable, Codable {
    public enum Kind: String, Hashable, Codable { case create, update, delete }
    public let id: String
    public var kind: Kind
    public var path: String
    public var diff: String
    public var status: Status

    public enum Status: String, Hashable, Codable {
        case pending
        case awaitingApproval
        case applied
        case failed
        case denied
    }

    public init(id: String, kind: Kind, path: String, diff: String = "", status: Status = .pending) {
        self.id = id
        self.kind = kind
        self.path = path
        self.diff = diff
        self.status = status
    }
}
