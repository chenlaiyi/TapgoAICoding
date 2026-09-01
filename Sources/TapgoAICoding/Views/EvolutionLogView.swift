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

    private enum Tab { case history, playbook }
    @State private var tab: Tab = .history
    /// 展开显示完整 changes/why/next 的条目（按 version 定位，源码内置
    /// 数据重载后仍然稳定）。默认只展开最新一条。
    @State private var expandedVersions: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            currentVersionBar
            Divider()
            picker
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch tab {
                    case .history:
                        historyIntro
                        ForEach(history) { entry in
                            EvolutionEntryRow(
                                entry: entry,
                                isLatest: entry.version == history.first?.version,
                                isExpanded: expandedVersions.contains(entry.version)
                            ) {
                                toggleExpanded(entry.version)
                            }
                        }
                    case .playbook:
                        playbookSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 640, height: 720)
        .background(DSHTheme.bg)
        .onAppear(perform: initialExpansion)
    }

    private func toggleExpanded(_ version: String) {
        if expandedVersions.contains(version) {
            expandedVersions.remove(version)
        } else {
            expandedVersions.insert(version)
        }
    }

    /// 默认展开最新一条，其余收起——用户看到的是"当前 + 可下钻的历史"。
    private func initialExpansion() {
        loadLiveState()
        guard expandedVersions.isEmpty, let latest = history.first?.version else { return }
        expandedVersions = [latest]
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DSHTheme.brand.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSHTheme.brand)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("自进化日志")
                    .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                Text("\(history.count) 次进化 · 测试全绿才发布 · 每版一个 tag")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Current version bar (compact, source-of-truth = built-in history)

    /// 当前版本条。**只信源码内置的 history.first**——它随发版更新；
    /// evolution_state.json 是 evolve.sh 落盘的快照，经常滞后（曾停在
    /// v0.5.3 四天），不能再作为"当前版本"的数据源。
    private var currentVersionBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(latest.tag ?? latest.version)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(DSHTheme.brand)
            Text(latest.date)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            if let sha = latest.commit {
                Text(shortCommit(sha))
                    .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            Text(latest.summary)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("本次进化")
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(DSHTheme.brandSoft, in: Capsule())
                .foregroundStyle(DSHTheme.brand)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DSHTheme.bgLayer1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前版本 \(latest.tag ?? latest.version)：\(latest.summary)")
    }

    private var latest: EvolutionEntry {
        history.first ?? EvolutionLogView.placeholderEntry
    }

    // MARK: - Tab picker

    private var picker: some View {
        HStack(spacing: 4) {
            tabButton("历史版本", count: history.count, tab: .history)
            tabButton("使用指南", count: nil, tab: .playbook)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func tabButton(_ title: String, count: Int?, tab target: Tab) -> some View {
        Button {
            self.tab = target
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).monospacedDigit())
                }
            }
            .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(self.tab == target ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(self.tab == target ? DSHTheme.brandSoft : Color.clear, in: Capsule())
            .foregroundStyle(self.tab == target ? DSHTheme.brand : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)\(count.map { "，\($0) 条" } ?? "")")
    }

    // MARK: - History

    /// 理念压缩成一行——完整说明移到 README/使用指南，不再占一整张卡。
    private var historyIntro: some View {
        Text("每次发布：AI 改代码 → 全量核心回归 → tag → push。点任意版本展开改动明细。")
            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            .foregroundStyle(.tertiary)
            .padding(.bottom, 2)
    }

    // MARK: - Playbook (how to use me better)

    private var playbookSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("亲测能让你事半功倍的用法，按场景挑。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            VStack(spacing: 8) {
                ForEach(playbook) { section in
                    PlaybookRow(section: section)
                }
            }
        }
    }

    // MARK: - Helpers

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
                    version: "v0.5.69",
                    date: "2026-09-01",
                    commit: "随 v0.5.69",
                    tag: "v0.5.69",
                    summary: "仿 ZCode 内容输出样式",
                    changes: [
                        "回合内每个事件（思考/查阅/终端/编辑/读取）各占一行安静灰底短行，显示具体内容；连续搜索类合并为查阅计数行；失败事件标执行失败。",
                        "文件编辑改成安静单行 +A -B 摘要；完成后折叠为已工作芯片 + N 个文件已更改横条。"
                    ],
                    why: "原 ZCode-style 折叠把工作日志藏得太深，每个事件都该让用户看到具体内容。",
                    next: "登录模型账号后真机看 UI 视觉与展开交互。"
                ),

                EvolutionEntry(
                    version: "v0.5.68",
                    date: "2026-09-01",
                    commit: "随 v0.5.68",
                    tag: "v0.5.68",
                    summary: "检查更新弹窗改简体中文",
                    changes: [
                        "Info.plist 声明 CFBundleLocalizations（zh-Hans/zh_CN/en），Sparkle 不再回退英文。",
                        "构建时把 Sparkle 框架的 zh_CN.lproj 镜像为 zh-Hans.lproj，匹配现代系统语言标记 zh-Hans-US。"
                    ],
                    why: "Sparkle 界面语言 = 应用声明语言 ∩ 框架资源语言，声明缺失与新旧命名不匹配两处都断在中文。",
                    next: "观察下次真实发版时两台机器的更新弹窗是否全程中文。"
                ),

                EvolutionEntry(
                    version: "v0.5.67",
                    date: "2026-09-01",
                    commit: "随 v0.5.67",
                    tag: "v0.5.67",
                    summary: "恢复聊天右侧自适应环境卡自动显示",
                    changes: [
                        "宽窗口（≥1428pt，宽输入 ≥1688pt）且有活跃会话、工作台未打开时，聊天右侧自动出现环境速览卡。",
                        "打开工作台或窗口变窄时卡片自动让位；'打开完整轨迹栏'可一键进入工作台。"
                    ],
                    why: "用户需要宽窗口下自动出现的环境速览卡，恢复 v0.5.58 的响应式策略并与工作台面板自然互斥。",
                    next: "两机部署后观察窄窗口/宽输入偏好切换时卡片的显隐是否跟手。"
                ),

                EvolutionEntry(
                    version: "v0.5.66",
                    date: "2026-09-01",
                    commit: "随 v0.5.66",
                    tag: "v0.5.66",
                    summary: "自绘分隔条实现拖宽自动弹出环境信息",
                    changes: [
                        "主会话与工作台分栏改为自绘分隔条，拖宽工作台到 ≥560pt 自动弹出环境抽屉，松手时以完整位移判定。",
                        "仅向加宽方向触发，向右收窄不误弹；真机验证三条呼出路径全部通过。"
                    ],
                    why: "HSplitView 内置分隔条拖动期间宽度事件不触发，宽度监听方案不可行；只有分隔条自己的手势能同时承担分栏与弹出判定。",
                    next: "两机部署后由真实鼠标复验拖宽弹出手感，必要时调整 560pt 阈值。"
                ),

                EvolutionEntry(
                    version: "v0.5.65",
                    date: "2026-09-01",
                    commit: "随 v0.5.65",
                    tag: "v0.5.65",
                    summary: "真机复验收口：拖拽阈值 3pt + 拖宽弹出步进误判修复",
                    changes: [
                        "贴边窗口手柄拖拽阈值从 6pt 降到 3pt：窗口最外侧数 pt 是系统缩放边框，中部起拖最多约 5pt 位移。",
                        "修复拖宽自动弹出：分隔条拖动是每步 3–5pt 的连续小步，单步增量判定永远不满足；改为宿主窗口宽度未变且工作台 ≥560pt 即弹出。"
                    ],
                    why: "v0.5.64 的阈值按理想化输入设计，真机复验暴露了系统缩放边框与连续小步拖动两个物理事实。",
                    next: "部署两机后重跑三条路径（贴边拖拽/点击/拖宽弹出）直至全绿。"
                ),

                EvolutionEntry(
                    version: "v0.5.64",
                    date: "2026-09-01",
                    commit: "随 v0.5.64",
                    tag: "v0.5.64",
                    summary: "修复右缘拖拽展开环境信息在贴边窗口下失效",
                    changes: [
                        "右缘环境手柄支持点击直接展开，拖拽阈值从 24pt 降到 6pt，窗口贴住屏幕右缘时小位移也能触发。",
                        "新增拖宽自动弹出：工作台分栏拖宽到 ≥560pt 自动弹出环境抽屉，仅分隔条拖动触发并带防回弹闩锁。"
                    ],
                    why: "全屏宽窗口下向右位移不足旧阈值，拖拽手势几何不可达；拖到一定宽度自动弹出此前从未实现。",
                    next: "三机安装后用真实拖拽复验贴边窗口与拖宽弹出两条路径。"
                ),

                EvolutionEntry(
                    version: "v0.5.63",
                    date: "2026-09-01",
                    commit: "随 v0.5.63",
                    tag: "v0.5.63",
                    summary: "修复侧栏头像被撑成大矩形",
                    changes: [
                        "头像改为渲染层预裁剪的 28pt 圆形小图并缓存，规避 macOS 26 菜单把 label 里的图片按原图尺寸抽走渲染的缺陷。",
                        "套餐信息行移出账户菜单 label 单独渲染，恢复供应商·套餐·周余量灰色行。"
                    ],
                    why: "macOS 26 的 Menu 只保留 label 首个 Text 与 Image 且图片按位图原尺寸绘制，头像被撑成 132pt 原图、套餐行被丢弃。",
                    next: "三机安装后确认不同头像与未登录态下的底栏表现。"
                ),

                EvolutionEntry(
                    version: "v0.5.62",
                    date: "2026-09-01",
                    commit: "随 v0.5.62",
                    tag: "v0.5.62",
                    summary: "侧栏底部收敛为账户菜单",
                    changes: [
                        "移除侧栏底部的手机工具菜单与设置按钮，套餐摘要获得完整宽度。",
                        "连接手机、自进化日志、自进化、检查更新、设置和退出登录统一收入点击用户区后的上拉菜单。"
                    ],
                    why: "底部右侧控件挤占套餐信息，且常用入口分散在多个小按钮里。",
                    next: "在真实窗口确认菜单展开方向与长套餐文案显示。"
                ),

                EvolutionEntry(
                    version: "v0.5.57",
                    date: "2026-08-31",
                    commit: "随 v0.5.57",
                    tag: "v0.5.57",
                    summary: "管理员登录页品牌化重设计",
                    changes: [
                        "管理员登录页改为用户选定的左右分栏布局，左侧品牌区、右侧高对比微信扫码区。",
                        "登录页直接读取主 App 的真实应用图标，logo 与 App 图标保持一致。",
                        "新增真实位图品牌背景、扫码状态与刷新入口，并完成同视口完整和聚焦视觉 QA。"
                    ],
                    why: "原登录页层级、对比度与留白失衡，品牌标志还可能与真实应用图标不一致。",
                    next: "继续观察不同窗口尺寸与系统字号下的二维码可读性。"
                ),

                EvolutionEntry(
                    version: "v0.5.56",
                    date: "2026-08-31",
                    commit: "随 v0.5.56",
                    tag: "v0.5.56",
                    summary: "GitHub Releases 自动更新",
                    changes: [
                        "左上角和应用菜单新增检查更新入口，并同步 Sparkle 的可检查状态。",
                        "接入 Sparkle 2.9.6，启动立即后台检查，之后每小时检查、下载并安全安装 GitHub Release。",
                        "更新归档使用 Keychain EdDSA 私钥签名，构建产物同时验证 Developer ID、Framework 嵌入和 SHA-256。"
                    ],
                    why: "旧版只能手工复制安装，缺少用户可见入口与可信的自动更新链路。",
                    next: "用 v0.5.57 做首次跨版本自动替换验收。"
                ),

                EvolutionEntry(
                    version: "v0.5.55",
                    date: "2026-08-31",
                    commit: "随 v0.5.55",
                    tag: "v0.5.55",
                    summary: "Tapgo Computer Use 对齐 Codex Computer Use",
                    changes: [
                        "主 API 对齐 Codex 的 11 个同名工具及参数语义，同时保留 8 个旧版兼容别名。",
                        "补齐应用自动启动、状态差量、三键连击、窗口拖拽、元素滚动、xdotool 风格按键、剪贴板恢复、文本选择和次级 AX 动作。",
                        "把 Codex Computer Use 的即时确认边界注入新会话，第三方页面内容不能充当用户授权。"
                    ],
                    why: "旧版只有部分语义点击能力，工具名相似但缺少多项 Codex Computer Use 核心原语，不能称为 1:1。",
                    next: "持续在不同原生与 Electron App 上回归 AX 完整度，并保持三机 Helper/TCC 分层验收。"
                ),

                EvolutionEntry(
                    version: "v0.5.54",
                    date: "2026-08-31",
                    commit: "随 v0.5.54",
                    tag: "v0.5.54",
                    summary: "ZCode 模型配置整窗复刻与运行链路统一",
                    changes: [
                        "按 ZCode 实机同视口复刻整窗设置导航、供应商侧栏、连接方式、套餐额度概览与模型操作。",
                        "ProviderRegistry 统一模型选择、端点、Key、config.toml 和目录生成，GLM-5.3、GLM-5-Turbo 与自定义 Provider 可真实用于新会话。",
                        "修复迁移旧 auth 文件后启动误报未配置；模型页统一显示真实剩余额度，MiniMax/智谱展示窗口、DeepSeek 展示账户余额。"
                    ],
                    why: "模型配置不仅要与 ZCode 视觉一致，选择结果也必须进入真实 Harness 运行链路。",
                    next: "根据真实使用反馈继续收紧设置页细节。"
                ),

                EvolutionEntry(
                    version: "v0.5.53",
                    date: "2026-08-31",
                    commit: "e3ff8ea",
                    tag: "v0.5.53",
                    summary: "模型供应商与模型两层注册表",
                    changes: [
                        "新增 Provider、ProviderModel 与 ProviderRegistry，并从旧模型和 auth 文件安全迁移。",
                        "模型设置页引入供应商分组、连接测试、模型编辑和自定义供应商。"
                    ],
                    why: "为 ZCode 式供应商/模型两层配置建立数据基础。",
                    next: "整窗复刻并统一实际 Harness 运行链路。"
                ),

                EvolutionEntry(
                    version: "v0.5.51",
                    date: "2026-08-31",
                    commit: "4610726",
                    tag: "v0.5.51",
                    summary: "电脑控制从全屏盲点升级为目标应用语义操作",
                    changes: [
                        "Accessibility 扫描深度 12 → 32、元素上限 220 → 600，并跳过关闭菜单的无关子树，可稳定读取 ZCode Electron 深层 WebArea 控件。",
                        "新增 set_element_value；截图、点击、按键、输入与滚动均可绑定目标 App，应用窗口截图与坐标统一，并修复旧 Y 轴翻转错误。",
                        "新会话强制执行确认应用、联合观察、语义操作和每步复核；连续失败停止盲点，同时修复多行 base instructions 的 JSON 转义；完整回归 2411/2411。"
                    ],
                    why: "旧实现只读到 Electron 外壳，且全屏坐标不锁定 App；焦点漂移后会误点其他窗口，无法完成 ZCode 模型配置。",
                    next: "三机同步 0.5.51；已授权机器扩大 Electron 表单回归，未授权机器完成本机 TCC 后再验收。"
                ),

                EvolutionEntry(
                    version: "v0.5.50",
                    date: "2026-08-30",
                    commit: "7668a47",
                    tag: "v0.5.50",
                    summary: "本地化应用名启动不再假成功",
                    changes: [
                        "open_application 等待 /usr/bin/open 完整退出并检查退出码，不再把进程创建成功误报为应用启动成功。",
                        "英文 bundle 名失败后按 Spotlight 本地化显示名索引解析 .app；中文「计算器」可定位 Calculator.app，bundle id 仍由 NSWorkspace 解析。",
                        "JKMac mini 实测调用前无 Calculator 进程，中文启动后产生新 PID，并可继续用中文名读取 com.apple.calculator 界面树；完整回归 2397/2397。"
                    ],
                    why: "v0.5.49 的权限桥接已打通，但验收使用英文 Calculator 绕过了中文名称找不到应用且仍返回成功的问题。",
                    next: "三机同步 0.5.50；另外两台完成本机 TCC 双授权后做相同真实会话回归。"
                ),

                EvolutionEntry(
                    version: "v0.5.49",
                    date: "2026-08-30",
                    commit: "535ae92",
                    tag: "v0.5.49",
                    summary: "正式签名 Helper 桥接打通真实电脑控制",
                    changes: [
                        "MCP stdio 将每次 tools/call 通过 Launch Services 交给独立 Helper 一次性执行，让 TCC 始终按稳定 bundle 身份判断权限。",
                        "桥接临时文件增加所有者、0700 权限、固定路径、无符号链接和请求大小校验，避免任意路径读写。",
                        "构建脚本优先使用 Tapgo Developer ID 正式签名并加时间戳，无证书环境才显式回退 ad-hoc。",
                        "JKMac mini 已完成双权限授权；底层 MCP 与真实 Tapgo 会话均完成截图、启动 Calculator、读树、点击数字 7、再次读树和截图，显示值 7 → 77；完整回归 2397/2397。"
                    ],
                    why: "设置探测由 Launch Services 启动 Helper，真实 MCP 却由 Harness 直接执行 bundle 内二进制，TCC 归因身份不同，造成界面显示已授权但截图和元素操作仍失败。",
                    next: "同步同一份正式签名构建到另外两台 Mac；各机首次使用时完成本机 TCC 授权并做相同回归。"
                ),

                EvolutionEntry(
                    version: "v0.5.48",
                    date: "2026-08-30",
                    commit: "083a560",
                    tag: "v0.5.48",
                    summary: "独立安装电脑控制 Helper 并修复真实拖拽入口",
                    changes: [
                        "参照 ZCode 将内嵌 Helper 原子安装到用户 Application Support，权限、探测和 MCP 共用稳定的独立 App。",
                        "以 AppKit NSDraggingSession 和原生 NSURL 生成 Finder 式文件拖拽；授权浮窗可获得焦点并回显拖拽状态。",
                        "JKMac mini 已验证当前 Helper 可加入屏幕录制列表并取得授权；完整离线回归 2397/2397。"
                    ],
                    why: "旧流程拖动主 App Resources 内的嵌套 bundle，授权对象、MCP 进程和升级后的 TCC 身份不一致；ZCode 实际先安装独立 Helper 再拖动。",
                    next: "经确认后清理 JKMac mini 的失效辅助功能旧记录并重新授权；正式发布签名改用稳定 Developer ID。"
                ),

                EvolutionEntry(
                    version: "v0.5.47",
                    date: "2026-08-30",
                    commit: "f361cfd",
                    tag: "v0.5.47",
                    summary: "修复授权浮窗抢占 Helper 拖拽",
                    changes: [
                        "禁止授权浮窗整体移动，关闭 AppKit 的窗口背景拖动。",
                        "保留 Tapgo Computer Use 卡片的真实 .app 文件拖拽提供器。",
                        "拖动卡片时不再带着整个浮窗移动；完整离线回归 2394/2394。"
                    ],
                    why: "AppKit 的窗口背景拖动先于 SwiftUI onDrag 消费手势，导致用户拖的是浮窗而不是 Helper App。",
                    next: "在两个系统权限页面分别完成真实拖入授权回归。"
                ),

                EvolutionEntry(
                    version: "v0.5.46",
                    date: "2026-08-30",
                    commit: "309e3c2",
                    tag: "v0.5.46",
                    summary: "电脑控制独立 Helper 与系统授权拖拽引导",
                    changes: [
                        "新增独立 Tapgo Computer Use.app，以固定 bundle id 承载系统权限与电脑控制 MCP。",
                        "辅助功能和屏幕录制分别直达对应系统设置，并显示可拖入允许列表的置顶 Helper 面板。",
                        "权限状态通过 Launch Services 启动 Helper 回读，避免宿主进程权限污染；Composer 与设置页统一使用 Helper 真值。",
                        "MCP 配置迁移到嵌套 Helper 可执行文件，完整离线回归 2394/2394。"
                    ],
                    why: "原实现没有稳定的系统授权身份，也只有通用设置链接，无法完成 ZCode 式可理解、可操作、可验证的电脑控制授权闭环。",
                    next: "用户授权三台 Mac 后分别实测截图、元素树读取、点击和输入链路。"
                ),

                EvolutionEntry(
                    version: "v0.5.45",
                    date: "2026-08-30",
                    commit: "e174ceb",
                    tag: "v0.5.45",
                    summary: "电脑控制界面验收修复",
                    changes: [
                        "电脑控制两个开关固定使用 macOS 滑动样式，避免在设置卡片中渲染为复选框。",
                        "输入区电脑操作入口改用携带初始页的 sheet 状态，首次点击也能稳定直达电脑控制设置。",
                        "保留 v0.5.44 已发布标签，修复以新版本交付，不改写远端历史。"
                    ],
                    why: "真实界面验收发现开关视觉形态和首次直达页面存在偏差，需要在不改写既有发布的前提下完成修复。",
                    next: "三机授权后验证语义元素点击；继续补按元素输入、滚动与多显示器选择。"
                ),

                EvolutionEntry(
                    version: "v0.5.44",
                    date: "2026-08-30",
                    commit: "c39cbda",
                    tag: "v0.5.44",
                    summary: "电脑控制完整启停、输入区入口与 Accessibility 语义操作",
                    changes: [
                        "补齐电脑控制总开关与输入框入口显示偏好：总开关真实注册/移除 MCP，显示开关只控制 Composer 快捷入口。",
                        "Composer 新增电脑操作 chip，以绿/橙/灰状态点显示已就绪、缺权限与已关闭，点击直达电脑控制设置。",
                        "MCP 工具 8 → 11：新增应用枚举、Accessibility 界面树读取和按元素点击；安全输入框内容强制隐藏。",
                        "启动与模型配置重写均尊重总开关；配置移除与参数边界补齐测试，完整离线回归 2390/2390。"
                    ],
                    why: "上一版只有状态与手动注册，没有真正的能力启停和 Composer 入口；截图坐标操作也不足以覆盖 Codex 风格的语义电脑控制。",
                    next: "三机授权后验证语义元素点击；继续补按元素输入、滚动与多显示器选择。"
                ),

                EvolutionEntry(
                    version: "v0.5.43",
                    date: "2026-08-30",
                    commit: "b4a7597",
                    tag: "v0.5.43",
                    summary: "参考 ZCode 重构设置中心",
                    changes: [
                        "设置中心改为分组侧栏、页面说明与卡片化内容，明确立即生效、新会话生效和重启 Harness 生效。",
                        "新增电脑控制权限与 MCP 注册真值页；模型配置重写后会自动恢复电脑控制 MCP 段。",
                        "模型列表首次加载和插件 version=null 解析问题一并修复；电脑控制逐页回归通过，测试 2367/2367。"
                    ],
                    why: "原设置页层级与生效范围不清楚；ZCode 的分域导航、状态可见性和解释性更适合持续扩展 Agent 能力。",
                    next: "只在具备完整后端真值源后再接入浏览器控制、技能和 MCP 服务器设置，避免空壳开关。"
                ),

                EvolutionEntry(
                    version: "v0.5.42",
                    date: "2026-08-30",
                    commit: "26bb60b",
                    tag: "v0.5.42",
                    summary: "自定义模型增删改查与端到端选择",
                    changes: [
                        "设置「模型」页支持新增、查看、编辑、删除任意 OpenAI Responses 兼容模型及其独立 API Key。",
                        "自定义模型贯通 composer、thread/start、config.toml、模型目录及全部模型展示位置；删除当前项时回落 MiniMax M3。",
                        "输入校验、TOML/JSON 安全转义、0600 权限与空 Key 处理补齐；全量离线测试 2366/2366。"
                    ],
                    why: "内置列表无法覆盖用户自己的兼容端点；半成品又只接通了部分调用链，导致运行模型与界面展示可能分裂。",
                    next: "用真实自定义 Responses 端点创建新会话并核对上游返回；评估迁移凭据到 macOS Keychain。"
                ),

                EvolutionEntry(
                    version: "v0.5.41",
                    date: "2026-08-30",
                    commit: "c8104fb",
                    tag: "v0.5.41",
                    summary: "模型弹窗极简化：只保留模型列表，点开即选",
                    changes: [
                        "用户两次反馈模型弹窗太复杂。目视确认后扁平化：弹窗只保留 4 个模型项（品牌 + 模型名 + 勾选当前）。",
                        "移除端点、上下文、思考深度、新建会话、复制运行信息、打开运行设置等行——各有归属（环境面板/设置页/圆环弹窗/⌘N）。",
                        "数据与切换逻辑不变：选择即持久化、对新建会话生效。"
                    ],
                    why: "用户要的是点开芯片看到 4 个模型点一下的最短路径，其余信息全是噪音。",
                    next: "真机用几天，若需要再把思考深度快捷入口以轻量形式回归。"
                ),

                EvolutionEntry(
                    version: "v0.5.40",
                    date: "2026-08-30",
                    commit: "206cb9b",
                    tag: "v0.5.40",
                    summary: "手机 H5 端模型名统一为 displayName：底栏与模型面板不再显示技术 slug",
                    changes: [
                        "v0.5.39 只改了 Mac 端展示层，H5 状态快照仍传 API slug，手机端继续暴露 deepseek-v4-flash。",
                        "PhoneRemoteServer 快照 model 改用 modelDisplayName；H5 JS 兜底文案同步改 displayName 口径。",
                        "H5 页面测试断言更新为 displayName 兜底；版本同步点对齐 0.5.40。"
                    ],
                    why: "同一模型 Mac 端显示「DeepSeek V4 Flash」、手机端显示 slug，口径分裂；H5 复用 v0.5.39 展示层规则。",
                    next: "真机扫码回归手机端模型名；评估普通会话发送【自进化指令】开头消息的确认提示。"
                ),

                EvolutionEntry(
                    version: "v0.5.39",
                    date: "2026-08-30",
                    commit: "5080e78",
                    tag: "v0.5.39",
                    summary: "模型选择菜单改显「品牌 + 模型名」，不再暴露技术 slug",
                    changes: [
                        "用户反馈模型菜单里 deepseek-v4-flash 这类技术 slug 太复杂，只想要品牌 + 模型名。",
                        "TapgoModel 新增 displayName：MiniMax M3 / GLM 5.3 Flash / DeepSeek V4 Flash / DeepSeek V4 Pro；API slug 不动，仅展示层切换。",
                        "切换菜单、composer 芯片、环境面板、设置页、诊断信息统一改用 displayName；测试 +5。"
                    ],
                    why: "面向用户的 UI 不应出现技术 slug；品牌 + 模型名一眼可辨。",
                    next: "手机 H5 端模型名仍显示 slug，待后续统一。"
                ),

                EvolutionEntry(
                    version: "v0.5.38",
                    date: "2026-08-30",
                    commit: "902ce8c",
                    tag: "v0.5.38",
                    summary: "自进化会话 composer 专属化：占位文案与项目条不再误导为当前项目",
                    changes: [
                        "用户实测踩坑: 点「自进化」进入专属会话后, composer 占位仍是「给 OctTapgo 发条任务…」、项目条仍显示 OctTapgo——用户以为没切进去, 把【自进化指令】粘贴进了 OctTapgo 下的普通会话, AI 在错误目录 (~/OctTapgo) 里跑了一轮 252.6k tokens 的自进化。",
                        "修复 1 — 占位文案: activeThread 为自进化会话时显示「向自进化下达本轮指令…」, 不再跟随 activeProject。",
                        "修复 2 — 项目条: 自进化会话显示专属胶囊「✨ 自进化 · <仓库名>」(固定指向项目根, 点击打开目录), 不跟随 activeProject 切换。",
                        "保留 v0.5.33 的行为: 进入自进化会话不清空用户当前项目, 仅在 composer 层做上下文显式化。"
                    ],
                    why: "会话已切换但输入区上下文没切换, 视觉状态与实际路由不一致, 是把指令发错会话的直接诱因。",
                    next: "评估在普通会话发送以【自进化指令】开头的消息时给出确认提示。"
                ),

                EvolutionEntry(
                    version: "v0.5.37",
                    date: "2026-08-30",
                    commit: "ceb6e5b",
                    tag: "v0.5.37",
                    summary: "圆形额度表改显「剩余量」：侧栏 / 弹窗 / 圆环三处口径完全统一",
                    changes: [
                        "用户圈出圆形额度表：显示已用 26%（周额度已用），与余量 74% 口径相反。",
                        "contextMeterChip 翻转：有额度数据时显示最差窗口剩余量（MiniMax 当前 74）；无额度数据退回上下文占用百分比。",
                        "无障碍标签同步：有额度数据时报「套餐余量 X%」。三处（侧栏 / 弹窗 / 圆环）全部为剩余口径。"
                    ],
                    why: "同一个数字三种口径让用户无法直接对照。",
                    next: "观察圆环填充方向语义（环越满 = 剩余越多）；有反馈再评估倒计时样式。"
                ),

                EvolutionEntry(
                    version: "v0.5.36",
                    date: "2026-08-30",
                    commit: "65c6444",
                    tag: "v0.5.36",
                    summary: "额度口径统一：弹窗余量卡片改显「剩余量」",
                    changes: [
                        "用户反馈口径不一：侧栏显示余量（99%/74%），额度弹窗却显示已用（19%/33%）。统一为剩余量。",
                        "ModelUsagePopover.quotaCells() 展示层翻转：usedPercent → max(0, 100 - usedPercent)，与侧栏公式一致；卡片标签加「余量」后缀。",
                        "数据层不动：三个额度客户端仍产出「已用」语义的 usedPercent，只在展示层翻转。"
                    ],
                    why: "同一个「剩余额度」标题下混用两种口径会让用户误读（19% 被看成只剩 19%）。",
                    next: "真机确认弹窗与侧栏数字一致。"
                ),

                EvolutionEntry(
                    version: "v0.5.35",
                    date: "2026-08-30",
                    commit: "17d8923",
                    tag: "v0.5.35",
                    summary: "接入 DeepSeek V4 系列（v4-flash / v4-pro，原生 Responses API）",
                    changes: [
                        "官方文档确认 DeepSeek API 原生支持 OpenAI Responses 协议；本机实测 key 打 https://api.deepseek.com/responses 返回标准 Responses 对象。",
                        "TapgoModel 新增 deepseek-v4-flash / deepseek-v4-pro（官方 slug，1,048,576 上下文）；config.toml 新增 [model_providers.deepseek]，鉴权独立 auth-deepseek.json（0600）。",
                        "额度/余额三路接线补全：DeepSeek 按量计费走 GET /user/balance，侧栏显示「DeepSeek·余额 ¥17.95 CNY」，弹窗来源标签 DeepSeek user/balance。",
                        "切换子菜单自动列出全部 4 个模型，切换对新建会话生效。",
                        "测试 +20 全绿（2375 passed / 8 既有 SSH 环境失败）。"
                    ],
                    why: "用户要求在模型选择里加入 DeepSeek 最新系列；V4 系列原生 Responses API 与 harness 0.149+ 零桥接兼容。",
                    next: "deepseek-v4-flash-vision-exp（图片输入）暂未接入，等需要再评估。"
                ),

                EvolutionEntry(
                    version: "v0.5.34",
                    date: "2026-08-30",
                    commit: "a0af5f8",
                    tag: "v0.5.34",
                    summary: "GLM 额度可查：接入 BigModel 官方 monitor/usage/quota/limit",
                    changes: [
                        "查证 GLM 套餐余量可以查询：智谱官方用量查询插件揭示端点 GET https://open.bigmodel.cn/api/monitor/usage/quota/limit，Authorization 直放套餐 key（裸 token）。",
                        "新增 GLMQuotaClient（与 MiniMaxQuotaClient 同构）：percentage→usedPercent，unit 3×5→5小时档 / unit 6×1→周档，nextResetTime 毫秒→resetsAt，level→planLabel（如 Lite）。",
                        "refreshRateLimits 按所选模型双通道取数（MiniMax coding_plan/remains / BigModel quota/limit，key 分别来自 auth.json 与 auth-glm.json）。",
                        "额度弹窗撤掉「暂不支持查询」占位，GLM 渲染真实余量卡片；侧栏 GLM 显示「GLM·Lite·81%/33%」。",
                        "测试 +18 全绿（2355 passed / 8 既有 SSH 环境失败）。"
                    ],
                    why: "用户质疑 GLM 额度显示为暂不支持查询；实测 BigModel 有官方接口，补齐与 MiniMax 对等的额度体验。",
                    next: "真机观察 GLM 数值；BigModel 若调整字段结构需同步解析。"
                ),

                EvolutionEntry(
                    version: "v0.5.33",
                    date: "2026-08-30",
                    commit: "5ed7ead",
                    tag: "v0.5.33",
                    summary: "自进化日志模块重构：分段导航 + 紧凑折叠条目 + 当前版本数据源修复",
                    changes: [
                        "用户反馈页面很乱：hero 卡显示 8/28 的陈旧 evolution_state.json（v0.5.3）却标着「本次进化」，v0.5.32 条目 commit 是没回填的 PLACEHOLDER，理念卡与全部明细平铺导致信息密度过低。",
                        "数据源修复：当前版本条只信源码内置 makeHistory() 最新条目（随发版更新）；evolution_state.json 不再作为版本数据源（它是 evolve.sh 快照，曾滞后 4 天）。",
                        "布局重构：hero 大卡压成单行版本条（版本·日期·SHA·摘要 + 本次进化胶囊）；「历史版本 / 使用指南」改为分段切换，不再全部堆叠。",
                        "条目紧凑化：收起态 = 版本 + SHA + 单行摘要；点击展开完整改动明细与 Why/Next，默认只展开最新一条；理念说明压缩为一行 caption。",
                        "数据回填：v0.5.32 commit 55b1f72、v0.5.19 commit c486d44（源码与 EVOLUTION.md 同步，PLACEHOLDER 清零）。"
                    ],
                    why: "自进化日志是 AI 的对外广播页，陈旧数据 + 未回填字段 + 低密度排版让用户无法快速回答「现在到哪了、每次改了什么」；重构后当前版本一眼可见，历史按下钻展开。",
                    next: "评估条目按版本号搜索/过滤；evolve.sh 落盘 evolution_state.json 的步骤若已废弃应删除该文件避免误导。"
                ),

                EvolutionEntry(
                    version: "v0.5.32",
                    date: "2026-08-30",
                    commit: "55b1f72",
                    tag: "v0.5.32",
                    summary: "侧栏额度行按用户反馈改版：套餐名 Ultra + 纯数字余量",
                    changes: [
                        "用户反馈三点：套餐名弄错了（实际订阅是 Ultra，不是 Token Plan/Coding Plan）；『周余量』等文字不要显示，只显示数值；格式改为 5小时余量%/周余量%。",
                        "modelQuotaSummary 改版：MiniMax·Ultra·21%/76%——供应商/套餐随选中模型（GLM 选中时只显示 GLM，不显示 MiniMax 配额）；套餐名走 TapgoConfig.planDisplayName = \"Ultra\"（MiniMax 接口不返回套餐名，以实际订阅为准，换套餐改一处常量）。",
                        "5 小时窗口（300 分钟）与周窗口（10080 分钟）各自取 100 - usedPercent，斜杠分隔无文字。"
                    ],
                    why: "用户明确给出目标格式与真实套餐名；显示应忠实于订阅事实而不是端点语义猜测。",
                    next: "无。"
                ),

                EvolutionEntry(
                    version: "v0.5.31",
                    date: "2026-08-30",
                    commit: "f81cf47",
                    tag: "v0.5.31",
                    summary: "模型切换：composer 弹窗可选 GLM-5.3-Flash（BigModel Coding Plan）",
                    changes: [
                        "功能代码随 v0.5.30 (60294f6) 提前入库（并行会话合并提交），本版补齐版本对齐、文档、侧栏适配与真机回归。",
                        "TapgoCore 新增 TapgoModel 目录：MiniMax-M3 与 GLM-5.3-Flash 各自绑定 provider 与端点；wire 一律 responses（本机 harness codex 0.149.1 已移除 chat wire）。",
                        "GLM 走智谱给 Codex 的 OpenAI Responses 专属端点 https://open.bigmodel.cn/api/v1，鉴权用独立 auth-glm.json（0600，缺失时报 401）；Coding Plan 套餐 key 实测可用且不按量计费。",
                        "config.toml 常驻双 provider；thread/start 按选中模型下发 model/modelProvider，切换对新建会话生效。",
                        "composer 模型弹窗「模型」行升级为切换子菜单（当前模型勾选）；端点/诊断跟随所选模型。",
                        "额度查询按模型门控：选 GLM 清空 MiniMax 快照并注明暂不支持查询；侧栏灰色行供应商跟随所选模型。",
                        "测试 +12：TapgoModel catalog & provider mapping（2335 passed / 8 既有 SSH 环境失败）。"
                    ],
                    why: "用户要求模型弹窗能选 GLM-5.3-Flash（套餐内不额外计费），并反馈弹窗冗杂、找不到切换入口；把模型行变成真正的切换器。",
                    next: "手机 H5 模型面板列出全部可选模型并支持切换；远程项目远端 config 仍是 MiniMax 单 provider，选 GLM 需同步 auth-glm.json 与 glm 段。"
                ),

                EvolutionEntry(
                    version: "v0.5.30",
                    date: "2026-08-30",
                    commit: "60294f6",
                    tag: "v0.5.30",
                    summary: "侧栏用户信息灰色行改为「供应商·套餐名·周余量」",
                    changes: [
                        "用户要求：App 左下角用户信息的灰色名字行（原先重复显示昵称）改为显示当前模型供应商/套餐名/周余量百分比。",
                        "SidebarView.userBar 灰色行改为 modelQuotaSummary：MiniMax·Coding Plan·周余量 74%——供应商取 TapgoConfig，套餐名用 rateLimits?.planLabel（MiniMax coding_plan 端点不返回套餐名字段，回退 Coding Plan 端点语义；初版误用『Token Plan』被用户指出后更正），周余量 = 100 - secondary(10080 分钟窗口).usedPercent，与 MiniMax 接口 current_weekly_remaining_percent 实测一致。",
                        "userBar 挂 .task：进侧栏立即 refreshRateLimits()，之后每 5 分钟刷新。",
                        "目视回归：窗口级截图确认左下角渲染 MiniMax·Coding Plan·周余量 74%（接口真实数据 74，无截断）。"
                    ],
                    why: "用户要在常驻位置一眼看到当前供应商/套餐/周配额健康度；灰色行原本重复显示昵称没有信息量。",
                    next: "若 MiniMax 接口未来返回正式套餐名字段，用真实值替换 Coding Plan 回退；周余量颜色随压力等级变化。"
                ),

                EvolutionEntry(
                    version: "v0.5.29",
                    date: "2026-08-30",
                    commit: "4ebecd9",
                    tag: "v0.5.29",
                    summary: "自进化升级为独立入口：独立对话、独立开发专属会话",
                    changes: [
                        "侧边栏「自进化」从只读日志弹窗升级为独立入口：点击直接进入自进化专属会话（新建或选中最新一条），菜单命令注册 ⌘⌥E 快捷键。",
                        "独立对话：Thread 新增 mode 字段（\"evolution\" 标记，向后兼容），自进化会话在侧边栏独立分组置顶（sparkles 图标），不与普通项目会话混排。",
                        "独立开发：会话 cwd 固定为本项目根（探测 ~/TapgoAICoding 需同时含 Package.swift 与 AGENTS.md），找不到时弹窗提示而不建空壳会话。",
                        "新增 EvolutionPanel 引导横幅：「开始自进化」一键发出内置指令（核对仓库 → 选定改进点 → 实现 → 全量回归 → 版本对齐，运行中禁用），「自进化日志」按钮保留只读历史入口。",
                        "进入自进化会话不再清空 composer 的当前项目；窗口标题/副标题特判显示真实仓库名与路径。",
                        "测试新增 Thread: evolution mode + workspace 段 16 断言；全量 2283 passed / 0 failed（跳过远程集成段）。"
                    ],
                    why: "自进化此前只是静态日志页，用户想让它真正“自己开发自己”——必须是一个独立入口下的独立会话，有专属指令与固定工作目录，与日常对话互不干扰。",
                    next: "自进化回合结束后自动生成 EVOLUTION 草稿条目；评估多轮自进化会话列表与每轮独立 harness 上下文。"
                ),

                EvolutionEntry(
                    version: "v0.5.28",
                    date: "2026-08-30",
                    commit: "ca7da89",
                    tag: "v0.5.28",
                    summary: "紧急修复 config.toml 漂移重写抹掉真实鉴权导致 401",
                    changes: [
                        "用户真机反馈：会话每轮 Reconnecting 5/5 后报 unexpected status 401 Unauthorized: login fail (1004)，url 指向 api.minimaxi.com/v1/responses。",
                        "根因是 v0.5.27『修复 7』的回旋镖：ensureReady 按模板 diff 重写 config.toml 时，模板里的 experimental_bearer_token = \"__FROM_AUTH_JSON__\" 是 Tapgo 自造占位符，全仓没有任何运行时替换机制——磁盘旧 config 的鉴权段是历史真实有效的 key，重写把它覆盖回占位符，请求不带 Authorization。",
                        "修复：新增 TapgoConfig.renderedConfigWithKey(region:authKey:)，两条 config 写出路径（init 的 writeAll 与 ensureReady 的漂移重写）都把占位符替换为 auth.json 真实 key；模板注释同步更正。",
                        "自愈验证：重启 App 后 ensureReady 检测漂移自动重写，bearer 与 auth.json 完全一致（125 字符 sk-cp-12…，占位符残留 0）。",
                        "端到端验证：经公网 H5 api/send 发送鉴权验证消息 → 回合 completed，模型回复『已恢复正常』。"
                    ],
                    why: "v0.5.27 的 config 漂移重写是按『占位符有效』的错误假设写的，上线即打断了所有会话的模型鉴权；配置文件属于关键数据，重写必须保留可用的凭据语义。",
                    next: "观察三台机器配置一致性；评估给 config.toml 重写加 .bak 备份，避免同类覆盖不可回滚。"
                ),

                EvolutionEntry(
                    version: "v0.5.27",
                    date: "2026-08-29",
                    commit: "cb8e2db",
                    tag: "v0.5.27",
                    summary: "额度弹窗二轮修复：诊断 + 双端点 + 6 行去重 + 模型分桶 + 毫秒时间戳",
                    changes: [
                        "v0.5.25 上线后用户截屏反馈弹窗仍报错且 6 行百分比 1612% > context% 815%。直接 curl 实测 MiniMax 接口发现根因 + 4 处隐藏 bug。",
                        "根因 1 — model_name 实际是 quota 类别而非模型名：接口返回 general / video 这样的分桶名，不会直接返回 MiniMax-M3。pickEntry 增加『文本/对话模型 → general 桶』『视频模型 → video 桶』的语义映射。",
                        "根因 2 — 接口直接给 _remaining_percent（剩余百分比），旧版在 total=0 时丢弃 cell。新版三层 fallback：_remaining_percent 优先 → total - remaining 反算 → 仅 total 时按 0% 展示；即使 total=0 也能展示订阅健康度。",
                        "修复 3 — 6 行百分比重复计 cached：消息 = max(0, input - cached)，行间近似不重。",
                        "修复 4 — MiniMax 时间戳是毫秒不是秒：13 位 end_time=1788019200000 表示 2026-08-29。dateValue 按量级自动检测 + 兜底乘 1000。",
                        "修复 5 — 诊断信息可读：QuotaError 带 endpoint；noMatchingModel 带 returned 列表；新增 emptyResponse 区分两种失败。",
                        "修复 6 — 双端点 fallback：coding_plan/remains → token_plan/remains，仅未匹配/空响应触发。",
                        "附带清理 — v0.5.25 引入的 Swift 6.4 编译错误：case [\"img\", let turnId, let idxStr]: 改写为 case let arr where ... 手动取元素；TranscriptTurn 漏传 userImageCount。",
                        "测试新增 MiniMaxQuota: lenient match + dual-endpoint fallback 19 断言、timestamp parsing 2 断言、SnapshotBuilder 16→19 断言；全量 7 段 94 断言全绿。",
                        "修复 7 — config.toml 漂移导致 24M tokens 不压缩：用户机器上 config.toml 缺 model_auto_compact_token_limit = 800000（v0.3.0 模板新增，但 ensureReady 从不重生成 config.toml）；后果是 harness 不知道该在 800k 自动压缩，会话累积到 24M tokens（弹窗进度条 2524%）。ensureReady 现在按模板 diff 漂移即用 renderConfig 重写（auth.json 不动）。",
                        "修复 8 — 弹窗百分比阈值封顶：contextPercent >= 100% 时显示 ≥100% 而不是 2524%；真实计数 24.0M/950k 仍显示在前，用户一眼看出超出多少倍。",
                        "收编并行会话 WIP（用户反馈『H5 看不到上传的图片』）：新增 GET /img/<turnId>/<index>（按 turnId 查 userImagePaths 出图）与 GET /pending/<index>（待发附件缩略图）两条带 token 的图片路由；TranscriptTurn 增 userImageCount；H5 用户气泡内渲染图片、composer 附件行改缩略图 + 计数；图片响应带私有缓存头防 2s 轮询闪烁。"
                    ],
                    why: "v0.5.25 只换了数据源没换诊断 UX，且未实测接口；这一版直接 curl 发现 4 处协议级 bug（分桶命名 / 剩余百分比 / 毫秒时间戳 / 重复计缓存），加上 config.toml 漂移导致 24M 不压缩（弹窗进度条 2524%），一次性全部修复。",
                    next: "contextWindow 仍由 harness 报 950k（vs TapgoConfig 配置 1M）—— 怀疑是 harness 对 MiniMax-M3 实际请求窗口有其它来源；等用户真机重启后看到 950k 来源后再修。"
                ),

                EvolutionEntry(
                    version: "v0.5.26",
                    date: "2026-08-29",
                    commit: "9287b78",
                    tag: "v0.5.26",
                    summary: "移除手机 composer 下方三个快捷指令 chips",
                    changes: [
                        "用户反馈 v0.5.21 仿 ZCode 截图时自作主张加的三个快捷 chips (🧪 跑测试 / 📝 总结改动 / ▶ 继续任务) 多此一举：它们只是把固定文案填进输入框，不是用户要的功能。",
                        "删除 #chips HTML/CSS 与对应 JS 接线，composer 下方恢复干净；无其它行为变化。"
                    ],
                    why: "仿造竞品形态时不该连可有可无的装饰一起照搬；用户明确指出后立即移除。",
                    next: "无。"
                ),

                EvolutionEntry(
                    version: "v0.5.25",
                    date: "2026-08-29",
                    commit: "275c78f",
                    tag: "v0.5.25",
                    summary: "composer『查看额度』接 MiniMax 官方接口 + 手机附件上传与模型选择面板",
                    changes: [
                        "用户反馈『查看额度』严重错误：之前走 Codex app-server 的 account/rateLimits/read，但本 App 对话模型是 MiniMax-M3，那条 JSON-RPC 永远拿不到真实订阅数据。",
                        "新增 TapgoCore/MiniMaxQuotaClient：直接读 auth.json 里的 OPENAI_API_KEY，调 MiniMax 官方 GET /v1/api/openplatform/coding_plan/remains，Authorization: Bearer <Token Plan Key>，端点随 TapgoConfig.Region（默认 www.minimaxi.com）。",
                        "新增 TapgoCore/MiniMaxQuotaSnapshotBuilder：处理 MiniMax 字段语义陷阱——current_interval_usage_count / current_weekly_usage_count 字面是 usage，实际是『剩余』；这里集中做 used = total - remaining 反转；周配额无 reset 时间则不写 resetsAt；Token Plan 没有 Credits 概念，credits cell 始终隐藏。",
                        "SessionStore.refreshRateLimits() 改为异步实例化 MiniMaxQuotaClient(authPath:, modelName:) 直接拉取，不再依赖 Codex harness（移除 firstLiveRunner() 选 harness 的逻辑）。",
                        "弹窗标签 codex account/rateLimits → MiniMax coding_plan/remains，调试时一眼看出数据来源；错误信息直接显示 MiniMax 接口的 HTTP / 业务码。",
                        "测试：新增 MiniMaxQuota: SnapshotBuilder 16 断言（基本反转/100%/0%/服务端 glitch 越界 → 100% 钳位/total=0 隐藏/planLabel 空白隐藏/数值类型 NSNumber+Double 兼容）+ MiniMaxQuota: MiniMaxQuotaClient 10 断言（HTTP 200 成功 / 500 透传 / 业务 1008 insufficient_balance 透传 / model 不匹配 / auth.json 缺失 / 单条 wildcard fallback / Bearer header 取自 auth.json）；既有 RateLimits: JSON parsing + display helpers (29 断言) 与 ExecEvent: account/rateLimits/updated notification (6 断言) 全绿。",
                        "收编并行会话 WIP（用户反馈『+ 怎么是新对话？模型也不能选择，按钮也不能正常使用』）：composer『+』改为图片附件上传——选图 → base64 POST api/attach → Mac 魔数校验后 store.addImages 加入待发附件，随下一条消息发送；composer 显示附件计数与上传进度；PhoneRemote.maxBodyBytes 65KB → 20MB；快照增 attachedCount。",
                        "模型名『MiniMax-M3 ▾』点击弹出模型选择面板（列表来自 Mac 端 codex 配置，当前模型高亮）；大脑图标可点跳电脑控制 Tab；测试 +13 断言（attach 路由 5 / attachedCount 1 / 页面 7），公网链路实测上传 1x1 PNG → attachedCount=1。"
                    ],
                    why: "App 用的是 MiniMax-M3 不是 Codex 模型，Codex 那条 JSON-RPC 拿到的是 Codex 自身订阅配额，跟用户实际订阅完全无关——必须切到 MiniMax 官方 Token Plan 接口才能拿到真实数据。",
                    next: "Token Plan 接口在海外端点未联调（.overseas 分支已留好 baseURL）；后续若用户切到海外 region，用同一个 client 即可生效。"
                ),

                EvolutionEntry(
                    version: "v0.5.24",
                    date: "2026-08-29",
                    commit: "5af6315",
                    tag: "v0.5.24",
                    summary: "H5 顶部改项目切换器，移除软件标题",
                    changes: [
                        "置顶 header 由『● Tapgo · 机器名』改为『● 📁 当前项目名 ▾』——项目切换器占据标题位，点击进『项目与会话』列表页；原 composer 上方的项目条同步移除，不再重复。",
                        "页面 h1 标题删除（回归断言：页面无 <h1>）；浏览器标签页标题仍为 document.title = \"Tapgo · 机器名\"（多机辨识在标签页层）。",
                        "列表页统计行加主机名（『Chenlaiyi · 2 个项目 · 42 个会话』），多机场景下辨识当前设备。",
                        "真实浏览器截图确认顶部即项目切换器。"
                    ],
                    why: "手机小屏上软件名没有信息量，项目才是当前上下文；顶部常驻切换器让『换项目』变成一步操作。",
                    next: "项目切换器支持直接下拉切换（免进列表页）；会话页补当前会话标题行。"
                ),

                EvolutionEntry(
                    version: "v0.5.23",
                    date: "2026-08-29",
                    commit: "60100a1",
                    tag: "v0.5.23",
                    summary: "手机 H5 助手输出 Markdown 富文本渲染（标题/列表/代码块/行内代码芯片）",
                    changes: [
                        "用户反馈『输出内容也太乱』：助手回复的 Markdown 源码原样贴在 H5 上。新增 PhoneRemote.markdownHTML：复用 Mac 端同款 MarkdownLite 解析器渲染成安全 HTML —— 标题、有序/无序列表、任务清单 (☑/☐)、代码块 (深底+语言标签+横向滚动)、行内代码 (品牌色芯片)、引用块、表格、分隔线、链接。",
                        "安全设计：全部原文先转义、标签只由渲染器产出 (innerHTML 无注入面)；escapeText (内容位, 不转引号) 与 escapeHTML (属性位, 全量) 分离；javascript: 等危险 scheme 链接降级纯文本；图片降级为链接 (H5 不外链资源)。",
                        "TranscriptTurn 增 assistantHTML (原文 assistant 保留)；H5 对话区改 innerHTML 渲染；文本段软换行转 <br>。",
                        "新增『PhoneRemote: Markdown 输出渲染』测试段 21 断言 (XSS/行内/标题/列表/任务/代码块/表格/引用/快照一致性)；全量 2240 passed / 8 failed。",
                        "目视回归：真实浏览器手机视口截图 —— 加粗/行内代码芯片/列表全部正确排版，不再出现源码字符。"
                    ],
                    why: "助手输出天然是 Markdown，按纯文本渲染等于源码墙；复用同款解析器在 Mac 端服务端渲染成安全 HTML，手机端零依赖、离线可用。",
                    next: "长回复折叠/展开；代码块一键复制。"
                ),

                EvolutionEntry(
                    version: "v0.5.22",
                    date: "2026-08-29",
                    commit: "854b4e5",
                    tag: "v0.5.22",
                    summary: "composer 底栏对齐 ZCode：模型名/盾牌/大脑/白色圆形↑ + 项目条独立",
                    changes: [
                        "按用户 ZCode composer 截图重构底栏：左侧 + (线性 SVG, 当前项目新建会话) 与橙色盾牌 (电脑控制权限警示态, 点击跳电脑控制 Tab)；右侧 busy 转圈、模型名选择行『MiniMax-M3 ▾』、大脑图标 + 状态点 (权限齐备变绿)、白色圆形 ↑ 发送键 (深色箭头, 运行中置灰)。",
                        "StateSnapshot 增 model 字段 (App 传 store.modelName)，快照段 +1 断言 (model 透传)。",
                        "项目选择挪回 composer 上方独立小条 (📁 项目名 ▾)，与 ZCode 第一屏结构一致；composer 卡内不再有分隔的项目行。",
                        "图标全部换内联 SVG 线性风格 (+ / 盾牌 / 大脑 / ↑)，与截图线性图标一致，不再用 emoji。",
                        "H5 段断言 29 → 35 (barIcon/modelName/兜底文案/busySpin/brainDot/shieldBtn)；目视回归：真实浏览器手机视口截图对照用户截图通过。"
                    ],
                    why: "上一版只对了功能与大形，底栏元素构成 (模型名/状态图标/白色发送键) 与 ZCode 差距仍明显；逐元素复刻才能达到用户预期。",
                    next: "模型名 ▾ 接真实模型切换 (config.toml 多模型)；盾牌/大脑点击后的权限引导细化。"
                ),

                EvolutionEntry(
                    version: "v0.5.21",
                    date: "2026-08-29",
                    commit: "9c02040",
                    tag: "v0.5.21",
                    summary: "手机 H5 全面仿 ZCode 输入/输出形态：composer 卡片 + 用户气泡 + 工作区列表徽标",
                    changes: [
                        "输入区 (composer 卡片)：卡内首行项目选择行 (📁 项目名 + ▾, 点击进『项目与会话』列表页)、中部大输入区『向 Tapgo 提问…』自动增高至 140px、底行 + 新建会话 + 圆形 ↑ 发送键 (运行中置灰)；卡片下方快捷 chips (🧪 跑测试 / 📝 总结改动 / ▶ 继续任务) 点击填入不自动发送。",
                        "输出区 (对话形态)：用户消息右对齐品牌色圆角气泡 (max-width 86%)、助手通栏正文、运行中脉冲『正在运行…』徽标；空会话首屏时段问候 (早上好呀/中午好呀/下午好呀/晚上好呀)。",
                        "列表页 (仿 ZCode 工作区与任务)：信息横幅；项目卡『本地/远程』标签 (ProjectSeed/ProjectInfo 增 isLocal + lastActivityAt, App 传 kind)、『更新于 刚刚/N 小时/N 天』；会话行徽标『⚡ 运行中』橙实底 /『✓ 已完成』绿浅底, 当前会话蓝点 + 品牌浅底。",
                        "H5 段回归断言 19 → 29：composer/占位/发送键/问候/气泡/脉冲/更新于/本地/双徽标。",
                        "目视回归：真实浏览器手机视口截图两张 (会话页 + 列表页), 与 ZCode 截图逐项对照通过。"
                    ],
                    why: "用户要求输入输出全面仿造 ZCode 截图；v0.5.20 只做了功能可达 (能切换), 本版补齐形态一致性, 让手机端观感与 ZCode 对齐。",
                    next: "按 ZCode 任务页补会话标题头部；评估快捷 chips 可配置；电脑控制 Tab 与新 composer 的视觉统一。"
                ),

                EvolutionEntry(
                    version: "v0.5.20",
                    date: "2026-08-29",
                    commit: "d65f57e",
                    tag: "v0.5.20",
                    summary: "模型可调用的电脑控制 (Computer Use)：内置 MCP server 让 AI 自动化桌面工作流",
                    changes: [
                        "新增 TapgoComputerUseMCP 可执行目标：电脑控制 MCP stdio server（MCP 2025-06-18 协议），向模型暴露 8 个工具：screenshot / get_screen_size / left_click / double_click / type_text / press_key（14 普通键 + 6 媒体键 + command/control/option/shift 组合）/ scroll / open_application；坐标一律归一化 0...1 与分辨率无关；权限缺失时返回带系统设置指引的 isError 文本。",
                        "新增 TapgoComputerUse 库：截屏（CGDisplayCreateImage → ≤1280px JPEG）/ 鼠标单击双击（CGEvent clickState 递增）/ 滚轮（±20 行限幅）/ 逐字符 Unicode 键盘输入 / 媒体键 systemDefined 事件 / 锁屏（Ctrl+Cmd+Q）/ 睡眠（pmset）/ open -a 启动应用，从 PhoneRemoteServer 抽出为 App 手机控制与 MCP server 共用的单一实现。",
                        "新增 TapgoCore/ComputerUseMCP 纯 Foundation 协议层：JSON-RPC 分发（initialize/tools/list/tools/call/ping，通知不回包）、工具注册表 inputSchema、参数解析助手（CFBooleanGetTypeID 严格区分 Bool 与数值）、config.toml [mcp_servers.tapgo_computer_use] 段幂等写入（新增/路径变更只换 command 行/缺 command 补插），协议分发 + TOML 写入共 76 项单测。",
                        "自动注册链路：build-app.sh 把 MCP 二进制嵌入 .app 的 Contents/MacOS/；App 启动幂等把随包路径写进隔离 Codex home 的 config.toml；codex 拉起后模型即可调用，无需任何手工配置。",
                        "真实轮验证：经手机 H5 /api/send 发起真实 MiniMax-M3 轮『用电脑控制工具截屏』——模型成功发起 MCP screenshot 调用并如实转述结果（本机未授予屏幕录制权限时返回权限指引），模型→工具→回包全链路打通。",
                        "收编并行会话 WIP：H5 项目列表（StateSnapshot 增 projects 块 + ProjectSeed/ProjectInfo、页面项目选择区）、PhoneRemoteController init 增 workspace 参数；补 WorkspaceStore.projects 只读视图使两端共用。"
                    ],
                    why: "用户要求 Computer Use 风格的能力——让 App 里的模型自己调用截屏/鼠标/键盘工具协助完成桌面自动化工作流，而不是只有手机端人工遥控。MCP 是 codex 的标准工具扩展面，注册进隔离 Codex home 即对所有会话生效；权限闸（屏幕录制/辅助功能 TCC）与错误指引内建在工具返回里。",
                    next: "TCC 授权后回归真实点击/打字链路；评估窗口枚举工具（list_windows）；H5 项目切换完善后单独发版。"
                ),

                EvolutionEntry(
                    version: "v0.5.19",
                    date: "2026-08-29",
                    commit: "c486d44",
                    tag: "v0.5.19",
                    summary: "修复公网模式 H5 永远停在『正在连接 Mac』：fetch 前缀自适应 + 首屏失败可读诊断",
                    changes: [
                        "用户真机反馈：公网域名模式扫码后页面停在『正在连接 Mac…』。定位：页面 200 可打开，但 JS 用绝对路径 /r/<token>/api/state 拉数据，nginx 只转发 /remote/<machine>/ 前缀，/r/* 落到 Laravel 404，首屏永远渲染不出（curl 三路径 200/404/200 坐实）。",
                        "pageHTML 全部 5 处 fetch（state/select/send/ctrl/ctrl-screen）改为 BASE + \"r/\" + TOKEN 前缀自适应：BASE = location.pathname 剥掉 /r/<token> 尾巴，直连为 /，公网中继为 /remote/<machine>/，两种模式同一份页面。",
                        "首屏连续 2 次失败时占位区给出可读诊断（403=二维码已轮换请重扫 / 404=请更新 Mac 端 App / 网络不通）；已加载成功后瞬断仍只熄状态点。",
                        "『PhoneRemote: H5 页面』测试段新增 4 条回归断言：含 BASE 自适应、禁止绝对路径 fetch。",
                        "真实浏览器（390×844 手机视口）打开公网链接端到端验证：标题/项目下拉 48 个会话/对话渲染/发送框全部就位，不再卡『正在连接 Mac』。"
                    ],
                    why: "公网中继把页面挂在 /remote/<machine>/ 子路径下，页面内绝对路径 fetch 在反代后必然断链；这是公网模式上线的最后一公里，必须真浏览器端到端验证而不只是 curl 接口。",
                    next: "手机端项目切换（对齐 ZCode 工作区/任务列表形态），见 v0.5.20。"
                ),

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

/// 历史条目行：收起 = 版本行 + 摘要（两行内）；点击展开完整改动明细、
/// Why 与 Next。最新一条有品牌色描边，展开态背景微亮。
private struct EvolutionEntryRow: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let entry: EvolutionEntry
    let isLatest: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                        .foregroundStyle(isLatest ? DSHTheme.brand : Color.secondary)
                        .frame(width: 10)
                    Text(entry.tag ?? entry.version)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(isLatest ? DSHTheme.brand : .primary)
                    if let commit = entry.commit {
                        Text(String(commit.prefix(7)))
                            .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.summary)
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? 3 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(entry.date)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.tag ?? entry.version)，\(entry.summary)\(isExpanded ? "，已展开" : "，点击展开")")

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.changes, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(line)
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !entry.why.isEmpty {
                        row(tag: "Why", color: DSHTheme.brand, text: entry.why)
                    }
                    if !entry.next.isEmpty {
                        row(tag: "Next", color: .secondary, text: entry.next)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isLatest ? DSHTheme.brand.opacity(0.5) : DSHTheme.border,
                        lineWidth: isLatest ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: isExpanded)
    }

    private func row(tag: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(tag)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color.opacity(0.12), in: Capsule())
                .foregroundStyle(color)
            Text(text)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
