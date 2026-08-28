import SwiftUI
import TapgoCore

/// "自进化日志"弹窗。
///
/// 设计目标：让用户**每次点进来都更看懂 AI、更会用 AI**。
///   1. 顶部 hero：当前版本 + commit + 真实 next-actions（来自 evolution_state.json）。
///   2. 历史：按版本倒序列出每一次自进化（为什么、改了什么、下一步）。
///   3. 使用指南：分场景（开发 / 工作 / 设计 / 调试）告诉用户怎么让 AI 更有用。
///   4. 自进化理念 + 协作约定（用户看一眼就懂 AI 的边界与偏好）。
///
/// 所有静态内容在源码里硬编码，保证离线可用、编译期校验；只有"当前状态"
/// 会在 onAppear 时尝试从 `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`
/// 拉取，找不到就优雅降级。
struct EvolutionLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var liveState: EvolutionState? = nil
    @State private var loadError: String? = nil
    @State private var hasLoaded = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    /// 历史日志条目。最新在最上。
    private let history: [EvolutionEntry] = EvolutionLogView.makeHistory()

    /// 使用指南条目（按场景分组）。
    private let playbook: [PlaybookSection] = EvolutionLogView.makePlaybook()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    philosophyCard
                    historySection
                    playbookSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
        .frame(width: 640, height: 720)
        .background(DSHTheme.bg)
        .onAppear(perform: loadLiveState)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DSHTheme.brand.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DSHTheme.brand)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("自进化日志")
                    .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                Text("Tapgo AICoding · Self-Evolution Log")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Hero card (current version)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(currentVersionTag())
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(DSHTheme.brand)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(currentDate())
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("本次进化")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DSHTheme.brandSoft, in: Capsule())
                    .foregroundStyle(DSHTheme.brand)
            }

            Text(liveState?.evolutionNote ?? latestHistoryEntry.summary)
                .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let sha = liveState?.commitSha ?? latestHistoryEntry.commit {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    Text(shortCommit(sha))
                        .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                }
                .foregroundStyle(.tertiary)
            }

            if let err = loadError {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    Text("实时状态: \(err)")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
                .stroke(DSHTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Philosophy

    private var philosophyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("什么是自进化？", systemImage: "arrow.triangle.2.circlepath")
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.semibold))
                .foregroundStyle(DSHTheme.label)

            Text("每次发布我都会让 AI 跑一遍 `evolve.sh`：自动改代码 → 跑 332 个测试 → 打 tag → 推 git。"
                 + "这一页就是这条流水线的对外广播。")
                .font(AppFont.scaled(.callout, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(DSHTheme.success)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Text("测试全绿才发布")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                Spacer().frame(width: 12)
                Image(systemName: "tag.fill")
                    .foregroundStyle(DSHTheme.brand)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Text("每个版本都打 git tag，可一键回滚")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
                .stroke(DSHTheme.border, lineWidth: 1)
        )
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("历史版本", systemImage: "clock.arrow.circlepath")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.semibold))
                Spacer()
                Text("\(history.count) 次进化")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }

            ForEach(history) { entry in
                EvolutionEntryRow(entry: entry, isLatest: entry.id == history.first?.id)
            }
        }
    }

    // MARK: - Playbook (how to use me better)

    private var playbookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("怎么用我更好", systemImage: "lightbulb.fill")
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.semibold))
                .foregroundStyle(DSHTheme.warn)

            Text("下面这些是我**亲测能让你事半功倍**的用法。按场景挑你常用的看就行。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(playbook) { section in
                    PlaybookRow(section: section)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(DSHTheme.brand)
                Text("每一行代码背后都有一份测试、一个 tag、一段反思。")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            if let actions = liveState?.nextActions, !actions.isEmpty {
                Text("下一步：\(actions.prefix(2).joined(separator: " / "))")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func currentVersionTag() -> String {
        if let tag = liveState?.tag { return tag }
        return latestHistoryEntry.tag ?? latestHistoryEntry.version
    }

    private func currentDate() -> String {
        if let builtAt = liveState?.builtAt {
            return formatDate(builtAt)
        }
        return latestHistoryEntry.date
    }

    private var latestHistoryEntry: EvolutionEntry {
        history.first ?? EvolutionLogView.placeholderEntry
    }

    private func shortCommit(_ sha: String) -> String {
        String(sha.prefix(7))
    }

    private func formatDate(_ iso: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        guard let date = isoFormatter.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    private func loadLiveState() {
        guard !hasLoaded else { return }
        hasLoaded = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = EvolutionLogView.readLiveState()
            DispatchQueue.main.async {
                switch result {
                case .success(let state):
                    self.liveState = state
                case .failure(let err):
                    self.loadError = err.message
                }
            }
        }
    }

    // MARK: - Static content (history)

    private static func makeHistory() -> [EvolutionEntry] {
        // 倒序：最新在最上。新增条目直接 prepend 即可。
        return [
            EvolutionEntry(
                version: "v0.5.2",
                date: "2026-08-28",
                commit: nil,
                tag: "v0.5.2",
                summary: "强制小步增量输出与异常即时反馈",
                changes: [
                    "线程级输出契约明确每个有意义步骤完成后立即输出 1–3 行结果与下一步",
                    "每个用户任务前追加短提醒，恢复旧对话时也不会被长上下文稀释",
                    "App 在命令、工具和文件事件完成时生成两行即时进度，失败事件立即可见",
                    "关闭并行工具批处理并自动刷新模型目录，新增 21 项输出协议测试，总测试 685 → 706"
                ],
                why: "v0.5.1 只有一句宽泛提示；仅加强 Prompt 后模型仍会并行执行多个工具并集中总结，因此需要 App 事件层兜底。",
                next: "持续观察长任务中模型的实际分段消息，并在 Harness 支持更强事件策略时下沉为协议级约束。"
            ),
            EvolutionEntry(
                version: "v0.5.1",
                date: "2026-08-28",
                commit: nil,
                tag: "v0.5.1",
                summary: "恢复开发代理职责并清洗长期记忆",
                changes: [
                    "核心开发职责与长期记忆分层注入，当前请求和工作区证据始终优先",
                    "长期记忆只保留稳定 Markdown 要点，过滤思考轨迹、NONE、临时任务、凭据与版本快照",
                    "旧记忆在追加时自动规范化、语义去重，污染文件已备份后修复",
                    "新增 DurableMemory 回归测试，测试数 667 → 685"
                ],
                why: "修复记忆内容覆盖基础指令后，模型只复述旧上下文、虚构工具不可用并停止开发的问题。",
                next: "继续补充真实原生 App 的长周期记忆与跨对话开发回归。"
            ),
            EvolutionEntry(
                version: "v0.5.0",
                date: "2026-08-28",
                commit: "eaa3d90",
                tag: "v0.5.0",
                summary: "结构化 Diff 与逐行审查评论",
                changes: [
                    "解析 unified diff 为文件、hunk 与行级结构",
                    "支持 unified、split、raw 三种渲染模式和逐行评论",
                    "新增 DiffParser 与 ReviewCommentStore 回归覆盖，测试数 572 → 667"
                ],
                why: "把纯字符串着色升级为可审查、可评论的结构化代码变更视图。",
                next: "恢复开发代理职责并加固长期记忆边界。"
            ),
            EvolutionEntry(
                version: "v0.4.3",
                date: "2026-08-27",
                commit: nil,
                tag: "v0.4.3",
                summary: "对话独立执行与 Harness 失效恢复修复",
                changes: [
                    "每个对话独立持有 runner、队列、取消和运行状态，切换对话不会中断后台任务",
                    "审批按 turn 与所属 runner 路由，60 秒真实定时自动拒绝，兼容数字和字符串 RPC id",
                    "Harness 意外退出立即结束旧回合，code 0、信号退出和重启失败均纳入有限重试",
                    "新增对话运行注册表与 Supervisor 回归覆盖，测试数 517 → 572"
                ],
                why: "解决新对话被全局 runner 阻塞、插话误停旧对话，以及审批或 Harness 异常导致永久卡住的问题。",
                next: "增加 App target 的可注入 runner 协调器测试和长任务无事件看门狗。"
            ),
            EvolutionEntry(
                version: "v0.4.1",
                date: "2026-08-27",
                commit: "fa917d3",
                tag: "v0.4.1",
                summary: "Harness 进程监督、JSON-RPC id 防重用、审批超时",
                changes: [
                    "新增 HarnessSupervisor、HarnessIdAllocator 与 ApprovalTimeoutTracker",
                    "加入内存 FakeHarnessTransport 和协议层回归测试",
                    "测试数 420 → 517"
                ],
                why: "为 Harness 进程退出、审批挂起和 JSON-RPC id 冲突建立专用防线。",
                next: "按对话隔离执行生命周期，并验证异常恢复不会留下挂起回合。"
            ),
            EvolutionEntry(
                version: "v0.4.0",
                date: "2026-08-27",
                commit: nil,
                tag: "v0.4.0",
                summary: "Harness 协议与上下文恢复升级",
                changes: [
                    "修复同一会话未复用 thread/resume 的上下文断链，并增加 rollout 丢失后的有界恢复",
                    "对齐 Codex 0.149/0.150 server-request 审批与实时命令输出协议",
                    "真实保留 interrupted 状态，RPC 增加超时，回合结束后回收 app-server",
                    "借鉴 DeepSeek Harness rc.2 的失败关闭、80% 压缩压力和恢复设计",
                    "跨会话记忆串行化、限长、校验、去重，并明确额外模型调用"
                ],
                why: "解决原生 App 的实际上下文失忆、审批失效、命令输出缺失与旧 Codex CLI 被误选问题。",
                next: "接入可见的 thread compact 状态、文件 patch 增量与 FakeTransport 两轮端到端测试。"
            ),
            EvolutionEntry(
                version: "v0.3.3",
                date: "2026-08-26",
                commit: nil,
                tag: nil,
                summary: "侧边栏新增「自进化」按钮 + 自进化日志弹窗",
                changes: [
                    "侧边栏顶栏在新对话上方新增「自进化」入口（sparkles 图标）",
                    "新建 EvolutionLogView：展示当前版本 / 真实 next-actions / 历史版本 / 使用指南",
                    "运行时从 evolution_state.json 拉取真实状态，缺失时优雅降级到源码快照",
                    "使用指南按场景分组：开发软件 / 工作文档 / 设计创意 / 调试疑难"
                ],
                why: "用户多次反馈「点进来想了解 AI 现在能干嘛、怎么用更好」；把自进化流水线和最佳实践摆在手边，每次点开都更新一点点。",
                next: "弹窗内加「回到最新 commit」按钮 + 在 EVOLUTION.md 的 git tag 自动化上确认 v0.3.3。"
            ),
            EvolutionEntry(
                version: "v0.3.2",
                date: "2026-08-25",
                commit: "c141776",
                tag: "v0.3.2",
                summary: "evolve.sh 默认跳过 SSH 集成测试；测试计数 110 → 332",
                changes: [
                    "evolve.sh 默认设置 TAPGO_SKIP_REMOTE_INTEGRATION=1，避免依赖 RFC 5737 测试地址",
                    "README 测试数从 110 更新为真实 332",
                    "evolve.sh 的 sanity check 由硬失败降为警告",
                    "版本号自动从最新 git tag 读取",
                    "修复若干 set -u 下的未初始化变量"
                ],
                why: "SSH 集成测试在无远程主机的环境下会假阳性失败；让默认跑测链路在所有机器上都能跑通。",
                next: "继续在交互 UX、模型路由、测试覆盖上加力（见 evolution_state.json）。"
            ),
            EvolutionEntry(
                version: "v0.3.0",
                date: "2026-08-25",
                commit: "6422947",
                tag: nil,
                summary: "账户 tab 退居 + 微信扫码登录门禁 + 输入/排队 UX",
                changes: [
                    "设置里新增\"账户\"tab，二维码扫码登录",
                    "移除侧边栏\"@ 插件\"菜单项，保留输入框内插入技能入口",
                    "消息输入加入排队/插话",
                    "用户消息操作条与头像/昵称展示"
                ],
                why: "在打开自进化循环前，先把\"谁能用、怎么用\"的用户层闸门和 UX 打磨好。",
                next: "v0.3.1+ 进入自进化基础设施阶段。"
            ),
        ]
    }

    private static func readLiveState() -> Result<EvolutionState, EvolutionLoadError> {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tapgo AICoding/state/evolution_state.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.notFound)
        }
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(EvolutionState.self, from: data)
            return .success(state)
        } catch {
            return .failure(.decodeFailed(error.localizedDescription))
        }
    }

    private static let placeholderEntry = EvolutionEntry(
        version: "v?",
        date: "—",
        commit: nil,
        tag: nil,
        summary: "暂无版本记录",
        changes: [],
        why: "",
        next: ""
    )

    // MARK: - Static content (playbook)

    private static func makePlaybook() -> [PlaybookSection] {
        return [
            PlaybookSection(
                icon: "hammer.fill",
                color: DSHTheme.brand,
                title: "开发软件：把 AI 当结对程序员",
                tips: [
                    "先给目标，再给约束。例如：「给 SwiftUI 加一个 sheet，沿用 DSHTheme 配色，宽度 640 高度 720」。",
                    "一次只问一件事。复杂任务用「先列计划 → 我确认 → 再动手」三段式，避免长 diff。",
                    "让它跑测试。我每次改完都会跑 TapgoTests，你看绿/红就知道稳不稳。",
                    "想回滚？每个版本都打了 git tag，告诉我「回滚到 v0.3.1」即可。"
                ]
            ),
            PlaybookSection(
                icon: "doc.text.fill",
                color: DSHTheme.success,
                title: "工作 / 文档：让 AI 替你写第一稿",
                tips: [
                    "粘贴上下文比描述场景快。把邮件、需求、bug 报告直接贴进来，让它基于事实改写。",
                    "明确角色。「你是技术写作助理，帮我把这段改得不像说明书」比「改好一点」有效 10 倍。",
                    "要表格、要大纲、要 markdown，**明示格式**——它会照办。",
                    "迭代比一次到位强。先骨架再润色，每轮告诉它哪里不对。"
                ]
            ),
            PlaybookSection(
                icon: "paintpalette.fill",
                color: DSHTheme.warn,
                title: "设计 / 创意：让 AI 当草图机器",
                tips: [
                    "用结构化提示：风格（极简 / 拟物 / 玻璃拟态）+ 主色 + 比例 + 用途（落地页 / 图标 / 海报）。",
                    "让它一次出 3 个方向，挑一个再细化。**多样性 > 单点完美**。",
                    "图标/SVG/HTML 直接要代码；位图素材走 imagegen 技能。",
                    "想要 Apple HIG / Material / iOS 26 液态玻璃等具体风格，**点名**，它认得。"
                ]
            ),
            PlaybookSection(
                icon: "ant.fill",
                color: DSHTheme.error,
                title: "调试 / 疑难：让 AI 当第二双眼睛",
                tips: [
                    "贴完整报错 + 触发路径 + 已尝试方案。三件套到位，命中率最高。",
                    "让它先**复述问题**再给答案。如果复述错了，你立刻知道方向偏了。",
                    "可疑假设直接列：「A/B/C 哪个是 root cause？」——它会逐个证伪。",
                    "长会话让它先 /thread 收个尾再继续，避免上下文越聊越糊。"
                ]
            ),
        ]
    }
}

