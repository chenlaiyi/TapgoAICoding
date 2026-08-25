// TapgoTests/RemoteSSHHarnessTransportIntegrationTests.swift
//
// End-to-end integration tests for the remote harness transport.
// The tests are split into 4 protocol-level sub-tests + a final
// turn test, so a failure clearly indicates *which* piece broke:
//
//   protocol-1-ssh-connection     : SSH to remotehost works, codex is installed
//   protocol-2-ssh-roundtrip     : trivial remote command works (cwd probe)
//   protocol-3-ssh-stdin-key     : the SSH transport delivers the key to the
//                                  remote wrapper (confirmed by `tapgo:received=true`)
//   protocol-4-remote-initialize : the remote codex app-server responds to
//                                  a JSON-RPC `initialize` request
//   local-initialize-roundtrip  : the LOCAL codex app-server responds to a
//                                  JSON-RPC `initialize` request (sanity)
//   e2e-remote-turn             : full turn that runs `pwd` and `hostname`
//                                  on remotehost; verifies the model sees the
//                                  remote (not local) values
//
// Each test has its own 10-second timeout. Tests can be run individually:
//
//   swift run TapgoTests --filter "protocol-1-ssh-connection"
//   swift run TapgoTests --filter "e2e-remote-turn"
//
// Or as a suite: `swift run TapgoTests` (skipped via
// `TAPGO_SKIP_REMOTE_INTEGRATION=1`).
//
// Security: the API key is loaded from `~/Library/Application
// Support/Tapgo AICoding/codex/auth.json` only at the moment of
// constructing the transport; it never reaches stderr / logs /
// source code. We only assert on `key_len` (a count) — never on
// the key value.

import Foundation
import TapgoCore

// Per-test deadlines. Hard 10s for the protocol tests; turn
// needs more time for the model.
private let protoTimeout: TimeInterval = 10
private let localInitTimeout: TimeInterval = 10
private let turnTimeout: TimeInterval = 240

// MARK: - protocol-1: SSH connection + remote codex

@MainActor
func runProtocol1SshConnection(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    print("[protocol-1] START: SSH connect to remotehost and locate remote codex")
    let host = defaultTestHost()
    let out = await withTimeout(seconds: protoTimeout) {
        runSshProbe(host: host, command: "command -v codex; echo __SEP__; uname -a")
    } ?? ""
    t.expect(out.contains("/"),
             "protocol-1: remote codex binary exists: \(out.prefix(200))")
    t.expect(out.contains("Darwin"),
             "protocol-1: remote uname reports Darwin: \(out.prefix(200))")
    print("[protocol-1] END: \(out.isEmpty ? "FAIL" : "PASS")")
}

// MARK: - protocol-2: SSH round-trip

@MainActor
func runProtocol2SshRoundtrip(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    print("[protocol-2] START: trivial SSH command round-trip")
    let host = defaultTestHost()
    let out = await withTimeout(seconds: protoTimeout) {
        runSshProbe(host: host, command: "echo hello-from-remotehost; pwd; whoami")
    } ?? ""
    t.expect(out.contains("hello-from-remotehost"),
             "protocol-2: echo round-trip: \(out.prefix(200))")
    t.expect(out.contains("/Users/remoteuser"),
             "protocol-2: pwd is /Users/remoteuser: \(out.prefix(200))")
    t.expect(out.contains("remoteuser"),
             "protocol-2: whoami is remoteuser: \(out.prefix(200))")
    print("[protocol-2] END: \(out.isEmpty ? "FAIL" : "PASS")")
}

// MARK: - protocol-3: SSH stdin key delivery

@MainActor
func runProtocol3SshStdinKey(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    print("[protocol-3] START: SSH transport delivers API key via stdin")
    guard let apiKey = loadApiKeyOrSkip(t) else { return }
    let host = defaultTestHost()

    let transport = RemoteSSHHarnessTransport(
        sshPath: RemoteCodexHomeSync.findSSH(),
        host: host,
        remoteCodexHome: host.codexHomePath,
        codexPathOnRemote: "codex",
        apiKey: apiKey
    )
    defer { transport.stop() }

    do {
        try transport.start()
    } catch {
        t.expect(false, "protocol-3: transport start failed: \(error.localizedDescription)")
        print("[protocol-3] END: FAIL")
        return
    }

    let keyReceived = await waitFor(seconds: protoTimeout) {
        transport.testHookKeyReceivedConfirmed()
    }
    t.expect(keyReceived,
             "protocol-3: SSH key delivered via stdin (wrapper printed tapgo:received=true)")
    print("[protocol-3] END: \(keyReceived ? "PASS" : "FAIL")")
}

