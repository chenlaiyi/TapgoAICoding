// TapgoTests/main.swift
//
// Standalone test runner. `swift run TapgoTests` runs the full suite
// against the real `TapgoCore` library — no hand-rolled copies of
// the regex/validators. Exits non-zero on the first failure (and
// always prints a summary at the end).
//
// CLI flags (handled before any tests run):
//   `--list`             print every section name and exit 0
//   `--filter <section>` run only the named section (also supports
//                        `--filter all` to force the full suite,
//                        which is the default)
//   `--help`             show this help and exit 0
//
// Section dispatch is **strict**: when a filter is set, only the
// matching section's function actually runs. Out-of-scope section
// functions are skipped entirely (this matters for the slow
// RemoteSSHHarnessTransport integration test which we never want to
// start unless the user explicitly asked for it).
//
// We do not use XCTest / swift-testing because the CommandLineTools
// Swift toolchain on this machine ships neither framework.

import Foundation
import TapgoCore

/// Sections registered up-front so `--list` can print them and
/// `--filter` can pre-decide which suite to run.
let allSections: [String] = [
    "RemoteCommandBuilder: input validation",
    "RemoteCommandBuilder: buildSshArgv shape",
    "RemoteCommandBuilder: buildSshArgv rejects bad inputs",
    "RemoteCommandBuilder: command escaping (defense in depth)",
    "Project: display path & harness cwd",
    "Project: Codable round-trip",
    "RemoteHost: probe argv shape",
    "WorkspaceState: version + active project",
    "WorkspaceStore: load from fresh state",
    "WorkspaceStore: addProject dedup",
    "WorkspaceStore: ensureRemoteMirrorExists",
    "WorkspaceStore: load after save round-trips",
    "WorkspaceStore: removeProject + cascade",
    "WorkspaceStore: removeRemoteHost cascades projects to local",
    "ThreadStore: load from fresh state",
    "ThreadStore: save + load round-trips per-id file",
    "ThreadStore: delete removes file",
    "ThreadStore: v0 → v1 migration",
    "ThreadStore: turns + items round-trip",
    "ThreadStore: legacy file without turns decodes",
    "RemoteCodexHomeSync: rendered config has no secret material",
    "RemoteCodexHomeSync: trusted projects are remote-only",
    "RemoteCodexHomeSync: harness wrapper script",
    "RemoteCodexHomeSync: literal key is never present anywhere in the public surface",
    "RemoteSSH: push config + catalog (no auth)",
    "protocol-1: ssh connection + remote codex",
    "protocol-2: ssh round-trip",
    "protocol-3: ssh stdin key delivery",
    "protocol-4: remote JSON-RPC initialize",
    "local: JSON-RPC initialize round-trip (sanity)",
    "e2e: remote turn (hostname/pwd, single source of truth)",
    "e2e: remote turn with `false` (exit code propagation)",
    "Thread: auto-title from first user message",
    "ExecEvent: approval request parsing",
    "ExecEvent: reasoning summary delta",
    "TokenUsage: parsing (camelCase + snake_case)",
    "MarkdownLite: fenced code blocks",
    "MarkdownLite: inline code + bold",
    "MarkdownLite: passthrough",
    "MarkdownLite: empty",
    "MarkdownLite: lists",
    "MarkdownLite: links",
    "MarkdownLite: quote + rule",
    "MarkdownLite: tables",
    "MarkdownLite: task list",
    "MarkdownLite: images",
    "MarkdownLite: headings",
    "MarkdownLite: strikethrough",
    "TrajectoryFilter: item matching",
    "TurnMarkdown: render",
    "DurationFormatter: string + turn duration",
    "ReasoningMerge: streamed trace wins",
    "AgentCapabilities: skills",
    "Thread: usage & duration summary",
    "RemoteDirectoryLister: argv shape (pure)",
    "RemoteDirectoryLister: live on remotehost",
]

/// Run a section only if it's in scope. This is what makes
/// `--filter` actually skip slow tests (not just stop counting
/// them).
@MainActor
func runIfInScope(_ runner: TestRunner, _ name: String, _ body: @escaping @MainActor () async -> Void) async {
    if runner.filter != nil && runner.filter != "all" && runner.filter != name {
        return
    }
    runner.section(name)
    await body()
    runner.endSection()
}

