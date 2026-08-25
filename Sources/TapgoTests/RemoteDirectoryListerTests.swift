// TapgoTests/RemoteDirectoryListerTests.swift
import Foundation
@testable import TapgoCore

// MARK: - argv shape (pure)

@MainActor
func runRemoteDirListerArgvShape(_ t: TestRunner) {
    let ssh = "/usr/bin/ssh"
    let host = RemoteHost(
        id: "h", alias: "jk", host: "203.0.113.10",
        user: "remoteuser", port: 22,
        identityHint: nil, addedAt: Date()
    )

    // Happy path — typical absolute path.
    let argv = try! RemoteCommandBuilder.buildListDirArgv(
        sshPath: ssh, host: host, remotePath: "/Users/remoteuser")
    t.expectEqual(argv[0], ssh, "argv[0] is the ssh binary")
    t.expectEqual(argv.contains("-o"), true, "argv uses -o options")
    t.expectEqual(argv.contains("BatchMode=yes"), true, "BatchMode=yes present")
    t.expectEqual(argv.contains("ConnectTimeout=8"), true, "ConnectTimeout=8 present")
    t.expectEqual(argv.contains("StrictHostKeyChecking=accept-new"), true,
                  "StrictHostKeyChecking=accept-new present")
    t.expectEqual(argv.contains("remoteuser@203.0.113.10"), true,
                  "user@host concatenated as a single argv entry")
    // The remote command is the LAST entry. It must contain
    // `cd <path> && ls -1Ap` so the ls runs *after* the cd and
    // is therefore guaranteed to mean "list current directory"
    // on the remote host, not "list the path as a positional
    // argument" (which would let a hostile `ls` wrapper
    // interpret it).
    let last = argv.last ?? ""
    t.expectEqual(last.contains("cd /Users/remoteuser"), true,
                  "remote command starts with `cd <path>`")
    t.expectEqual(last.contains("ls -1Ap"), true,
                  "remote command includes `ls -1Ap`")
    t.expectEqual(last.contains("&&"), true,
                  "remote command joins cd and ls with &&")

    // `~` is allowed (validated) and passes through verbatim —
    // the remote shell will expand it.
    let argvTilde = try! RemoteCommandBuilder.buildListDirArgv(
        sshPath: ssh, host: host, remotePath: "~")
    t.expectEqual(argvTilde.last?.contains("cd ~"), true,
                  "~ passes through to the remote shell")

    // Reject path with shell metacharacters.
    do {
        _ = try RemoteCommandBuilder.buildListDirArgv(
            sshPath: ssh, host: host, remotePath: "/tmp; rm -rf /")
        t.expect(false, "expected invalidPath for shell metacharacter path")
    } catch let e as RemoteCommandBuilder.BuildError {
        t.expectEqual(e, .invalidPath, "rejects shell metacharacter in path")
    } catch {
        t.expect(false, "unexpected error type: \(error)")
    }

    // Reject empty path.
    do {
        _ = try RemoteCommandBuilder.buildListDirArgv(
            sshPath: ssh, host: host, remotePath: "")
        t.expect(false, "expected invalidPath for empty path")
    } catch let e as RemoteCommandBuilder.BuildError {
        t.expectEqual(e, .invalidPath, "rejects empty path")
    } catch {
        t.expect(false, "unexpected error type: \(error)")
    }

    // Reject bad host (contains space).
    let badHost = RemoteHost(
        id: "h", alias: "jk", host: "203.0.113.10 22",
        user: "remoteuser", port: 22,
        identityHint: nil, addedAt: Date()
    )
    do {
        _ = try RemoteCommandBuilder.buildListDirArgv(
            sshPath: ssh, host: badHost, remotePath: "/Users/remoteuser")
        t.expect(false, "expected invalidHost")
    } catch let e as RemoteCommandBuilder.BuildError {
        t.expectEqual(e, .invalidHost, "rejects bad host")
    } catch {
        t.expect(false, "unexpected error type: \(error)")
    }

    // Reject bad user.
    let badUser = RemoteHost(
        id: "h", alias: "jk", host: "203.0.113.10",
        user: "chan laiyi", port: 22,
        identityHint: nil, addedAt: Date()
    )
    do {
        _ = try RemoteCommandBuilder.buildListDirArgv(
            sshPath: ssh, host: badUser, remotePath: "/Users/remoteuser")
        t.expect(false, "expected invalidUser")
    } catch let e as RemoteCommandBuilder.BuildError {
        t.expectEqual(e, .invalidUser, "rejects bad user")
    } catch {
        t.expect(false, "unexpected error type: \(error)")
    }
}

// MARK: - end-to-end: list on remotehost

@MainActor
func runRemoteDirListerLive(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    let host = RemoteHost(
        id: "h", alias: "jk", host: "203.0.113.10",
        user: "remoteuser", port: 22,
        identityHint: nil, addedAt: Date()
    )
    let lister = RemoteDirectoryLister()
    do {
        // 1) Home directory: should contain well-known
        // sub-directories like `Library`, `Documents`, etc.
        // We don't assert on a fixed list (different macs may
        // differ) but we do require the call to succeed and
        // return at least one entry.
        let home = try await lister.listDirectories(
            sshPath: RemoteCodexHomeSync.findSSH(),
            host: host, path: "~"
        )
        t.expect(home.count > 0,
                  "remote home directory: at least one entry, got \(home.count) (\(home.prefix(5).map(\.id).joined(separator: ", ")))")

        // 2) /etc should be a directory on any unix; the
        // listing should return sub-dirs like `ssh` or
        // `security`. We require non-empty and zero failure.
        let etc = try await lister.listDirectories(
            sshPath: RemoteCodexHomeSync.findSSH(),
            host: host, path: "/etc"
        )
        t.expect(etc.count > 0, "remote /etc lists sub-directories")

        // 3) Non-existent path must surface as a typed error,
        // not a crash. We use a path that no real user has.
        do {
            _ = try await lister.listDirectories(
                sshPath: RemoteCodexHomeSync.findSSH(),
                host: host,
                path: "/this/does/not/exist/tapgo-test-\(UUID().uuidString)"
            )
            t.expect(false, "expected error for non-existent path")
        } catch let e as RemoteDirectoryLister.ListError {
            switch e {
            case .remoteNotDirectory, .sshFailed:
                t.expect(true, "non-existent path raises typed error: \(e)")
            default:
                t.expect(false, "wrong error type: \(e)")
            }
        } catch {
            t.expect(false, "non-typed error: \(error)")
        }
    } catch {
        t.expect(false, "remote list failed: \(error)")
    }
}