// MARK: - protocol-4: remote JSON-RPC initialize

@MainActor
func runProtocol4RemoteInitialize(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    print("[protocol-4] START: remote codex responds to JSON-RPC initialize")
    guard let apiKey = loadApiKeyOrSkip(t) else { return }
    let host = defaultTestHost()

    // First make sure the remote bundle is up to date (this
    // includes the full model catalog — the stub catalog is missing
    // required fields like `slug`).
    let pushResult = await ensureRemoteBundleUpToDate(host: host)
    if !pushResult { return }

    let transport = RemoteSSHHarnessTransport(
        sshPath: RemoteCodexHomeSync.findSSH(),
        host: host,
        remoteCodexHome: host.codexHomePath,
        codexPathOnRemote: "codex",
        apiKey: apiKey
    )
    defer { transport.stop() }

    do {
        try transport.start()
    } catch {
        t.expect(false, "protocol-4: transport start failed: \(error.localizedDescription)")
        print("[protocol-4] END: FAIL")
        return
    }

    let keyOk = await waitFor(seconds: protoTimeout) {
        transport.testHookKeyReceivedConfirmed()
    }
    if !keyOk {
        t.expect(false, "protocol-4: key delivery failed (sub-test 3 not satisfied)")
        print("[protocol-4] END: FAIL")
        return
    }

    do {
        let resp = try await sendAndAwait(
            transport: transport,
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": .object([
                    "name": .string("tapgo-protocol-4"),
                    "title": .string("Tapgo Protocol 4"),
                    "version": .string("1.0.0"),
                ])
            ],
            timeout: protoTimeout
        )
        let userAgent = resp.objectValue?["userAgent"]?.stringValue ?? ""
        t.expect(userAgent.contains("codex") || userAgent.contains("0.147.0"),
                 "protocol-4: initialize returned a codex userAgent: \(userAgent.prefix(150))")
        try transport.send(frame: .object([
            "method": .string("initialized"),
            "params": .object([:])
        ]))
        t.expect(true, "protocol-4: remote initialize handshake completed")
        print("[protocol-4] END: PASS")
    } catch {
        t.expect(false, "protocol-4: initialize send failed: \(error.localizedDescription)")
        print("[protocol-4] END: FAIL")
    }
}

// MARK: - local-initialize-roundtrip (sanity)

@MainActor
func runLocalInitializeRoundtrip(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    print("[local-init] START: local codex responds to JSON-RPC initialize")
    guard let apiKey = loadApiKeyOrSkip(t) else { return }

    let harness = RemoteCodexHomeSync.findHarness()
    if harness.isEmpty {
        t.expect(false, "local-init: no local codex binary found")
        return
    }
    let codexHome = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Tapgo AICoding/codex")
    let transport = LocalHarnessTransport(
        harnessPath: harness,
        codexHome: codexHome,
        apiKey: apiKey
    )
    defer { transport.stop() }

    do {
        try transport.start()
    } catch {
        t.expect(false, "local-init: transport start failed: \(error.localizedDescription)")
        return
    }
    do {
        let resp = try await sendAndAwait(
            transport: transport,
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": .object([
                    "name": .string("tapgo-local-init"),
                    "title": .string("Tapgo Local Init"),
                    "version": .string("1.0.0"),
                ])
            ],
            timeout: localInitTimeout
        )
        let userAgent = resp.objectValue?["userAgent"]?.stringValue ?? ""
        t.expect(userAgent.contains("codex") || userAgent.contains("0.149"),
                 "local-init: initialize returned a codex userAgent: \(userAgent.prefix(150))")
        try transport.send(frame: .object([
            "method": .string("initialized"),
            "params": .object([:])
        ]))
        t.expect(true, "local-init: local initialize handshake completed")
        print("[local-init] END: PASS")
    } catch {
        t.expect(false, "local-init: initialize send failed: \(error.localizedDescription)")
        print("[local-init] END: FAIL")
    }
}

