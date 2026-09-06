import Foundation
import TapgoCore

// Explicit opt-in: real SSH + app-server command/exec, without a model turn
// or account credentials. Arguments: user host remote path expected absolute cwd.
@main struct RemoteProtocolCheck {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 5 else { fatalError("usage: check <user> <host> <remote-path> <expected-cwd>") }
        let host = RemoteHost(id: "verify", alias: "verify", host: args[2], user: args[1], port: 22, addedAt: Date())
        let remoteHome = "/tmp/tapgo-remote-check-" + UUID().uuidString
        let transport = RemoteSSHHarnessTransport(
            sshPath: "/usr/bin/ssh", host: host, remoteCodexHome: remoteHome,
            apiKey: "tapgo-protocol-fixture-not-a-credential", workingDirectory: args[3],
            runtimeOverrides: RemoteCodexHomeSync.runtimeOverrides(
                model: "gpt-5.4", provider: "tapgo_probe", baseURL: "http://127.0.0.1:9/v1", contextWindow: 200_000))
        defer { transport.stop() }
        func rpc(_ id: Int, _ method: String, _ params: [String: JSONValue]) async throws -> JSONValue {
            try transport.send(frame: .object(["id": .int(id), "method": .string(method), "params": .object(params)]))
            let deadline = Date().addingTimeInterval(25)
            while Date() < deadline {
                if let frame = transport.collectedFrames.first(where: { $0.objectValue?["id"]?.intOrBoolAsInt == id }) {
                    guard frame.objectValue?["error"] == nil, let result = frame.objectValue?["result"] else {
                        throw NSError(domain: "RPC \(method)", code: 1)
                    }
                    return result
                }
                if let failure = transport.startupFailure { throw NSError(domain: failure, code: 2) }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw NSError(domain: "RPC timeout: \(method)", code: 3)
        }
        try transport.start()
        _ = try await rpc(1, "initialize", ["clientInfo": .object(["name": .string("tapgo_verify"), "version": .string("1")])])
        try transport.send(frame: .object(["method": .string("initialized")]))
        guard transport.keyReceivedConfirmed, transport.resolvedWorkingDirectory == args[4] else {
            throw NSError(domain: "remote cwd/key delivery mismatch", code: 4)
        }
        let result = try await rpc(2, "command/exec", [
            "command": .array([.string("/bin/sh"), .string("-c"), .string("hostname; pwd; git remote get-url origin")]),
            "cwd": .string(transport.resolvedWorkingDirectory!),
            "timeoutMs": .int(10000),
            "sandboxPolicy": .object(["type": .string("readOnly")])
        ])
        guard result.objectValue?["exitCode"]?.intOrBoolAsInt == 0,
              result.objectValue?["stdout"]?.stringValue?.contains(args[4]) == true else {
            throw NSError(domain: "command execution mismatch", code: 5)
        }
        print("PASS: SSH initialize, dummy-key delivery, resolved cwd, remote command/exec")
        print(result.objectValue?["stdout"]?.stringValue ?? "")
        await transport.stopAndWait()
        // Only this check's generated temporary home is removed.
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        cleanup.arguments = Array(try RemoteCommandBuilder.connectionArgv(sshPath: "/usr/bin/ssh", host: host).dropFirst()) + ["rm -rf -- " + RemoteCommandBuilder.shellQuote(remoteHome)]
        cleanup.standardOutput = FileHandle.nullDevice
        cleanup.standardError = FileHandle.nullDevice
        try cleanup.run()
        cleanup.waitUntilExit()
        guard cleanup.terminationStatus == 0 else { throw NSError(domain: "fixture cleanup failed", code: 6) }
    }
}
