// TapgoTests/RemoteCommandBuilderTests.swift
//
// Verifies the safe-by-construction SSH argv builder. These are
// critical — every shell command we ever run on a remote host goes
// through `RemoteCommandBuilder.buildSshArgv`. A bug here is a
// remote-code-execution vector.

import Foundation
import TapgoCore

private func makeHost(
    alias: String = "remotehost",
    host: String = "203.0.113.10",
    user: String = "remoteuser",
    port: Int = 22,
    identityHint: String? = nil
) -> RemoteHost {
    RemoteHost(
        id: "host-remotehost",
        alias: alias,
        host: host,
        user: user,
        port: port,
        identityHint: identityHint,
        addedAt: Date(timeIntervalSince1970: 0),
        lastTestedAt: nil,
        lastTestedOK: nil,
        lastTestOutput: nil
    )
}

@MainActor
func runRemoteCommandBuilderInputValidation(_ t: TestRunner) {
    // path validation
    t.expectNotNil(RemoteCommandBuilder.validatePath("/Users/remoteuser"), "path: absolute ok")
    t.expectNotNil(RemoteCommandBuilder.validatePath("./rel/dir"), "path: relative ok")
    t.expectNotNil(RemoteCommandBuilder.validatePath("~/projects/x"), "path: tilde ok")
    t.expectNil(RemoteCommandBuilder.validatePath("/etc; rm -rf /"), "path: rejects ;")
    t.expectNil(RemoteCommandBuilder.validatePath("/etc && cat /etc/shadow"), "path: rejects &&")
    t.expectNil(RemoteCommandBuilder.validatePath("$(whoami)"), "path: rejects $()")
    t.expectNil(RemoteCommandBuilder.validatePath("/etc\nls"), "path: rejects newline")
    t.expectNil(RemoteCommandBuilder.validatePath("/etc\rls"), "path: rejects carriage return")
    t.expectNil(RemoteCommandBuilder.validatePath(""), "path: rejects empty")
    t.expectNil(RemoteCommandBuilder.validatePath(String(repeating: "a", count: 5000)), "path: rejects overlong")
    t.expectNil(RemoteCommandBuilder.validatePath("/path\0null"), "path: rejects NUL")

    // host validation
    t.expectNotNil(RemoteCommandBuilder.validateHost("203.0.113.10"), "host: IPv4 ok")
    t.expectNotNil(RemoteCommandBuilder.validateHost("remotehost.local"), "host: name ok")
    t.expectNotNil(RemoteCommandBuilder.validateHost("my-host.example.com"), "host: dashed name ok")
    t.expectNil(RemoteCommandBuilder.validateHost("203.0.113.10; rm"), "host: rejects ;")
    t.expectNil(RemoteCommandBuilder.validateHost("`host`"), "host: rejects backticks")
    t.expectNil(RemoteCommandBuilder.validateHost("host && bad"), "host: rejects &&")
    t.expectNil(RemoteCommandBuilder.validateHost(""), "host: rejects empty")
    t.expectNil(RemoteCommandBuilder.validateHost("host\nfoo"), "host: rejects newline")

    // user validation
    t.expectNotNil(RemoteCommandBuilder.validateUser("remoteuser"), "user: plain ok")
    t.expectNotNil(RemoteCommandBuilder.validateUser("u.name"), "user: dot ok")
    t.expectNotNil(RemoteCommandBuilder.validateUser("u-name"), "user: dash ok")
    t.expectNil(RemoteCommandBuilder.validateUser("u; cat"), "user: rejects ;")
    t.expectNil(RemoteCommandBuilder.validateUser("u\nrm"), "user: rejects newline")
    t.expectNil(RemoteCommandBuilder.validateUser(""), "user: rejects empty")

    // command validation
    t.expectNotNil(RemoteCommandBuilder.validateCommand("pwd"), "command: simple ok")
    t.expectNotNil(RemoteCommandBuilder.validateCommand("ls -la /Users/remoteuser"), "command: with args ok")
    t.expectNil(RemoteCommandBuilder.validateCommand("ls\nrm -rf /"), "command: rejects newline")
    t.expectNil(RemoteCommandBuilder.validateCommand(""), "command: rejects empty")
    t.expectNil(RemoteCommandBuilder.validateCommand(String(repeating: "x", count: 70_000)), "command: rejects overlong")
}

