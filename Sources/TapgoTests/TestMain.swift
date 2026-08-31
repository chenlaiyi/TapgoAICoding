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
    "UserImageAttachmentStore: durable thumbnail copies",
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
    "Thread: evolution mode + workspace",
    "TapgoModel: catalog & provider mapping",
    "GLMQuota: quota/limit 解析与映射",
    "DeepSeekQuota: balance 解析与映射",
    "ModelRegistry: 自定义模型增删改查",
    "TapgoConfigProbe: readAPIKey parses auth file",
    "TapgoConfigProbe: deleteCustomModel rewrites selected id",
    "TapgoConfigProbe: testConnection probes /models",
    "ProviderRegistry: Provider/ProviderModel CRUD + 持久化",
    "ProviderRegistry: v0.5.52 legacy migration",
    "DeepSeekQuota: DeepSeekQuotaClient transport & auth",
    "GLMQuota: GLMQuotaClient transport & auth",
    "ExecEvent: approval request parsing",
    "ExecEvent: command output streaming",
    "ExecEvent: turn plan, diff, compaction",
    "ExecEvent: reasoning summary delta",
    "TokenUsage: parsing (camelCase + snake_case)",
    "ModelUsageMetrics: percentOfWindow + averageCacheHitPercent",
    "RateLimits: JSON parsing + display helpers",
    "ExecEvent: account/rateLimits/updated notification",
    "MiniMaxQuota: SnapshotBuilder (remaining → used)",
    "MiniMaxQuota: MiniMaxQuotaClient (transport-injected)",
    "MiniMaxQuota: lenient match + dual-endpoint fallback",
    "MiniMaxQuota: timestamp parsing (ms vs s)",
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
    "MobilePairing: protocol + URL round-trip",
    "PhoneRemote: token 生成与校验",
    "PhoneRemote: 链接构建与路由鉴权",
    "PhoneRemote: HTTP 解析与响应序列化",
    "PhoneRemote: 状态快照 JSON",
    "PhoneRemote: H5 页面",
    "PhoneRemote: 接入模式与公网中继",
    "PhoneRemote: Markdown 输出渲染",
    "PhoneRemote: 电脑控制路由解析",
    "PhoneRemote: 电脑控制按键映射",
    "PhoneRemote: 电脑控制快照与页面",
    "ComputerUseMCP: 协议分发",
    "ComputerUseMCP: config.toml 段写入",
    "AppUpdate: GitHub Releases distribution",
    "FakeHarnessTransport: start + send + exit",
    "FakeHarnessTransport: send after exit throws",
    "FakeHarnessTransport: simulateStartFailure is one-shot",
    "FakeHarnessTransport: exit is idempotent",
    "FakeHarnessTransport: stop() does not fire onClose by itself",
    "HarnessIdAllocator: monotonic allocation",
    "HarnessIdAllocator: release + reuse",
    "HarnessIdAllocator: server id claim",
    "HarnessIdAllocator: collision detection",
    "HarnessIdAllocator: reset",
    "HarnessIdAllocator: idempotence / repeat releases",
    "HarnessIdAllocator: 1000 allocations are strictly increasing",
    "ConversationRunRegistry: per-thread isolation",
    "TurnSteerPayload: native same-turn steering",
    "TurnPresentation: semantic activity summaries",
    "TurnProgressSummary: plan + diff statistics",
    "AdaptiveEnvironmentLayout: responsive visibility threshold",
    "ApprovalTimeoutTracker: arm / disarm basics",
    "ApprovalTimeoutTracker: re-arm resets deadline",
    "ApprovalTimeoutTracker: sweep fires onExpire",
    "ApprovalTimeoutTracker: disarm prevents expire",
    "ApprovalTimeoutTracker: disarmAll on shutdown",
    "ApprovalTimeoutTracker: default deadline matches config",
    "HarnessSupervisor: start transitions to .running",
    "HarnessSupervisor: stop cancels pending restart",
    "HarnessSupervisor: code 0 and signal exits restart while running",
    "HarnessSupervisor: unexpected exit fires onRestart after backoff",
    "HarnessSupervisor: restart start failures consume retry budget",
    "HarnessSupervisor: backoff is exponential and capped",
    "HarnessSupervisor: idempotent whitelist",
    "HarnessSupervisor: idAllocator is per-supervisor and resets on restart",
    "HarnessSupervisor: reserveServerId prevents collision",
    "HarnessSupervisor: idempotent retry bookkeeping",
    "DurableMemory: sanitize polluted model output",
    "DurableMemory: canonical markdown and dedup",
    "DurableMemory: timestamped bullets",
    "DurableMemory: appendBullet",
    "DurableMemory: byte limit",
    "DurableMemory: summary layer",
    "MemoryConsolidator: deterministic pass",
    "MemoryCloudSync: availability",
    "MemoryCloudSync: relative path round-trip",
    "AgentOutputPolicy: incremental progress contract",
    "DiffParser: empty input returns no files",
    "DiffParser: whitespace-only input returns no files",
    "DiffParser: single-file diff parses file + hunk + lines",
    "DiffParser: total additions + removals computed",
    "DiffParser: comma-less hunk header defaults count to 1",
    "DiffParser: trailing heading after hunk header is preserved",
    "DiffParser: brand-new file has /dev/null old path",
    "DiffParser: deleted file has /dev/null new path",
    "DiffParser: multi-file diff splits into one DiffFile each",
    "DiffParser: git-style 'diff --git' header pre-seeds paths",
    "DiffParser: CRLF input is normalised to LF before parsing",
    "DiffParser: malformed @@ header is skipped, not crashed on",
    "DiffParser: DiffLine.stableKey is unique per line",
    "DiffParser: binary marker produces a DiffFile with isBinary=true",
    "DiffParser: allLines preserves hunk + line order",
    "DiffParser: '\\ No newline' marker is preserved",
    "DiffParser.parseHunkHeader: returns numeric fields",
    "ReviewCommentStore: add then fetch by fileChangeId",
    "ReviewCommentStore: filter by lineKey",
    "ReviewCommentStore: update text by id",
    "ReviewCommentStore: update on missing id returns false",
    "ReviewCommentStore: remove by id",
    "ReviewCommentStore: removeAll(fileChangeId) clears that file only",
    "ReviewCommentStore: clear wipes everything",
    "ReviewCommentStore: allComments spans every file",
    "ReviewComment: Codable round-trips through JSON",
    "ReviewComment: hunk-level comment uses empty lineKey",
    "ReviewCommentStore: 100 concurrent adds don't lose data",
    "AppFontScale: enum shape",
    "TrajectoryFilter: item matching",
    "TurnMarkdown: render",
    "DurationFormatter: string + turn duration",
    "ReasoningMerge: streamed trace wins",
    "AgentCapabilities: skills",
    "PluginCatalog: Codex parsing",
    "PluginCatalog: config editing",
    "PluginCatalog: DeepSeek filtering",
    "Thread: usage & duration summary",
    "RemoteDirectoryLister: argv shape (pure)",
    "RemoteDirectoryLister: live on remotehost",
    "Turn: in-conversation search",
]