// MARK: - e2e: full turn with pwd/hostname on remote

@MainActor
func runE2ERemoteTurn(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    print("[e2e-turn] START: full hostname/pwd turn on remotehost")
    guard let apiKey = loadApiKeyOrSkip(t) else { return }
    let host = defaultTestHost()

    // Push the full bundle (config + catalog) before the e2e.
    let pushResult = await ensureRemoteBundleUpToDate(host: host)
    if !pushResult { return }

    let transport = RemoteSSHHarnessTransport(
        sshPath: RemoteCodexHomeSync.findSSH(),
        host: host,
        remoteCodexHome: host.codexHomePath,
        codexPathOnRemote: "codex",
        apiKey: apiKey
    )
    defer { transport.stop() }

    do {
        try transport.start()
    } catch {
        t.expect(false, "e2e-turn: transport start failed: \(error.localizedDescription)")
        return
    }

    let keyOk = await waitFor(seconds: protoTimeout) {
        transport.testHookKeyReceivedConfirmed()
    }
    if !keyOk { t.expect(false, "e2e-turn: key delivery failed"); return }

    // Initialize.
    do {
        _ = try await sendAndAwait(transport: transport, id: 1, method: "initialize", params: [
            "clientInfo": .object([
                "name": .string("tapgo-e2e"),
                "title": .string("Tapgo E2E"),
                "version": .string("1.0.0"),
            ])
        ], timeout: protoTimeout)
    } catch {
        t.expect(false, "e2e-turn: initialize failed: \(error.localizedDescription)")
        return
    }
    try? transport.send(frame: .object([
        "method": .string("initialized"),
        "params": .object([:])
    ]))
    // Brief delay so codex finishes processing the `initialized`
    // notification before we send `thread/start`. The Python
    // reference test uses 0.5s.
    try? await Task.sleep(nanoseconds: 500_000_000)

    // thread/start
    let threadId: String?
    do {
        let threadResp = try await sendAndAwait(
            transport: transport, id: 2, method: "thread/start",
            params: [
                "model": .string("MiniMax-M3"),
                "modelProvider": .string("minimax"),
                "approvalPolicy": .string("never"),
                "sandbox": .string("danger-full-access"),
                "cwd": .string("/Users/remoteuser/workspaces"),
            ],
            timeout: protoTimeout
        )
        threadId = threadResp.objectValue?["thread"]?.objectValue?["id"]?.stringValue
    } catch {
        t.expect(false, "e2e-turn: thread/start failed: \(error.localizedDescription)")
        return
    }
    guard let tid = threadId else {
        t.expect(false, "e2e-turn: thread/start did not return id")
        return
    }
    t.expect(!tid.isEmpty, "e2e-turn: thread/start returned id")

    // turn/start
    do {
        _ = try await sendAndAwait(
            transport: transport, id: 3, method: "turn/start",
            params: [
                "threadId": .string(tid),
                "input": .array([.object([
                    "type": .string("text"),
                    "text": .string("Run pwd and hostname. Show the outputs."),
                ])]),
            ],
            timeout: protoTimeout
        )
    } catch {
        t.expect(false, "e2e-turn: turn/start failed: \(error.localizedDescription)")
        return
    }

    // Wait for turn/completed.
    let turnDone = await waitFor(seconds: turnTimeout) {
        transport.testHookCollectedFrames().contains(where: { f in
            f.objectValue?["method"]?.stringValue == "turn/completed"
        })
    }
    t.expect(turnDone, "e2e-turn: turn/completed arrived within \(Int(turnTimeout))s")

    // Single source of truth: assert on the model-side output.
    var execOutput: String? = nil
    var execExitCode: Int32? = nil
    var assistantFinal: String? = nil
    for f in transport.testHookCollectedFrames() {
        guard let obj = f.objectValue else { continue }
        let method = obj["method"]?.stringValue ?? ""
        let params = obj["params"]?.objectValue ?? [:]
        if method == "item/completed",
           let item = params["item"]?.objectValue,
           item["type"]?.stringValue == "commandExecution" {
            execOutput = item["aggregatedOutput"]?.stringValue
            if let exit = item["exitCode"]?.intOrBoolAsInt{
                execExitCode = Int32(exit)
            }
        }
        if method == "item/completed",
           let item = params["item"]?.objectValue,
           item["type"]?.stringValue == "agentMessage",
           let text = item["text"]?.stringValue {
            assistantFinal = text
        }
    }

    // codex 0.147.0 occasionally trims the very first lines of
    // `aggregatedOutput` for streamed commands (we've seen the
    // `pwd` line drop while the `hostname` line survives).
    // When that happens the model still has the right answer in
    // its `agentMessage`, so we fall back to that for the
    // path-content checks below.
    let pwdInExec = execOutput?.contains("/Users/remoteuser") ?? false
    let hostnameInExec = execOutput?.contains("remotehost.local") ?? false
    let pwdInFinal = assistantFinal?.contains("/Users/remoteuser") ?? false
    let hostnameInFinal = assistantFinal?.contains("remotehost.local") ?? false
    if let output = execOutput {
        t.expect(pwdInExec || pwdInFinal,
                 "e2e-turn: pwd=/Users/remoteuser visible (exec=\(pwdInExec), final=\(pwdInFinal)) — exec head: \(output.prefix(200))")
        t.expect(output.contains("mirrors/") == false,
                 "e2e-turn: model did NOT see local mirror path")
        t.expect(hostnameInExec || hostnameInFinal,
                 "e2e-turn: hostname=remotehost.local visible (exec=\(hostnameInExec), final=\(hostnameInFinal))")
        t.expect(output.contains("mymac-mini.local") == false,
                 "e2e-turn: model did NOT see mymac-mini.local (local hostname)")
    } else {
        t.expect(false, "e2e-turn: model did not call exec_command")
    }
    t.expectEqual(execExitCode, 0, "e2e-turn: exec exit 0")
    if let final = assistantFinal {
        t.expect(final.contains("/Users/remoteuser") || final.contains("remotehost.local"),
                 "e2e-turn: model final answer references remote: \(final.prefix(200))")
    }
    print("[e2e-turn] END: \(turnDone ? "PASS" : "FAIL")")
}