@MainActor
func runRemoteCommandBuilderBuildSshArgvShape(_ t: TestRunner) {
    let h = makeHost()
    do {
        let argv = try RemoteCommandBuilder.buildSshArgv(
            sshPath: "/usr/bin/ssh",
            host: h,
            remotePath: "/Users/remoteuser",
            modelCommand: "pwd"
        )
        t.expectEqual(argv[0], "/usr/bin/ssh", "argv[0] = ssh path")
        t.expectEqual(argv.contains("-o"), true, "argv includes -o options")
        t.expectEqual(argv.contains("BatchMode=yes"), true, "argv includes BatchMode=yes")
        t.expectEqual(argv.contains(where: { $0.hasPrefix("ConnectTimeout=") }), true, "argv includes ConnectTimeout")
        t.expectEqual(argv.contains("StrictHostKeyChecking=accept-new"), true, "argv includes StrictHostKeyChecking=accept-new")
        t.expectEqual(argv.contains("remoteuser@203.0.113.10"), true, "argv has user@host")
        let remoteCmd = argv.last ?? ""
        t.expectEqual(remoteCmd.contains("/Users/remoteuser"), true, "remote command references remote path")
        t.expectEqual(remoteCmd.contains("pwd"), true, "remote command references the command")
        let joined = argv.joined(separator: "\u{1f}")
        t.expectEqual(joined.contains("\n"), false, "argv has no embedded newline")
        t.expectEqual(joined.contains("`"), false, "argv has no backticks")
    } catch {
        t.expect(false, "buildSshArgv must succeed: \(error)")
    }
}

@MainActor
func runRemoteCommandBuilderBuildSshArgvRejects(_ t: TestRunner) {
    t.expectThrows({
        _ = try RemoteCommandBuilder.buildSshArgv(
            sshPath: "/usr/bin/ssh",
            host: makeHost(),
            remotePath: "/Users/remoteuser; rm -rf /",
            modelCommand: "pwd"
        )
    }, "buildSshArgv rejects bad remotePath")
    t.expectThrows({
        _ = try RemoteCommandBuilder.buildSshArgv(
            sshPath: "/usr/bin/ssh",
            host: makeHost(),
            remotePath: "/Users/remoteuser",
            modelCommand: "ls\nrm -rf /"
        )
    }, "buildSshArgv rejects bad modelCommand")
    t.expectThrows({
        _ = try RemoteCommandBuilder.buildSshArgv(
            sshPath: "/usr/bin/ssh",
            host: makeHost(host: "203.0.113.10; rm"),
            remotePath: "/Users/remoteuser",
            modelCommand: "pwd"
        )
    }, "buildSshArgv rejects bad host")
    t.expectThrows({
        _ = try RemoteCommandBuilder.buildSshArgv(
            sshPath: "/usr/bin/ssh",
            host: makeHost(user: "remoteuser; cat"),
            remotePath: "/Users/remoteuser",
            modelCommand: "pwd"
        )
    }, "buildSshArgv rejects bad user")
}

@MainActor
func runRemoteCommandBuilderCommandEscaping(_ t: TestRunner) {
    do {
        let argv = try RemoteCommandBuilder.buildSshArgv(
            sshPath: "/usr/bin/ssh",
            host: makeHost(),
            remotePath: "/Users/remoteuser",
            modelCommand: "echo 'hello world'"
        )
        let lastFew = argv.suffix(3).joined(separator: " ")
        t.expectEqual(lastFew.contains("hello world"), true, "escaping preserves command text")
    } catch {
        t.expect(false, "buildSshArgv should accept a quoted command: \(error)")
    }
}
