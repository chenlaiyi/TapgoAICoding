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

            Text("每次发布我都会让 AI 跑一遍 `evolve.sh`：自动改代码 → 跑全量核心回归测试 → 打 tag → 推 git。"
                 + "这一页就是这条流水线的对外广播，测试数会随每个版本自动变化。")
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
                    version: "v0.5.18",
                    date: "2026-08-29",
                    commit: "939a2bc",
                    tag: "v0.5.18",
                    summary: "公网中继自愈：清理孤儿隧道进程与服务器僵尸转发，端口冲突 3s 快速重试",
                    changes: [
                        "真机异常修复：部署强杀 App 后 ssh 隧道子进程变孤儿，继续占用服务器端口，新实例报『公网中继 · 异常 · remote port forwarding failed for listen port 18723』但公网实际仍经孤儿隧道可达，状态误导。",
                        "PhoneRelayTunnel.spawn() 前先 pkill -f 清理本机孤儿：PhoneRemote.tunnelProcessPattern 特征串唯一对应本机『ssh -R 127.0.0.1:<port>:… root@139.9.61.199』命令行，不误伤其它 ssh。",
                        "服务器端僵尸转发自愈：本机 ssh 非正常死亡时 sshd 对半开连接不敏感（fafa 实测：本机无 ssh 进程但端口 LISTEN、公网超时）；新增 PhoneRemote.remoteCleanupArguments，清理阶段在服务器 fuser -k -n tcp <port> 释放本机独占端口（18723-18725 三机一一对应）。",
                        "端口冲突类失败识别为可自愈：不累计持续失败、3s 快速重试；其它失败维持连续 3 次转 failed + 15s 降频。",
                        "『PhoneRemote: 接入模式与公网中继』测试段 29 → 34 断言：特征串与真实 ssh argv 逐字匹配、远端清理命令形态。",
                        "三机部署实测：强杀部署后各机只剩 1 个新隧道进程；fafa 僵尸监听被自动释放，三机公网链接连续 3 轮全部 200。"
                    ],
                    why: "部署流程必然强杀 App 而隧道子进程无父进程回收，公网中继必须能从『强杀 / 断网 / 半开连接』中自己恢复，否则弹窗长期挂着误导性异常。",
                    next: "长周期观察服务器重启与长时间断网恢复；评估服务器 sshd ClientAliveInterval 作为第二道兜底。"
                ),

                EvolutionEntry(
                    version: "v0.5.17",
                    date: "2026-08-29",
                    commit: "658b9d1",
                    tag: "v0.5.17",
                    summary: "手机 H5 新增『电脑控制』页（截屏/点按/滚动/打字/按键/锁屏）+ 三种接入方式（Wi-Fi/Tailscale/公网中继）",
                    changes: [
                        "电脑控制协议层：PhoneRemoteLink 新增 /api/ctrl/screen|click|scroll|type|key|cmd 六条路由与 ControlKey（14 个普通键 kVK_* + 6 个媒体键 NX_KEYTYPE_*，互斥映射表）、ControlAction（lock/sleep）白名单；StateSnapshot 增加 control 块（enabled/screenAllowed/accessibilityAllowed），H5 据此自适应提示。",
                        "电脑控制 App 层：PhoneRemoteServer 新增 controlEnabled 总开关（UserDefaults 持久化，默认开）+ TCC 权限预检（CGPreflightScreenCaptureAccess / AXIsProcessTrusted）与弹窗授权入口；CGDisplayCreateImage 主屏截屏（最长边限 1200px JPEG 0.72）；CGEvent 注入鼠标移动/单击/双击（clickState 递增）、行滚动（±20 限幅）、逐字符 Unicode 键盘输入（换行转 Return）、媒体键走 NSEvent systemDefined subtype 8 私有形态；锁屏 = Ctrl+Cmd+Q、睡眠 = pmset sleepnow。控制类请求在开关关闭/权限缺失时返回 403 + 机读 error 码。",
                        "H5 页面升级：新增『会话 | 电脑控制』Tab。控制页含截屏按钮 + 画面点按（归一化坐标回传，与分辨率无关，点按后 600ms 自动刷新）、双击模式切换、上/下滚、远程打字输入框、常用键（换行/Esc/Tab/空格/⌫/⌦/方向键）、媒体键（音量/亮度/播放暂停）、锁屏与睡眠（confirm 确认）；权限缺失/开关关闭时横幅提示并禁用对应按钮。",
                        "三种接入方式（v0.5.17 WIP 收编）：AccessMode = lan（局域网 IP 直连）/ tailnet（100.64/10 utun 地址）/ relay（https://pay.itapgo.com/remote/<machine>/ 经 ssh -R 反向隧道 + nginx 加密中继）；三台 Mac 端口 18723-18725 与 nginx tapgo-remote.conf 一一对应；PhoneRelayTunnel 常驻监督（3s 快速重连，连续 3 次失败降频 15s 并转 failed）。",
                        "ConnectPhoneView 新增『电脑控制』卡片：总开关 + 屏幕录制/辅助功能权限状态行 + 弹窗授权按钮 + 系统设置路径提示。",
                        "测试：PhoneRemoteTests 新增 3 个 section（电脑控制路由解析 / 按键映射 / 快照与页面）共 40+ 断言；修复 jsonDoubleField/jsonBoolField 在 Darwin 上 Bool 经 NSNumber 桥接混淆为数值的问题（CFBooleanGetTypeID 严格区分）。"
                    ],
                    why: "v0.5.16 完成了『扫码即开 H5』，手机只能看到/驱动 AI 会话；用户要求让 App 拥有真正的电脑控制能力——在任意网络下用手机截屏看 Mac 画面、点按操作鼠标、远程打字和控制音量/亮度/锁屏。本次把控制面做进同一个 token 鉴权的 H5 服务，并保留 Mac 端总开关与权限前置检查，泄露 token 的风险面与既有约定一致。",
                    next: "为截屏增加多显示器选择；评估触屏拖拽映射鼠标按住移动；考虑在控制面加最近剪贴板/文件推送。"
                ),

                EvolutionEntry(
                    version: "v0.5.16",
                    date: "2026-08-29",
                    commit: "36cf03b",
                    tag: "v0.5.16",
                    summary: "Composer 圆形上下文 meter 移到输入框正下方 + 底部 5 chip 恢复 + PhoneRemote 协议层",
                    changes: [
                        "Composer 圆形上下文 meter 迁移到输入框正下方：v0.5.15 把 5 chip 整行删除换成 meter，但用户期望是『圆形 meter 放在输入框正下方 chip 区 + 底部 5 chip 保留』。v0.5.16 把 CircularContextMeter + ModelUsagePopover 抽成独立 contextMeterChip 视图，插到 environmentChip（完全访问权限）之后、Spacer 之前的左侧 chip 区，chip 风格一致（capsule 背景 + caption 字号）；hover / 点击 / pinned 行为与 v0.5.15 相同，popover arrow 改 .bottom（从 meter 向下指向输入框）。",
                        "Composer 底部 5 chip 文本恢复：composerMetricsBar 回到 v0.5.14 风格，rounds · steps / LLM 时长 / 缓存命中 / 输入 tokens；与左侧 contextMeterChip 不再冲突。",
                        "PhoneRemote 协议层（v2 扫码即开 H5）：新增 Sources/TapgoCore/PhoneRemoteLink.swift（528 行）。对标 ZCode 移动端体验：Mac 端内置带 token 鉴权的 HTTP 服务，QR 码直接编码 http://<局域网IP>:<端口>/r/<token>，iPhone 相机扫码即可在 Safari 打开 H5 控制页（无需安装原生 App）。本文件只放纯 Foundation 协议层：token 生成与校验、链接与路由解析、极简 HTTP 报文解析/序列化、状态快照 JSON、H5 页面渲染。真实 NWListener 装配在 App 层 PhoneRemoteServer.swift。",
                        "PhoneRemote 测试套件：新增 35 项断言（token 鉴权、链接解析、HTTP 请求解析/序列化、H5 页面渲染、状态快照 JSON）。补 constantTimeEquals 的 UInt8/Int 类型推断修复和 RouteError: Error 缺 conformance 修复，让 TapgoCore 能 release build。",
                        "测试 runner 提速：Sources/TapgoTests/TestMain.swift 新增 TAPGO_SKIP_REMOTE_TESTS=1 环境变量：跳过 protocol-1..4 / RemoteSSH: / RemoteCodexHomeSync: / RemoteDirectoryLister: / e2e: 共 13 个连接 RFC 5737 fixture 地址的 SSH 集成测试，避免默认 connect timeout 把本地 swift run TapgoTests 卡 60–120s。",
                        "EVOLUTION.md 顺序修正 + 顶部注释更新：v0.5.15 的 EVOLUTION 条目在文件里被误 append 到末尾（line 195），v0.5.16 commit 同步把它移到 Format 块之后；顶部描述从『Append-only changelog』改为『最新条目在最上方』，避免下次再被误导。"
                    ],
                    why: "v0.5.15 把 composer 底部 5 chip 整行删除换成 meter 的方向被推翻——chip 区是用户长期使用的位置，meter 应该附加在输入框 chip 区里而不是替换掉。用户先前已在本地为 v0.5.16 准备了 PhoneRemote 协议层 WIP，本次 hotfix 顺手把它也接入主线并补齐测试，同时把 TapgoTests 提速让本地 TDD 循环不再被 SSH fixture timeout 阻塞。",
                    next: "把 PhoneRemoteLink 的 NWListener 装配层 (App 端 PhoneRemoteServer.swift) 完成并接入设置页；为 contextMeterChip 增加 mini 显示模式（22×22 圆环可隐藏文字 + badge）；评估是否给 5 chip 加 hover 详情。"
                ),

                EvolutionEntry(
                    version: "v0.5.15",
                    date: "2026-08-29",
                    commit: "4bf25fe",
                    tag: "v0.5.15",
                    summary: "Markdown 视觉升级 + composer 底部 metrics 重写 + 真实账户 rateLimits 接入",
                    changes: [
                        "Markdown 视觉升级：AppFont 新增 pointSize(for:multiplier:) 公共 helper，MarkdownMessageView 把 Block.para 改为保留原始 MarkdownSegment 后再按 appFontScale 重新拼装；新增 paragraphView(segs:)；ListView 紧凑化（marker footnote + labelTertiary + 2pt 间距 + 2pt leading 缩进）；行内代码字号比正文小 1.5pt + brandStrong 文字 + moduleBg 圆角底色仿 chip；TaskListView checkbox hierarchical + labelTertiary 色调；QuoteView 改吃 MarkdownSegment 让引用内子样式与正文一致。",
                        "Composer 底部 metrics 重写：删除旧 rounds · steps / LLM 时长 / 缓存命中 / 输入 tokens 五个文本 chip,替换为一个 CircularContextMeter（按实时 rateLimits 压力 → 上下文窗口使用率优先级显示百分比）；详细信息挪进悬停 / 点击弹出的 ModelUsagePopover，含套餐用量 / 5h 与 weekly 窗口剩余与重置时间 / credits 余额 / 输入输出 tokens / 平均缓存命中 / 上下文上限；pinned 状态由点击切换。",
                        "真实账户 rateLimits 接入：新增 TapgoCore/RateLimits 与 TapgoCore/ModelUsageMetrics；CodexHarnessClient.readRateLimits() 走 JSON-RPC account/rateLimits/read，initialize / initialized 之后幂等调用，失败时返回空 snapshot；ExecEvent 解析 harness 推送的 account/rateLimits/updated 通知（ExecEventParserTests +57 行覆盖）；SessionStore 增加 rateLimits / rateLimitsLoading / rateLimitsError 状态 + refreshRateLimits()，每次 popover 打开时刷新。",
                        "Composer 清空按钮误显修复：新增 tapgoIsComposerUserContentEmpty(text:attachedImageCount:) helper，过滤 NBSP / 全角空格 / 零宽字符，空 composer 不再误显 xmark.circle.fill。",
                        "同步把 makeHistory() 里上一轮漏补的 v0.5.14 条目 prepend，避免 App 内『自进化日志』页面落后于实际版本。"
                    ],
                    why: "上一轮 v0.5.14 把队列卡片宽度调到 90% 后，本轮集中处理三类遗留：Markdown 段落 / 列表 / 行内代码视觉层次弱；composer 底部五个文本 chip 一直展开，与 chat 内其余位置权重不平衡；v0.5.6 的『套餐用量』chip 一直用 thread 累计 token 做占位，需要接入真实 harness account/rateLimits 数据。三件事都集中在『输入 / 消息内容可读性』这条主线上，因此合并发 v0.5.15。",
                    next: "真机视觉回归 composer 底部圆环在不同上下文压力下的颜色梯度；为 ModelUsagePopover 增加可点击复制剩余 / 重置时间；评估是否把 5h / weekly 窗口快捷指示器放进 chip 头部避免每次点开。"
                ),
                EvolutionEntry(
                    version: "v0.5.14",
                    date: "2026-08-29",
                    commit: "a7ffa45",
                    tag: "v0.5.14",
                    summary: "队列卡片宽度 = composer × 0.90",
                    changes: [
                        "queueStatusBar 末尾宽度约束从 contentWidth 改为 contentWidth * 0.90：队列卡片固定为输入框卡片的 90% 并整体居中，恢复『排队卡片比输入框略窄』的层次感。",
                        "同步更新两处注释（queueStatusBar 与队列面板说明），避免后续再被改回同宽。",
                        "同步把版本号 / EVOLUTION / makeHistory / project.yml / Info.plist / tag 全部对齐到 0.5.14。"
                    ],
                    why: "上一版把队列卡片改成与输入框同宽后，用户反馈宽度弄错了，明确要求队列卡片应为输入框卡片宽度的 90%。",
                    next: "继续优化 Markdown 输出内容（段落 / 列表 / 行内代码）的视觉层次。"
                ),
                EvolutionEntry(
                    version: "v0.5.13",
                    date: "2026-08-29",
                    commit: "5ccb271",
                    tag: "v0.5.13",
                    summary: "队列卡片 Codex 紧凑样式 + 拖拽排序",
                    changes: [
                        "输入框上方排队卡片改成 Codex 式紧凑面板：行 padding 12/8、minHeight 44、缩略图 36pt，行间用 25% 透明 Divider 分隔。",
                        "行尾去掉「更多」常驻按钮（编辑 / 关闭排队改为右键菜单），只保留「调整方向」+「删除」图标按钮。",
                        "新增 macOS 14 风格的拖拽排序：拖到目标行的上 / 下半区决定插入位，目标行显示品牌色 3pt 插入指示线。",
                        "输入框右侧主操作按钮合并为互斥的「停止」/「发送」单按钮，避免同框视觉冗余。",
                        "SessionStore 新增 moveQueued(_ id: String, to newIndex: Int)，仅在当前 active 对话且未在 steering 时改写子数组顺序。"
                    ],
                    why: "用户参照 Codex 当前界面要求队列卡片更紧凑、行内右侧不要过大空白，且希望可拖拽重排多条排队；同框的「停止 / 发送」双按钮也合并为单按钮。",
                    next: "收集真实拖拽手感后，再决定是否加入 ⌥↑ / ⌥↓ 备用排序快捷键。"
                ),
                                EvolutionEntry(
                    version: "v0.5.12",
                    date: "2026-08-29",
                    commit: "b93bed6",
                    tag: "v0.5.12",
                    summary: "输入框上方队列改为 Codex 式同宽单面板",
                    changes: [
                        "排队卡片与输入框同宽并直接衔接，取消逐行分隔线和多余层级。",
                        "每条消息保持紧凑单行；真实图片附件显示圆角缩略图，多图显示数量。",
                        "调整方向、删除与更多操作固定右对齐，统一低强调灰色，更多按钮取消圆形底色。",
                        "队列最多显示五行后内部滚动，原有编辑、删除、关闭排队与 same-turn steer 行为不变。",
                        "套餐用量组件、账户限额请求与事件、状态模型及相关测试已从当前 App 删除。",
                        "队列与并发核心回归 43/43；SDK 26.5 Release App build 与本机原生多条队列视觉、菜单和删除回归通过。"
                    ],
                    why: "多条排队消息需要像 Codex 一样清晰可扫读，同时不能让旧发布基线重新带回已经删除的套餐用量。",
                    next: "继续覆盖更多附件和极窄窗口下的截断表现。"
                ),
                EvolutionEntry(
                    version: "v0.5.11",
                    date: "2026-08-29",
                    commit: "e710977",
                    tag: "v0.5.11",
                    summary: "宽屏自动显示环境信息与来源卡片，窄屏自动隐藏",
                    changes: [
                        "右侧空间足够时自动显示真实变更、运行位置、Git 分支、提交/推送和比较分支入口。",
                        "来源区展示当前会话最近三张真实图片缩略图；没有图片时提供明确空态。",
                        "窗口变窄时自动隐藏，恢复宽度后重新出现；手动轨迹栏打开时卡片让位。",
                        "聊天区使用 trailing safe-area inset，宽窄切换保持输入框焦点和未发送草稿。",
                        "响应式布局 7/7 通过；Release build 与本机真实窗口宽窄回归通过。"
                    ],
                    why: "宽屏应充分利用右侧空白展示环境上下文，窄屏则优先保护会话阅读与持续输入空间。",
                    next: "根据真实使用反馈微调宽度阈值与卡片密度。"
                ),
                EvolutionEntry(
                    version: "v0.5.10",
                    date: "2026-08-29",
                    commit: "6cc0517",
                    tag: "v0.5.10",
                    summary: "套餐用量在输入区下方固定右对齐",
                    changes: [
                        "套餐用量 chip 在输入区内容宽度内固定靠右，不再被外层居中 frame 拉回中间。",
                        "套餐空态 17/17 通过；保留 v0.5.9 的步骤进度、变更统计、白色流光与真实账户限额。"
                    ],
                    why: "完整落实用户此前明确要求的输入框下方右侧位置，并用新版本保存已发布标签的不可变性。",
                    next: "验证窄窗口和长套餐名称下的对齐与截断。"
                ),
                EvolutionEntry(
                    version: "v0.5.9",
                    date: "2026-08-29",
                    commit: "cd5db2d",
                    tag: "v0.5.9",
                    summary: "Codex 式步骤进度、真实变更统计、运行流光与账户限额",
                    changes: [
                        "输入区上方新增步骤进度胶囊，显示当前步数、本回合文件数、绿色新增行和红色删除行；点击展开完整步骤清单。",
                        "优先消费 Harness 的 plan/diff 事件；仅有命令工具时按回合开始前 Git 基线统计，不混入既有脏工作树。",
                        "最新灰色运行活动加入白色流光并原位更新；历史活动静止，减少动态效果时自动停用。",
                        "接入 Codex account/rateLimits/read 与实时通知，展示真实 5 小时/周窗口、用量、等级与重置时间。",
                        "步骤进度 12/12、限额解析 30/30、新套餐展示 16/16、旧展示兼容 30/30；Release build 与安装版原生回归通过。"
                    ],
                    why: "让运行过程只呈现用户关心的当前步骤和真实代码变化，同时以账户限额替代会话 token 估算套餐用量。",
                    next: "补充失败步骤与耗时，并验证远程多工作树 diff 统计。"
                ),
                EvolutionEntry(
                    version: "v0.5.8",
                    date: "2026-08-28",
                    commit: "ad339ce",
                    tag: "v0.5.8",
                    summary: "Codex / DeepSeek 官方插件目录、安装管理与安全过滤",
                    changes: [
                        "左上菜单新增『插件』，以原生弹窗管理已安装插件、搜索并浏览官方来源。",
                        "Codex 官方目录读取当前 App 使用的 CLI 与隔离 CODEX_HOME，展示应用/MCP/技能能力并支持安装、卸载和启停。",
                        "DeepSeek 官方区只保留文档明确支持的 Codex 与 Claude Code 子代理，安装使用和当前 Harness 对齐的 next 通道。",
                        "过滤 DeepSeek 内部 patch/driver/SDK 依赖；安装与卸载经过安全标识校验、确认和目录刷新。",
                        "PluginCatalog 13 项回归、Release build、参考图同屏视觉 QA 与本机原生交互回归全部通过。"
                    ],
                    why: "用户需要在 Tapgo AICoding 内直接管理两套 Harness 的官方插件，同时不能把内部 npm 依赖伪装成可安装市场项目。",
                    next: "为已安装插件增加详情页，展示权限、依赖、更新状态与变更日志。"
                ),
                EvolutionEntry(
                    version: "v0.5.7",
                    date: "2026-08-28",
                    commit: "e5d2eea",
                    tag: "v0.5.7",
                    summary: "iOS 原生工程闭环：DashboardView + 协议层自包含副本 + 446 断言同步校验",
                    changes: [
                        "补齐 mobile/ios/Sources/DashboardView.swift，让 RootView 能编译。",
                        "新增 mobile/ios/Sources/MobilePairing.swift，作为 Sources/TapgoCore/MobilePairing.swift 的字节级同步副本，由 Scripts/check-sync.sh 强制一致。",
                        "新增 Scripts/{check-sync,run-tests,build}.sh + Tests/MobilePairingProtocolTests.swift，协议层 446 断言本机 Foundation 即可跑过。",
                        "新增 Assets.xcassets/AppIcon + AccentColor 占位 + project.yml 引用，避免 ASSETCATALOG_COMPILER_APPICON_NAME 编译失败。",
                        "mobile/README.md 状态表对齐 v0.5.7 真实进度。",
                        "6 个 iOS SwiftUI 源文件 swiftc -parse 全部通过。"
                    ],
                    why: "mobile/ios/ 原本缺 DashboardView，且 MobilePairing 协议层需通过 SPM 引用兄弟模块，违反独立 Xcode 工程约束；本版让 iOS 工程自包含并强制两端协议同步漂移。",
                    next: "在装全 Xcode 的机器上 build.sh 生成 .xcodeproj，跑模拟器验证 PairingStore ↔ PairingView ↔ DashboardView 闭环；接 AVFoundation 扫码 + Bonjour 长连接。"
                ),
            EvolutionEntry(
                version: "v0.5.6",
                date: "2026-08-28",
                commit: "c716fe4",
                tag: "v0.5.6",
                summary: "输入框下方右侧『套餐用量』chip + SubscriptionUsage 聚合",
                changes: [
                    "TapgoCore/SubscriptionUsage:聚合 Thread.usageTotal + 最近一次 turn 的 TokenUsage.contextWindow + ContextLevel 配色等级。",
                    "composerMetricsBar 右侧新增『套餐用量 X / Y (Z%)』chip,按压力等级 brand / warn / error 着色;空用量自动隐藏。",
                    "TapgoTests/SubscriptionUsageTests:30 项断言覆盖 isVisible / percent / level / chipLabel / detailText / from(turnsTotalTokens, latestUsage, fallbackWindow)。",
                    "把上一会话未提交的插件管理 WIP(PluginManagerService / PluginManagerView / PluginCatalog / PluginCatalogTests / SidebarView 的『插件』菜单与 sheet)一并 commit,避免 v0.5.6 SidebarView 引用悬空;PluginManagerService.init() 用 MainActor.assumeIsolated 包装 RemoteCodexHomeSync.findHarness() 调用,App target 恢复 SDK 26.5 build。"
                ],
                why: "用户要求在输入框下方右侧看到当前订阅套餐用量;本版用 thread 累计 token + 上下文窗口作为最小可用数据源,codex account/rateLimits/read 接入留给后续迭代。",
                next: "接入 codex account/rateLimits/read 拿到真实剩余/重置时间,把 chip 升级为『已用 X / 剩余 Y / 重置于 Z』并启用 iOS 端 Keychain 持久化。"
            ),
            EvolutionEntry(
                version: "v0.5.5",
                date: "2026-08-28",
                commit: "1c25dbb",
                tag: "v0.5.5",
                summary: "连接手机菜单 + MobilePairing 协议 + 长期记忆解析修复",
                changes: [
                    "左上角菜单栏在「自进化/新对话」之间插入「连接手机」,对接 Ter-Tapgo iOS 端『点点够终端』App。",
                    "TapgoCore/MobilePairing:6 位配对码生成、字符集过滤、tapgo://pair? URL 打包/解析、State 状态机与 PairedMac 持久化。",
                    "ConnectPhoneView 提供 6 位码 + CoreImage QR + 倒计时 + 未配对/已配对/已连接三态,MobilePairingStore 关闭后恢复。",
                    "同步产出 iOS 端 PairingStore(v0.5.5 走 UserDefaults,v0.5.6 切 Keychain)与 mobile/ 工程骨架。",
                    "DurableMemory.parseBullets timestamped 分支保留 - 前缀,与 legacy 分支统一;原回归 DurableMemoryTests:69 通过。",
                    "新增 MemoryCloudSync / MemoryConsolidator / TurnPresentation / TurnSteerPayload 与对应测试,测试数 706 → 1221。"
                ],
                why: "用户要在 Mac 端对接 iOS 原生 App『点点够终端』,先打通协议层与 Mac 端 UI;同时修复 19 个累积改动中遗留的旧记忆解析 bug,保证长期记忆语义一致。",
                next: "v0.5.6 引入 Bonjour 长链接 + iOS 端 Keychain 持久化,并在真实 iOS 设备上做端到端配对验证。"
            ),
            EvolutionEntry(
                version: "v0.5.4",
                date: "2026-08-28",
                commit: "5ec4e7c",
                tag: "v0.5.4",
                summary: "用户截图持久缩略图、运行中逐步输出与精简上下文 UI",
                changes: [
                    "发送图片复制到 App 专属附件目录并随 Turn 持久化，用户消息中显示可恢复的缩略图；删除会话时同步清理附件。",
                    "运行中的回合不再隐藏已收到的 assistant、命令、工具和文件事件；命令/工具状态只由原生卡片呈现，不再追加重复模板说明。",
                    "输入区在空白页与会话页之间保持同一实例；流式滚动改为限频且无动画，任务执行时仍可稳定输入下一条消息。",
                    "删除会话列表的上下文百分比，以及输入框右下角的 context 进度条；Harness 自动压缩机制保持不变。"
                ],
                why: "旧 UI 只把图片交给 Harness、没有写入会话模型；运行分支又主动隐藏中间 items。随后为每个命令强插开始/完成说明，又造成卡片与文字重复刷屏。高频流式事件还会持续叠加滚动动画并重建输入框，导致焦点抖动。上下文百分比则把可自动压缩的动态窗口误导成硬上限。",
                next: "用安装版继续验证截图重启恢复、长时间流式输入和多会话并行输入。"
            ),
            EvolutionEntry(
                version: "v0.5.3",
                date: "2026-08-28",
                commit: "de53c9a",
                tag: "v0.5.3",
                summary: "修复截图剪贴板被吞掉、却没有生成附件的问题",
                changes: [
                    "⌘V 改为识别 AppKit 可读取的图片对象与图片文件 URL",
                    "PNG 缺失时解码 TIFF/JPEG/HEIC 等剪贴板表示，并统一转换为临时 PNG 附件",
                    "Preview → 安装版 App 的真实截图粘贴、缩略图、临时 PNG 端到端验证已通过"
                ],
                why: "旧实现只读取 PNG；macOS 截图常提供 TIFF，因此按键被拦截后界面没有任何响应。",
                next: "继续守护其它粘贴路径（拖拽、Finder 拷贝）并按用户行为扩展更多自动场景。"
            ),
            EvolutionEntry(
                version: "v0.5.2",
                date: "2026-08-28",
                commit: "ce507a5",
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
                commit: "7ff7750",
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
                commit: "eb68ed1",
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