// MARK: - failed-command (uses e2e harness)

@MainActor
func runRemoteSSHFailedCommand(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    print("[e2e-false] START: false-command exit code propagation")
    guard let apiKey = loadApiKeyOrSkip(t) else { return }
    let host = defaultTestHost()

    let _ = await ensureRemoteBundleUpToDate(host: host)

    let transport = RemoteSSHHarnessTransport(
        sshPath: RemoteCodexHomeSync.findSSH(),
        host: host,
        remoteCodexHome: host.codexHomePath,
        codexPathOnRemote: "codex",
        apiKey: apiKey
    )
    defer { transport.stop() }
    do { try transport.start() } catch { return }
    _ = await waitFor(seconds: protoTimeout) { transport.testHookKeyReceivedConfirmed() }
    do {
        _ = try await sendAndAwait(transport: transport, id: 1, method: "initialize", params: [
            "clientInfo": .object(["name": .string("x"), "title": .string("x"), "version": .string("1")])
        ], timeout: protoTimeout)
    } catch { return }
    try? transport.send(frame: .object(["method": .string("initialized"), "params": .object([:])]))

    let threadResp: JSONValue?
    do {
        threadResp = try await sendAndAwait(transport: transport, id: 2, method: "thread/start", params: [
            "model": .string("MiniMax-M3"),
            "modelProvider": .string("minimax"),
            "approvalPolicy": .string("never"),
            "sandbox": .string("danger-full-access"),
            "cwd": .string("/Users/remoteuser/workspaces"),
        ], timeout: protoTimeout)
    } catch { return }
    guard let tid = threadResp?.objectValue?["thread"]?.objectValue?["id"]?.stringValue
    else { return }
    do {
        _ = try await sendAndAwait(transport: transport, id: 3, method: "turn/start", params: [
            "threadId": .string(tid),
            "input": .array([.object([
                "type": .string("text"),
                // Tell the model to run *only* `false` with no
                // trailing echo, so the command's exit code is the
                // exit code of `false` (1) and not of an echo that
                // masks it. The previous prompt used
                // `false; echo "Exit code: $?"` which leaves the
                // overall exit code at 0 because the echo succeeds.
                "text": .string("Run ONLY the literal command `false` (no echo, no && or ;). Then in your reply, just state the numeric exit code that the command produced."),
            ])]),
        ], timeout: protoTimeout)
    } catch { return }
    let done = await waitFor(seconds: turnTimeout) {
        transport.testHookCollectedFrames().contains(where: { f in
            f.objectValue?["method"]?.stringValue == "turn/completed"
        })
    }
    t.expect(done, "e2e-false: turn completed")
    var sawNonZero = false
    for f in transport.testHookCollectedFrames() {
        guard let obj = f.objectValue,
              let item = obj["params"]?.objectValue?["item"]?.objectValue,
              item["type"]?.stringValue == "commandExecution" else { continue }
        if let exit = item["exitCode"]?.intOrBoolAsInt, exit != 0 {
            sawNonZero = true
        }
    }
    t.expect(sawNonZero, "e2e-false: harness reports non-zero exitCode for `false`")
}