// MARK: - Subviews

private struct EvolutionEntryRow: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let entry: EvolutionEntry
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.tag ?? entry.version)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isLatest ? DSHTheme.brand : .primary)
                if let commit = entry.commit {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(String(commit.prefix(7)))
                        .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(entry.date)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            Text(entry.summary)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.changes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.changes.prefix(3), id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(line)
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if entry.changes.count > 3 {
                        Text("…还有 \(entry.changes.count - 3) 条")
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if !entry.why.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("Why")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DSHTheme.brandSoft, in: Capsule())
                        .foregroundStyle(DSHTheme.brand)
                    Text(entry.why)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !entry.next.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("Next")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                    Text(entry.next)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
                .stroke(isLatest ? DSHTheme.brand.opacity(0.5) : DSHTheme.border,
                        lineWidth: isLatest ? 1.5 : 1)
        )
    }
}

private struct PlaybookRow: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let section: PlaybookSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(section.color.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: section.icon)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                        .foregroundStyle(section.color)
                }
                Text(section.title)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.semibold))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(section.tips.enumerated()), id: \.offset) { idx, tip in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)
                        Text(tip)
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
                .stroke(DSHTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Models

struct EvolutionEntry: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let commit: String?
    let tag: String?
    let summary: String
    let changes: [String]
    let why: String
    let next: String
}

struct PlaybookSection: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let tips: [String]
}

/// 镜像 `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`。
/// 字段不强制完全匹配——缺哪个就优雅降级。
struct EvolutionState: Codable {
    let version: String?
    let commitSha: String?
    let tag: String?
    let builtAt: String?
    let evolutionNote: String?
    let threadToResume: String?
    let nextActions: [String]?
    let stopConditions: [String]?
}


// MARK: - Errors

enum EvolutionLoadError: Error {
    case notFound
    case decodeFailed(String)

    var message: String {
        switch self {
        case .notFound: return "未找到 evolution_state.json（使用源码内置快照）"
        case .decodeFailed(let m): return "解析失败: \(m)"
        }
    }
}