/// Run a section only if it's in scope. This is what makes
/// `--filter` actually skip slow tests (not just stop counting
/// them).
@MainActor
func runIfInScope(_ runner: TestRunner, _ name: String, _ body: @escaping @MainActor () async -> Void) async {
    if runner.filter != nil && runner.filter != "all" && runner.filter != name {
        return
    }
    // Honour TAPGO_SKIP_REMOTE_TESTS=1 to skip SSH/protocol integration
    // sections that connect to the RFC 5737 fixture address and would
    // otherwise hang on the default connect timeout. Used by local CI
    // runs and quick dev iterations.
    let environment = ProcessInfo.processInfo.environment
    if environment["TAPGO_SKIP_REMOTE_TESTS"] == "1"
        || environment["TAPGO_SKIP_REMOTE_INTEGRATION"] == "1" {
        if name.hasPrefix("protocol-") || name.hasPrefix("RemoteSSH:") || name.hasPrefix("RemoteCodexHomeSync:") || name.hasPrefix("RemoteDirectoryLister:") || name.hasPrefix("e2e:") {
            print("[skip-remote] \(name)")
            return
        }
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
        await runIfInScope(runner, "UserImageAttachmentStore: durable thumbnail copies") {
            runUserImageAttachmentStore(runner)
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
        await runIfInScope(runner, "Thread: evolution mode + workspace") {
            runThreadEvolutionMode(runner)
        }
        await runIfInScope(runner, "TapgoModel: catalog & provider mapping") {
            runModelCatalog(runner)
        }
        await runIfInScope(runner, "GLMQuota: quota/limit 解析与映射") {
            runGLMQuota(runner)
        }
        await runIfInScope(runner, "GLMQuota: GLMQuotaClient transport & auth") {
            await runGLMQuotaClient(runner)
        }
        await runIfInScope(runner, "DeepSeekQuota: balance 解析与映射") {
            runDeepSeekQuota(runner)
        }
        await runIfInScope(runner, "DeepSeekQuota: DeepSeekQuotaClient transport & auth") {
            await runDeepSeekQuotaClient(runner)
        }
        await runIfInScope(runner, "ModelRegistry: 自定义模型增删改查") {
            runModelRegistry(runner)
        }
        await runIfInScope(runner, "TapgoConfigProbe: readAPIKey parses auth file") {
            runTapgoConfigReadAPIKey(runner)
        }
        await runIfInScope(runner, "TapgoConfigProbe: deleteCustomModel rewrites selected id") {
            runTapgoConfigDeleteCustomModel(runner)
        }
        await runIfInScope(runner, "TapgoConfigProbe: testConnection probes /models") {
            await runTapgoConfigTestConnection(runner)
        }
        await runIfInScope(runner, "ProviderRegistry: Provider/ProviderModel CRUD + 持久化") {
            runProviderRegistry(runner)
        }
        await runIfInScope(runner, "ProviderRegistry: v0.5.52 legacy migration") {
            runProviderRegistryMigration(runner)
        }
        await runIfInScope(runner, "ExecEvent: approval request parsing") {
            runExecEventParserApprovalRequests(runner)
        }
        await runIfInScope(runner, "ExecEvent: command output streaming") {
            runExecEventParserCommandOutput(runner)
        }
        await runIfInScope(runner, "ExecEvent: turn plan, diff, compaction") {
            runExecEventParserTurnSnapshots(runner)
        }
        await runIfInScope(runner, "ExecEvent: reasoning summary delta") {
            runExecEventParserReasoningSummary(runner)
        }
        await runIfInScope(runner, "TokenUsage: parsing (camelCase + snake_case)") {
            runTokenUsageParsing(runner)
        }
        await runIfInScope(runner, "ModelUsageMetrics: percentOfWindow + averageCacheHitPercent") {
            runModelUsageMetrics(runner)
        }
        await runIfInScope(runner, "RateLimits: JSON parsing + display helpers") {
            runRateLimitsParsing(runner)
        }
        await runIfInScope(runner, "ExecEvent: account/rateLimits/updated notification") {
            runExecEventParserRateLimitsUpdated(runner)
        }
        await runIfInScope(runner, "MiniMaxQuota: SnapshotBuilder (remaining → used)") {
            runMiniMaxQuotaParsing(runner)
        }
        await runIfInScope(runner, "MiniMaxQuota: MiniMaxQuotaClient (transport-injected)") {
            await runMiniMaxQuotaClient(runner)
        }
        await runIfInScope(runner, "MiniMaxQuota: lenient match + dual-endpoint fallback") {
            await runMiniMaxQuotaLenientMatch(runner)
        }
        await runIfInScope(runner, "MiniMaxQuota: timestamp parsing (ms vs s)") {
            runMiniMaxQuotaTimestampParsing(runner)
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
        await runIfInScope(runner, "FakeHarnessTransport: start + send + exit") {
            runFakeHarnessTransportStartSendExit(runner)
        }
        await runIfInScope(runner, "FakeHarnessTransport: send after exit throws") {
            runFakeHarnessTransportSendAfterExitThrows(runner)
        }
        await runIfInScope(runner, "FakeHarnessTransport: simulateStartFailure is one-shot") {
            runFakeHarnessTransportStartFailureIsOneShot(runner)
        }
        await runIfInScope(runner, "FakeHarnessTransport: exit is idempotent") {
            runFakeHarnessTransportExitIsIdempotent(runner)
        }
        await runIfInScope(runner, "FakeHarnessTransport: stop() does not fire onClose by itself") {
            runFakeHarnessTransportStopAlone(runner)
        }
        await runIfInScope(runner, "HarnessIdAllocator: monotonic allocation") {
            runHarnessIdAllocatorMonotonic(runner)
        }
        await runIfInScope(runner, "HarnessIdAllocator: release + reuse") {
            runHarnessIdAllocatorReleaseReuse(runner)
        }
        await runIfInScope(runner, "HarnessIdAllocator: server id claim") {
            runHarnessIdAllocatorServerClaim(runner)
        }
        await runIfInScope(runner, "HarnessIdAllocator: collision detection") {
            runHarnessIdAllocatorCollision(runner)
        }
        await runIfInScope(runner, "HarnessIdAllocator: reset") {
            runHarnessIdAllocatorReset(runner)
        }
        await runIfInScope(runner, "HarnessIdAllocator: idempotence / repeat releases") {
            runHarnessIdAllocatorRepeatReleases(runner)
        }
        await runIfInScope(runner, "HarnessIdAllocator: 1000 allocations are strictly increasing") {
            runHarnessIdAllocatorStress(runner)
        }
        await runIfInScope(runner, "ConversationRunRegistry: per-thread isolation") {
            runConversationRunRegistryTests(runner)
        }
        await runIfInScope(runner, "TurnSteerPayload: native same-turn steering") {
            runTurnSteerPayloadTests(runner)
        }
        await runIfInScope(runner, "TurnPresentation: semantic activity summaries") {
            runTurnPresentationTests(runner)
        }
        await runIfInScope(runner, "TurnProgressSummary: plan + diff statistics") {
            runTurnProgressSummaryTests(runner)
        }
        await runIfInScope(runner, "AdaptiveEnvironmentLayout: responsive visibility threshold") {
            runAdaptiveEnvironmentLayoutTests(runner)
        }
        await runIfInScope(runner, "ApprovalTimeoutTracker: arm / disarm basics") {
            runApprovalTimeoutArmDisarm(runner)
        }
        await runIfInScope(runner, "ApprovalTimeoutTracker: re-arm resets deadline") {
            runApprovalTimeoutRearm(runner)
        }
        await runIfInScope(runner, "ApprovalTimeoutTracker: sweep fires onExpire") {
            runApprovalTimeoutSweepFires(runner)
        }
        await runIfInScope(runner, "ApprovalTimeoutTracker: disarm prevents expire") {
            runApprovalTimeoutDisarmPrevents(runner)
        }
        await runIfInScope(runner, "ApprovalTimeoutTracker: disarmAll on shutdown") {
            runApprovalTimeoutDisarmAll(runner)
        }
        await runIfInScope(runner, "ApprovalTimeoutTracker: default deadline matches config") {
            runApprovalTimeoutDefaultDeadline(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: start transitions to .running") {
            await runHarnessSupervisorStartTransitions(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: stop cancels pending restart") {
            await runHarnessSupervisorStopCancels(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: code 0 and signal exits restart while running") {
            await runHarnessSupervisorRunningExitCodes(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: unexpected exit fires onRestart after backoff") {
            await runHarnessSupervisorRestartAfterBackoff(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: restart start failures consume retry budget") {
            await runHarnessSupervisorGivesUp(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: backoff is exponential and capped") {
            runHarnessSupervisorBackoff(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: idempotent whitelist") {
            runHarnessSupervisorIdempotentWhitelist(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: idAllocator is per-supervisor and resets on restart") {
            runHarnessSupervisorIdAllocator(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: reserveServerId prevents collision") {
            runHarnessSupervisorReserveServerId(runner)
        }
        await runIfInScope(runner, "HarnessSupervisor: idempotent retry bookkeeping") {
            runHarnessSupervisorRetryBookkeeping(runner)
        }
        await runIfInScope(runner, "DurableMemory: sanitize polluted model output") {
            runDurableMemorySanitization(runner)
        }
        await runIfInScope(runner, "DurableMemory: canonical markdown and dedup") {
            runDurableMemoryMarkdown(runner)
        }
        await runIfInScope(runner, "DurableMemory: timestamped bullets") {
            runDurableMemoryTimestampedBullets(runner)
        }
        await runIfInScope(runner, "DurableMemory: appendBullet") {
            runDurableMemoryAppendBullet(runner)
        }
        await runIfInScope(runner, "DurableMemory: byte limit") {
            runDurableMemoryByteLimit(runner)
        }
        await runIfInScope(runner, "DurableMemory: summary layer") {
            runDurableMemorySummaryLayer(runner)
        }
        await runIfInScope(runner, "MemoryConsolidator: deterministic pass") {
            await runMemoryConsolidatorDeterministic(runner)
        }
        await runIfInScope(runner, "MemoryCloudSync: availability") {
            runMemoryCloudSyncAvailability(runner)
        }
        await runIfInScope(runner, "MemoryCloudSync: relative path round-trip") {
            runMemoryCloudSyncRelativePath(runner)
        }
        await runIfInScope(runner, "AgentOutputPolicy: incremental progress contract") {
            runAgentOutputPolicyContract(runner)
        }
        await runIfInScope(runner, "DiffParser: empty input returns no files") {
            runDiffParserEmpty(runner)
        }
        await runIfInScope(runner, "DiffParser: whitespace-only input returns no files") {
            runDiffParserWhitespaceOnly(runner)
        }
        await runIfInScope(runner, "DiffParser: single-file diff parses file + hunk + lines") {
            runDiffParserSingleFileBasic(runner)
        }
        await runIfInScope(runner, "DiffParser: total additions + removals computed") {
            runDiffParserStats(runner)
        }
        await runIfInScope(runner, "DiffParser: comma-less hunk header defaults count to 1") {
            runDiffParserSingleLineHunk(runner)
        }
        await runIfInScope(runner, "DiffParser: trailing heading after hunk header is preserved") {
            runDiffParserHunkWithHeading(runner)
        }
        await runIfInScope(runner, "DiffParser: brand-new file has /dev/null old path") {
            runDiffParserCreate(runner)
        }
        await runIfInScope(runner, "DiffParser: deleted file has /dev/null new path") {
            runDiffParserDelete(runner)
        }
        await runIfInScope(runner, "DiffParser: multi-file diff splits into one DiffFile each") {
            runDiffParserMultiFile(runner)
        }
        await runIfInScope(runner, "DiffParser: git-style 'diff --git' header pre-seeds paths") {
            runDiffParserGitHeader(runner)
        }
        await runIfInScope(runner, "DiffParser: CRLF input is normalised to LF before parsing") {
            runDiffParserCRLFNormalisation(runner)
        }
        await runIfInScope(runner, "DiffParser: malformed @@ header is skipped, not crashed on") {
            runDiffParserMalformedHeaderIsSkipped(runner)
        }
        await runIfInScope(runner, "DiffParser: DiffLine.stableKey is unique per line") {
            runDiffParserStableKey(runner)
        }
        await runIfInScope(runner, "DiffParser: binary marker produces a DiffFile with isBinary=true") {
            runDiffParserBinaryMarker(runner)
        }
        await runIfInScope(runner, "DiffParser: allLines preserves hunk + line order") {
            runDiffParserAllLinesOrder(runner)
        }
        await runIfInScope(runner, "DiffParser: '\\ No newline' marker is preserved") {
            runDiffParserNoNewlineAtEOF(runner)
        }
        await runIfInScope(runner, "DiffParser.parseHunkHeader: returns numeric fields") {
            runDiffParserHunkHeaderParserDirectly(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: add then fetch by fileChangeId") {
            runReviewCommentAddAndFetch(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: filter by lineKey") {
            runReviewCommentFetchByLineKey(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: update text by id") {
            runReviewCommentUpdate(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: update on missing id returns false") {
            runReviewCommentUpdateMiss(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: remove by id") {
            runReviewCommentRemove(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: removeAll(fileChangeId) clears that file only") {
            runReviewCommentRemoveAll(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: clear wipes everything") {
            runReviewCommentClear(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: allComments spans every file") {
            runReviewCommentAllComments(runner)
        }
        await runIfInScope(runner, "ReviewComment: Codable round-trips through JSON") {
            runReviewCommentCodableRoundTrip(runner)
        }
        await runIfInScope(runner, "ReviewComment: hunk-level comment uses empty lineKey") {
            runReviewCommentHunkLevelUsesEmptyKey(runner)
        }
        await runIfInScope(runner, "ReviewCommentStore: 100 concurrent adds don't lose data") {
            runReviewCommentStoreConcurrency(runner)
        }
        await runIfInScope(runner, "AppFontScale: enum shape") {
            runAppFontScaleTests(runner)
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
        await runIfInScope(runner, "PluginCatalog: Codex parsing") {
            runPluginCatalogCodexParsing(runner)
        }
        await runIfInScope(runner, "PluginCatalog: config editing") {
            runPluginCatalogConfigEditing(runner)
        }
        await runIfInScope(runner, "PluginCatalog: DeepSeek filtering") {
            runPluginCatalogDeepSeekFiltering(runner)
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
        await runIfInScope(runner, "Turn: in-conversation search") {
            runTurnSearch(runner)
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
        await runIfInScope(runner, "MobilePairing: protocol + URL round-trip") {
            runMobilePairing(runner)
        }
        await runIfInScope(runner, "PhoneRemote: token 生成与校验") {
            runPhoneRemoteToken(runner)
        }
        await runIfInScope(runner, "PhoneRemote: 链接构建与路由鉴权") {
            runPhoneRemoteLinkRoute(runner)
        }
        await runIfInScope(runner, "PhoneRemote: HTTP 解析与响应序列化") {
            runPhoneRemoteHTTP(runner)
        }
        await runIfInScope(runner, "PhoneRemote: 状态快照 JSON") {
            runPhoneRemoteSnapshot(runner)
        }
        await runIfInScope(runner, "PhoneRemote: H5 页面") {
            runPhoneRemotePage(runner)
        }
        await runIfInScope(runner, "PhoneRemote: 接入模式与公网中继") {
            runPhoneRemoteAccessModes(runner)
        }
        await runIfInScope(runner, "PhoneRemote: Markdown 输出渲染") {
            runPhoneRemoteMarkdown(runner)
        }
        await runIfInScope(runner, "PhoneRemote: 电脑控制路由解析") {
            runPhoneRemoteControlRoutes(runner)
        }
        await runIfInScope(runner, "PhoneRemote: 电脑控制按键映射") {
            runPhoneRemoteControlKeys(runner)
        }
        await runIfInScope(runner, "PhoneRemote: 电脑控制快照与页面") {
            runPhoneRemoteControlSnapshot(runner)
        }
        await runIfInScope(runner, "ComputerUseMCP: 协议分发") {
            runComputerUseMCPProtocol(runner)
        }
        await runIfInScope(runner, "ComputerUseMCP: config.toml 段写入") {
            runComputerUseMCPConfigSection(runner)
        }
        await runIfInScope(runner, "AppUpdate: GitHub Releases distribution") {
            runAppUpdateDistribution(runner)
        }
    }
}