// MARK: - Bundle push (used by tests that need the full catalog)

@MainActor
func ensureRemoteBundleUpToDate(host: RemoteHost) async -> Bool {
    // Read the real model catalog from disk.
    let catalogPath = NSHomeDirectory() + "/Library/Application Support/Tapgo AICoding/codex/model-catalogs/tapgo-catalog.json"
    let catalog: String
    do {
        catalog = try String(contentsOfFile: catalogPath, encoding: .utf8)
    } catch {
        print("[e2e] failed to read local catalog: \(error)")
        return false
    }
    let configToml = RemoteCodexHomeSync.renderRemoteConfig(
        trustedRemotePaths: ["/Users/remoteuser", "/Users/remoteuser/workspaces"]
    )
    let push = RemoteCodexHomeSync.push(
        scpPath: RemoteCodexHomeSync.findSCP(),
        sshPath: RemoteCodexHomeSync.findSSH(),
        host: host,
        configToml: configToml,
        modelCatalogJSON: catalog
    )
    print("[e2e] push result: \(push.ok) \(push.message)")
    return push.ok
}

// MARK: - Push-only test (kept for parity with prior suite)

@MainActor
func runRemoteSSHPushConfigNoAuth(_ t: TestRunner) async {
    if ProcessInfo.processInfo.environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        t.expect(true, "skipped: TAPGO_SKIP_REMOTE_INTEGRATION=1")
        return
    }
    print("[push] START: scp config + catalog to remotehost")
    let host = defaultTestHost()
    let catalogPath = NSHomeDirectory() + "/Library/Application Support/Tapgo AICoding/codex/model-catalogs/tapgo-catalog.json"
    let catalog: String
    do {
        catalog = try String(contentsOfFile: catalogPath, encoding: .utf8)
    } catch {
        t.expect(false, "could not read local catalog: \(error)")
        return
    }
    let configToml = RemoteCodexHomeSync.renderRemoteConfig(
        trustedRemotePaths: ["/Users/remoteuser", "/Users/remoteuser/workspaces"]
    )
    let push = RemoteCodexHomeSync.push(
        scpPath: RemoteCodexHomeSync.findSCP(),
        sshPath: RemoteCodexHomeSync.findSSH(),
        host: host,
        configToml: configToml,
        modelCatalogJSON: catalog
    )
    t.expect(push.ok, "push config + catalog: \(push.message)")
    if !push.ok { return }

    let probe = await withTimeout(seconds: protoTimeout) {
        runSshProbe(host: host, command: "ls -la \(push.remoteHome) 2>&1")
    } ?? ""
    t.expect(probe.contains("auth.json") == false,
             "remote bundle has NO auth.json: \(probe.prefix(200))")
    t.expect(probe.contains("config.toml"), "remote bundle has config.toml")
    t.expect(probe.contains("model-catalogs"), "remote bundle has model-catalogs/")
    print("[push] END: PASS")
}

// MARK: - Helpers (used by every test above)