@main
struct TapgoTestMain {
    static func main() async {
        let args = CommandLine.arguments
        if args.contains("--help") || args.contains("-h") {
            print("""
            TapgoTests — standalone runner.

            Usage: swift run TapgoTests [--list] [--filter <section>] [--help]

              --list             Print every section name and exit 0
              --filter <name>    Run only the named section (or "all")
              --help, -h         Show this help
            """)
            exit(0)
        }
        if args.contains("--list") {
            for s in allSections { print("  \(s)") }
            exit(0)
        }
        var filter: String? = nil
        if let i = args.firstIndex(of: "--filter"), i + 1 < args.count {
            filter = args[i + 1]
            if filter != "all", !allSections.contains(filter ?? "") {
                print("Unknown section: \(filter ?? "")\nRun with --list to see all sections.")
                exit(2)
            }
        }

        let runner = TestRunner(filter: filter, allSections: allSections)
        await runAll(runner: runner)
        let code = runner.summary()
        exit(Int32(code))
    }

    @MainActor
    static func runAll(runner: TestRunner) async {
        await runIfInScope(runner, "RemoteCommandBuilder: input validation") {
            runRemoteCommandBuilderInputValidation(runner)
        }
        await runIfInScope(runner, "RemoteCommandBuilder: buildSshArgv shape") {
            runRemoteCommandBuilderBuildSshArgvShape(runner)
        }
        await runIfInScope(runner, "RemoteCommandBuilder: buildSshArgv rejects bad inputs") {
            runRemoteCommandBuilderBuildSshArgvRejects(runner)
        }
        await runIfInScope(runner, "RemoteCommandBuilder: command escaping (defense in depth)") {
            runRemoteCommandBuilderCommandEscaping(runner)
        }
        await runIfInScope(runner, "Project: display path & harness cwd") {
            runProjectDisplayPathHarnessCwd(runner)
        }
        await runIfInScope(runner, "Project: Codable round-trip") {
            runProjectCodableRoundTrip(runner)
        }
        await runIfInScope(runner, "RemoteHost: probe argv shape") {
            runRemoteHostProbeArgv(runner)
        }
        await runIfInScope(runner, "WorkspaceState: version + active project") {
            runWorkspaceStateVersionAndActive(runner)
        }
        await runIfInScope(runner, "WorkspaceStore: load from fresh state") {
            runWorkspaceStoreLoadFresh(runner)
        }
        await runIfInScope(runner, "WorkspaceStore: addProject dedup") {
            runWorkspaceStoreAddProjectDedup(runner)
        }
        await runIfInScope(runner, "WorkspaceStore: ensureRemoteMirrorExists") {
            runWorkspaceStoreEnsureRemoteMirrorExists(runner)
        }
        await runIfInScope(runner, "WorkspaceStore: load after save round-trips") {
            runWorkspaceStoreLoadAfterSave(runner)
        }
        await runIfInScope(runner, "WorkspaceStore: removeProject + cascade") {
            runWorkspaceStoreRemoveProject(runner)
        }
        await runIfInScope(runner, "WorkspaceStore: removeRemoteHost cascades projects to local") {
            runWorkspaceStoreRemoveRemoteHostCascade(runner)
        }
        await runIfInScope(runner, "ThreadStore: load from fresh state") {
            runThreadStoreLoadFresh(runner)
        }
        await runIfInScope(runner, "ThreadStore: save + load round-trips per-id file") {
            runThreadStoreSaveLoad(runner)
        }
        await runIfInScope(runner, "ThreadStore: delete removes file") {
            runThreadStoreDelete(runner)
        }
        await runIfInScope(runner, "ThreadStore: v0 → v1 migration") {
            runThreadStoreV0Migration(runner)
        }
        await runIfInScope(runner, "ThreadStore: turns + items round-trip") {
            runThreadStoreTurnsPersisted(runner)
        }
        await runIfInScope(runner, "ThreadStore: legacy file without turns decodes") {
            runThreadStoreDecodesLegacyWithoutTurns(runner)
        }
        await runIfInScope(runner, "Thread: auto-title from first user message") {
            runThreadAutoTitle(runner)
        }
        await runIfInScope(runner, "Thread: latest sidebar preview") {
            runThreadLatestPreview(runner)
        }
        await runIfInScope(runner, "Thread: date banner") {
            runThreadDateBanner(runner)
        }
        await runIfInScope(runner, "Thread: goal round-trip") {
            runThreadGoalRoundtrip(runner)
        }
        await runIfInScope(runner, "ExecEvent: approval request parsing") {
            runExecEventParserApprovalRequests(runner)
        }
        await runIfInScope(runner, "ExecEvent: reasoning summary delta") {
            runExecEventParserReasoningSummary(runner)
        }
        await runIfInScope(runner, "TokenUsage: parsing (camelCase + snake_case)") {
            runTokenUsageParsing(runner)
        }
        await runIfInScope(runner, "MarkdownLite: fenced code blocks") {
            runMarkdownLiteFencedCode(runner)
        }
        await runIfInScope(runner, "MarkdownLite: inline code + bold") {
            runMarkdownLiteInlineAndBold(runner)
        }
        await runIfInScope(runner, "MarkdownLite: passthrough") {
            runMarkdownLitePassthrough(runner)
        }
        await runIfInScope(runner, "MarkdownLite: empty") {
            runMarkdownLiteEmpty(runner)
        }
        await runIfInScope(runner, "MarkdownLite: lists") {
            runMarkdownLiteLists(runner)
        }
        await runIfInScope(runner, "MarkdownLite: links") {
            runMarkdownLiteLinks(runner)
        }
        await runIfInScope(runner, "MarkdownLite: quote + rule") {
            runMarkdownLiteQuoteRule(runner)
        }
        await runIfInScope(runner, "MarkdownLite: tables") {
            runMarkdownLiteTables(runner)
        }
        await runIfInScope(runner, "MarkdownLite: task list") {
            runMarkdownLiteTaskList(runner)
        }
        await runIfInScope(runner, "MarkdownLite: images") {
            runMarkdownLiteImages(runner)
        }
        await runIfInScope(runner, "MarkdownLite: headings") {
            runMarkdownLiteHeadings(runner)
        }
        await runIfInScope(runner, "MarkdownLite: strikethrough") {
            runMarkdownLiteStrikethrough(runner)
        }
        await runIfInScope(runner, "TrajectoryFilter: item matching") {
            runTrajectoryFilter(runner)
        }
        await runIfInScope(runner, "TurnMarkdown: render") {
            runTurnMarkdown(runner)
        }
        await runIfInScope(runner, "DurationFormatter: string + turn duration") {
            runDurationFormatter(runner)
        }
        await runIfInScope(runner, "ReasoningMerge: streamed trace wins") {
            runReasoningMerge(runner)
        }
        await runIfInScope(runner, "AgentCapabilities: skills") {
            runAgentCapabilities(runner)
        }
        await runIfInScope(runner, "Thread: usage & duration summary") {
            runThreadSummary(runner)
        }
        await runIfInScope(runner, "RemoteDirectoryLister: argv shape (pure)") {
            runRemoteDirListerArgvShape(runner)
        }
        await runIfInScope(runner, "RemoteDirectoryLister: live on remotehost") {
            await runRemoteDirListerLive(runner)
        }
        await runIfInScope(runner, "RemoteCodexHomeSync: rendered config has no secret material") {
            runRemoteCodexHomeSyncConfigNoSecret(runner)
        }
        await runIfInScope(runner, "RemoteCodexHomeSync: trusted projects are remote-only") {
            runRemoteCodexHomeSyncTrustedProjects(runner)
        }
        await runIfInScope(runner, "RemoteCodexHomeSync: harness wrapper script") {
            runRemoteCodexHomeSyncWrapper(runner)
        }
        await runIfInScope(runner, "RemoteCodexHomeSync: literal key is never present anywhere in the public surface") {
            runRemoteCodexHomeSyncNoLiteralKey(runner)
        }
        await runIfInScope(runner, "RemoteSSH: push config + catalog (no auth)") {
            await runRemoteSSHPushConfigNoAuth(runner)
        }
        await runIfInScope(runner, "protocol-1: ssh connection + remote codex") {
            await runProtocol1SshConnection(runner)
        }
        await runIfInScope(runner, "protocol-2: ssh round-trip") {
            await runProtocol2SshRoundtrip(runner)
        }
        await runIfInScope(runner, "protocol-3: ssh stdin key delivery") {
            await runProtocol3SshStdinKey(runner)
        }
        await runIfInScope(runner, "protocol-4: remote JSON-RPC initialize") {
            await runProtocol4RemoteInitialize(runner)
        }
        await runIfInScope(runner, "local: JSON-RPC initialize round-trip (sanity)") {
            await runLocalInitializeRoundtrip(runner)
        }
        await runIfInScope(runner, "e2e: remote turn (hostname/pwd, single source of truth)") {
            await runE2ERemoteTurn(runner)
        }
        await runIfInScope(runner, "e2e: remote turn with `false` (exit code propagation)") {
            await runRemoteSSHFailedCommand(runner)
        }
    }
}