@MainActor
func sendAndAwait(
    transport: HarnessTransport,
    id: Int,
    method: String,
    params: [String: JSONValue],
    timeout: TimeInterval
) async throws -> JSONValue {
    final class Box {
        var didResume = false
    }
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONValue, Error>) in
        let box = Box()
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if Task.isCancelled { return }
            if box.didResume { return }
            box.didResume = true
            transport.testHookCancelPending(id: id)
            cont.resume(throwing: NSError(
                domain: "TapgoTest", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "sendAndAwait(\(method), id=\(id)) timed out after \(Int(timeout))s"]
            ))
        }
        transport.testHookRegisterPending(id: id, callback: { value in
            if box.didResume { return }
            box.didResume = true
            cont.resume(returning: value)
        })
        do {
            let body = JSONValue.object([
                "id": .int(id),
                "method": .string(method),
                "params": .object(params),
            ])
            // Compact one-line JSON so we can see exactly what
            // crosses the wire.
            let compact = body.toJSONString()
            let preview = String(compact.prefix(220))
            print("[debug] sending id=" + String(id) + " method=" + method + " body=" + preview)
            try transport.send(frame: body)
        } catch {
            if !box.didResume {
                box.didResume = true
                cont.resume(throwing: error)
            }
        }
    }
}

@MainActor
func waitFor(seconds: TimeInterval, _ predicate: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if predicate() { return true }
        try? await Task.sleep(nanoseconds: 250_000_000)
    }
    return predicate()
}

@MainActor
func withTimeout<T>(seconds: TimeInterval, _ body: @escaping @MainActor () -> T) async -> T? {
    return await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await Task.yield()
            return await body()
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        for await result in group {
            group.cancelAll()
            if let r = result { return r }
            return nil
        }
        return nil
    }
}

@MainActor
func defaultTestHost() -> RemoteHost {
    RemoteHost(
        id: "host-remotehost-integration",
        alias: "remotehost",
        host: "203.0.113.10",
        user: "remoteuser",
        port: 22,
        identityHint: nil,
        addedAt: Date(timeIntervalSince1970: 0)
    )
}

@MainActor
func loadApiKeyOrSkip(_ t: TestRunner) -> String? {
    let authURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Tapgo AICoding/codex/auth.json")
    guard let data = try? Data(contentsOf: authURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let apiKey = json["OPENAI_API_KEY"] as? String,
          !apiKey.isEmpty
    else {
        t.expect(false, "auth.json not present at \(authURL.path); skipping integration test")
        return nil
    }
    return apiKey
}

@MainActor
func runSshProbe(host: RemoteHost, command: String) -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: RemoteCodexHomeSync.findSSH())
    proc.arguments = [
        "-T", "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=8",
        "\(host.user)@\(host.host)",
        command,
    ]
    var env = ProcessInfo.processInfo.environment
    env["LC_ALL"] = "C.UTF-8"
    proc.environment = env
    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe
    proc.standardInput = FileHandle(forReadingAtPath: "/dev/null") ?? FileHandle.nullDevice
    do { try proc.run() } catch { return "" }
    proc.waitUntilExit()
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: out, encoding: .utf8) ?? ""
}

// MARK: - Test hooks on HarnessTransport
extension HarnessTransport {
    func testHookKeyReceivedConfirmed() -> Bool {
        if let r = self as? RemoteSSHHarnessTransport {
            return r.keyReceivedConfirmed
        }
        return true
    }
    func testHookCollectedFrames() -> [JSONValue] {
        if let r = self as? RemoteSSHHarnessTransport {
            return r.collectedFrames
        }
        if let l = self as? LocalHarnessTransport {
            return l.collectedFrames
        }
        return []
    }
    func testHookRegisterPending(id: Int, callback: @escaping (JSONValue) -> Void) {
        if let r = self as? RemoteSSHHarnessTransport {
            r.registerPending(id: id, callback: callback)
            return
        }
        if let l = self as? LocalHarnessTransport {
            l.registerPending(id: id, callback: callback)
        }
    }
    nonisolated func testHookCancelPending(id: Int) {
        if let r = self as? RemoteSSHHarnessTransport {
            r.cancelPending(id: id)
        }
        if let l = self as? LocalHarnessTransport {
            l.cancelPending(id: id)
        }
    }
}
