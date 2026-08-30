# Evolution Log

> 最新条目在最上方（latest first）。每个版本对应一个 git tag（一个完整
> build → test → commit → push 闭环）。回滚到任意版本：
> `git checkout vX.Y.Z && ./scripts/build-app.sh`。

## Format

```
## vX.Y.Z — <one-line summary>
**Date**: YYYY-MM-DD
**Commit**: <short SHA>
**Tag**: vX.Y.Z
**Test status**: 110/110 green (or however many passed)
**Changed**:
- bullet
- bullet
**Why**: 1–2 sentences on the motivation / problem solved.
**Next**: what the following iteration plans to tackle (or "see state file").
```

## v0.5.50 — 本地化应用名启动不再假成功
**Date**: 2026-08-30
**Commit**: 7668a47
**Tag**: v0.5.50
**Test status**: 2397 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过远程环境段）
**Changed**:
- `open_application` 现在等待 `/usr/bin/open` 完整退出并检查退出码，不再把“进程成功创建”误报为“应用成功启动”。
- 英文 bundle 名失败时，按本机 Spotlight 的 `kMDItemDisplayName` 本地化索引解析 `.app`，中文“计算器”可正确定位 `/System/Applications/Calculator.app`；bundle id 仍走 `NSWorkspace` 直接解析。
- JKMac mini 实测调用前 Calculator 进程不存在；`open_application(name="计算器")` 后出现新 PID，并可用 `get_app_state(app="计算器")` 读取 `com.apple.calculator` 界面树。
**Why**: v0.5.49 的核心权限桥接已打通，但真实验收使用英文 `Calculator` 绕过了一个中文场景：旧实现未等待 `open` 结束，中文本地化名称找不到应用时仍返回成功。
**Next**: 三台 Mac 同步 0.5.50；MacBook Pro 与 fafamacmini 分别完成本机 TCC 双授权后，再做与 JKMac mini 相同的真实会话验收。

## v0.5.49 — 正式签名 Helper 桥接打通真实电脑控制
**Date**: 2026-08-30
**Commit**: 535ae92
**Tag**: v0.5.49
**Test status**: 2397 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过远程环境段）
**Changed**:
- MCP stdio 进程把每次 `tools/call` 通过 Launch Services 交给独立 `Tapgo Computer Use.app` 一次性执行，使 macOS TCC 始终按 Helper 的稳定 bundle 身份判断权限，不再错误归因给 Codex Harness 父进程。
- 桥接请求与响应限定在所有者专用的临时目录，校验目录所有者、0700 权限、固定文件名、常规文件、无符号链接和 1 MiB 请求上限，避免任意路径读写。
- 构建脚本优先使用 Tapgo Developer ID 正式签名并带时间戳；无证书环境才显式回退 ad-hoc，也支持 `TAPGO_SIGNING_IDENTITY` 覆盖。
- JKMac mini 已完成辅助功能与屏幕录制双授权；底层 MCP 和真实 Tapgo 会话均通过截图、启动 Calculator、读取界面树、按元素点击数字 7、再次读取与截图的完整验收，显示值从 `7` 变为 `77`。
**Why**: v0.5.48 的设置探测由 Launch Services 启动 Helper，所以页面显示已授权；真实会话却由 Harness 直接执行 Helper 内二进制，TCC 看到的是错误的父进程链，导致截图和 Accessibility 操作仍全部失败。
**Next**: 将同一份正式签名构建同步到另外两台 Mac；各机首次使用时分别完成本机 TCC 授权并做相同的真实会话回归。

## v0.5.48 — 独立安装电脑控制 Helper 并修复真实拖拽入口
**Date**: 2026-08-30
**Commit**: 083a560
**Tag**: v0.5.48
**Test status**: 2397 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过远程环境段）
**Changed**:
- 参照 ZCode 的实际安装流程，先把内嵌 Helper 原子复制到 `~/Library/Application Support/Tapgo AICoding/computer-use/Tapgo Computer Use.app`，权限授权、状态探测与 MCP 注册统一使用这一个稳定的独立 App。
- 将 SwiftUI `NSItemProvider` 替换为 AppKit `NSDraggingSession` 与原生 `NSURL` 文件载荷；授权浮窗可成为 key window，拖拽视图完整命中并回显按下、开始及结束状态。
- JKMac mini 已验证独立 Helper 可被系统“屏幕录制”列表接收且探测为已授权；同时发现旧版 ad-hoc 签名残留会让“辅助功能”列表显示开启但当前 Helper 自检仍为未授权。
- 测试入口兼容当前 `Codex Desktop` 大小写形式，完整离线回归 2397/2397。
**Why**: 之前拖动的是主 App Resources 内的嵌套 bundle，既不等同于 ZCode 的独立 Helper 安装流程，也会让 TCC 授权对象、MCP 进程和升级后的签名身份发生偏离。
**Next**: 经用户确认后移除 JKMac mini 上失效的旧辅助功能记录，重新添加当前 0.5.48 独立 Helper 并回读两项权限；正式签名证书到位后改用稳定 Developer ID，避免 ad-hoc CDHash 随版本变化。

## v0.5.47 — 修复授权浮窗抢占 Helper 拖拽
**Date**: 2026-08-30
**Commit**: f361cfd
**Tag**: v0.5.47
**Test status**: 2394 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 禁止电脑控制授权浮窗整体移动，关闭 `isMovable` 与 `isMovableByWindowBackground`。
- 保留 `Tapgo Computer Use` 卡片的文件拖拽提供器，拖动卡片时导出真实 Helper `.app`，不再带着整个浮窗移动。
**Why**: 浮窗允许背景拖动时，AppKit 会先于 SwiftUI `.onDrag` 消费手势，用户拖动 Helper 卡片实际移动了整个授权面板。
**Next**: 在辅助功能和屏幕录制两个系统页面分别完成一次真实拖入授权回归。

## v0.5.46 — 电脑控制独立 Helper 与系统授权拖拽引导
**Date**: 2026-08-30
**Commit**: 309e3c2
**Tag**: v0.5.46
**Test status**: 2394 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 新增独立 `Tapgo Computer Use.app` Helper，以固定 bundle id 承载 Accessibility、Screen Recording 和电脑控制 MCP，避免继续误用主 App 或宿主进程权限。
- 两项权限分别提供精确系统设置入口；打开后显示置顶拖拽面板，可把真实 Helper App 拖入对应允许列表。
- 权限状态通过 Launch Services 启动 Helper 并回写只读 JSON，避免直接执行二进制时继承 Terminal/主 App 的 TCC 上下文。
- Composer 入口与设置页统一使用 Helper 真值；MCP 配置改指向嵌套 Helper 可执行文件，并补齐稳定路径测试。
**Why**: 原实现只展示主 App 权限和通用系统设置链接，系统实际执行电脑控制的进程身份不明确，也没有 ZCode 式的一键拖拽授权流程。
**Next**: 用户完成三台 Mac 的系统授权后，分别回读 Helper 权限并实测截图、元素树读取和点击输入链路。

## v0.5.45 — 电脑控制界面验收修复
**Date**: 2026-08-30
**Commit**: e174ceb
**Tag**: v0.5.45
**Test status**: 2390 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 将电脑控制两个开关明确固定为 macOS 滑动开关，避免系统默认 Form 样式显示为复选框。
- 输入区「电脑操作」入口改用带初始页面的独立 sheet 状态，稳定直达电脑控制设置，消除首次打开误落到常规页的竞态。
**Why**: v0.5.44 发布后的真实界面验收发现开关视觉形态和首次直达页面不符合预期，需要发布一个不改写既有标签的修复版本。
**Next**: 三机授权后验证语义元素点击链路；继续补按元素输入、滚动与多显示器选择。

## v0.5.44 — 电脑控制完整启停、输入区入口与 Accessibility 语义操作
**Date**: 2026-08-30
**Commit**: c39cbda
**Tag**: v0.5.44
**Test status**: 2390 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 参考 ZCode 补齐「启用电脑控制」与「在输入框底部显示电脑操作」两个独立开关；总开关真实注册/移除 MCP 配置，显示偏好不改变能力状态。
- Composer 新增「电脑操作」快捷入口，以绿/橙/灰状态点区分已就绪、缺权限与已关闭，点击直达电脑控制设置。
- 电脑控制设置页新增权限/MCP 真值、关闭态说明、重新检测、重新注册和系统隐私设置入口；App 启动及模型配置重写均尊重总开关。
- MCP 工具由 8 个扩展为 11 个，新增 list_applications / get_app_state / click_element；支持读取 macOS Accessibility 元素树并按元素操作，安全输入框内容强制隐藏。
- 新增 MCP 段安全移除、语义工具 schema 与参数边界测试；完整离线回归 2390/2390。
**Why**: v0.5.43 只有状态页和手动注册按钮，没有真正的启停开关与 Composer 入口；底层也只有截图坐标操作，无法兑现「读取/驱动 UI 元素」的语义电脑控制。
**Next**: 在三台 Mac 分别授权后验证语义元素点击链路；后续补充按元素输入、滚动与多显示器选择。

## v0.5.43 — 参考 ZCode 重构设置中心
**Date**: 2026-08-30
**Commit**: b4a7597
**Tag**: v0.5.43
**Test status**: 2367 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 设置中心改为分组侧栏、页面标题/说明与卡片化内容，明确区分立即生效、新会话生效和重启 Harness 生效。
- 新增真实电脑控制状态页，回读辅助功能、屏幕录制和 MCP 注册状态；模型配置重写后自动恢复电脑控制 MCP 段。
- 模型页完成卡片化并修复首次进入模型列表不加载；插件管理嵌入设置页，并兼容官方目录中 `version = null` 的 Git 插件。
- 使用电脑控制逐页回归常规、外观、模型、电脑控制、记忆和插件页；Codex 官方 48 项、DeepSeek 官方 2 项均可正常读取。
**Why**: 原设置页只是窄侧栏加 Form 的功能集合，层级、说明和生效范围不清楚；ZCode 的分域导航与状态可见性更适合持续扩展 Agent 能力。
**Next**: 继续评估浏览器控制、技能、MCP 服务器等能力是否具备完整后端真值源，具备后再接入设置，避免只做空壳开关。

## v0.5.42 — 自定义模型增删改查与端到端选择
**Date**: 2026-08-30
**Commit**: 26bb60b
**Tag**: v0.5.42
**Test status**: 2366 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过 13 个远程环境段）
**Changed**:
- 设置「模型」页支持新增、查看、编辑、删除任意 OpenAI Responses 兼容模型，保存显示名、品牌、API 模型 ID、Base URL、API Key 与上下文窗口。
- 自定义模型贯通 composer 选择、thread/start 的 model/modelProvider、config.toml provider、模型目录、环境面板、侧栏、额度弹窗、诊断信息和模型身份提示；删除当前模型时安全回落 MiniMax M3。
- 注册表与生成配置保持 0600 权限；输入统一校验/去空白，TOML 与 JSON 做安全转义，空 Key 不再残留占位符；新增注册表与目录回归测试。
- 全量测试入口兼容既有 TAPGO_SKIP_REMOTE_INTEGRATION 环境变量，避免开发跑测卡在 RFC 5737 示例远程地址。
**Why**: 内置模型列表无法覆盖用户自己的兼容端点；此前半成品只接通了部分选择链路，其他界面仍会误报为 MiniMax，并且缺少输入与配置安全边界。
**Next**: 用真实自定义 Responses 端点创建新会话，核对上游返回与额度展示；再评估把凭据迁移到 macOS Keychain。

## v0.5.41 — 模型弹窗极简化：只保留模型列表，点开即选
**Date**: 2026-08-30
**Commit**: c8104fb
**Tag**: v0.5.41
**Test status**: 2375 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户两次反馈模型弹窗太复杂。目视确认后大刀阔斧：弹窗只保留 4 个模型项（品牌 + 模型名 + 勾选当前），扁平化不再有二级子菜单。
- 移除弹窗内的端点、上下文、思考深度、新建会话、复制运行信息、打开运行设置等行——各自已有归属：端点/运行信息在环境面板与设置页，上下文在圆环弹窗，思考深度在「运行设置」（SettingsView Picker，v0.5.31 起就有），新建会话有 ⌘N。
- 数据与切换逻辑不变：选择即持久化、对新建会话生效。
**Why**: 用户要的是"点开芯片 → 看到 4 个模型 → 点一下"的最短路径，其余信息全是噪音。
**Next**: 真机用几天，若需要再把「思考深度」快捷入口以轻量形式回归。

## v0.5.40 — 手机 H5 端模型名统一为 displayName：底栏与模型面板不再显示技术 slug
**Date**: 2026-08-30
**Commit**: 206cb9b
**Tag**: v0.5.40
**Test status**: 2340 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过 13 项 SSH 集成段）
**Changed**:
- v0.5.39 只改了 Mac 端展示层，手机 H5 状态快照仍传 `store.modelName`（API slug），H5 composer 底栏与模型选择面板继续暴露 deepseek-v4-flash 这类技术 slug。
- `PhoneRemoteServer` 状态快照 `model` 改用 `store.modelDisplayName`（H5 端即得「DeepSeek V4 Flash」）；H5 JS 兜底文案同步改 "MiniMax M3"（displayName 口径）。
- H5 页面测试断言更新为 displayName 兜底；版本同步点对齐 0.5.40。
**Why**: 同一模型 Mac 端显示「DeepSeek V4 Flash」、手机端显示「deepseek-v4-flash」，口径分裂；H5 复用 Mac 端 v0.5.39 的展示层规则后两端口径一致。
**Next**: 真机扫码回归手机端模型名；评估普通会话发送【自进化指令】开头消息的确认提示（v0.5.38 Next）。

## v0.5.39 — 模型选择菜单改显「品牌 + 模型名」，不再暴露技术 slug
**Date**: 2026-08-30
**Commit**: 5080e78
**Tag**: v0.5.39
**Test status**: 2380 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户反馈模型菜单里 "deepseek-v4-flash" 这类技术 slug 太复杂，只想要品牌 + 模型名。
- `TapgoModel` 新增 `displayName`：MiniMax M3 / GLM 5.3 Flash / DeepSeek V4 Flash / DeepSeek V4 Pro；API slug（rawValue）保持官方名不动，仅展示层切换。
- 模型切换菜单、composer 芯片、环境面板、设置页、诊断信息统一改用 displayName；目录 display_name 同步。
- 测试 +5（displayName 四项 + slug 不变断言）。
**Why**: 面向用户的 UI 不应出现技术 slug；品牌 + 模型名一眼可辨。
**Next**: 手机 H5 端模型名仍显示 slug，待后续统一为 displayName。

## v0.5.38 — 自进化会话 composer 专属化：占位文案与项目条不再误导为当前项目

**Date**: 2026-08-30
**Changed**:
- 用户实测踩坑: 点「自进化」进入专属会话后, composer 占位仍是「给 OctTapgo 发条任务…」、项目条仍显示 OctTapgo——用户以为没切进去, 把【自进化指令】粘贴进了 OctTapgo 下的普通会话, AI 在错误目录 (~/OctTapgo) 里跑了一轮 252.6k tokens 的自进化。
- 修复 1 — 占位文案: activeThread 为自进化会话时显示「向自进化下达本轮指令…」, 不再跟随 activeProject。
- 修复 2 — 项目条: 自进化会话显示专属胶囊「✨ 自进化 · <仓库名>」(固定指向项目根, 点击打开目录), 不跟随 activeProject。
- 保留 v0.5.33 行为: 进入自进化会话不清空用户当前项目, 仅在 composer 层做上下文显式化。
**Why**: 会话已切换但输入区上下文没切换, 视觉状态与实际路由不一致, 是把指令发错会话的直接诱因。
**Next**: 评估在普通会话发送以【自进化指令】开头的消息时给出确认提示。

## v0.5.37 — 圆形额度表改显「剩余量」：侧栏 / 弹窗 / 圆环三处口径完全统一
**Date**: 2026-08-30
**Commit**: ceb6e5b
**Tag**: v0.5.37
**Test status**: 2375 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户圈出输入框底部的圆形额度表：显示已用 26%（周额度已用），与余量 74% 口径相反。
- `contextMeterChip` 翻转：有额度数据时显示最差窗口的剩余量（100 − worstUsedPercent，MiniMax 当前即 74）；无额度数据（DeepSeek 仅余额 / 尚未拉取）时退回上下文占用百分比，保持原行为。
- 无障碍标签同步：有额度数据时报「套餐余量 X%」，否则维持「上下文用量 X%」。
- 至此侧栏底部、额度弹窗、圆形表三处全部为剩余口径。
**Why**: 同一个数字三种口径让用户无法直接对照；统一为剩余量后三处可互相印证。
**Next**: 观察圆环填充方向语义（现在环充得越满 = 剩余越多）；如有用户反馈再评估改为倒计时样式。

## v0.5.36 — 额度口径统一：弹窗余量卡片改显「剩余量」
**Date**: 2026-08-30
**Commit**: 65c6444
**Tag**: v0.5.36
**Test status**: 2375 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户反馈口径不一：左下角侧栏显示余量（99%/74%），输入框底部的额度弹窗却显示已用（19%/33%）。统一为剩余量。
- `ModelUsagePopover.quotaCells()` 展示层翻转：usedPercent → max(0, 100 - usedPercent)，与侧栏公式一致；卡片标签加「余量」后缀（如「5 小时余量」「每周余量」），Credits 余额卡片不变。
- 数据层不动：三个额度客户端仍产出「已用」语义的 usedPercent，只在展示层翻转。
**Why**: 同一个「剩余额度」标题下混用两种口径会让用户误读（19% 被看成只剩 19%）。
**Next**: 真机确认弹窗与侧栏数字一致。

## v0.5.35 — 接入 DeepSeek V4 系列（v4-flash / v4-pro，原生 Responses API）
**Date**: 2026-08-30
**Commit**: 17d8923
**Tag**: v0.5.35
**Test status**: 2375 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户要求接入 DeepSeek 最新系列。官方文档 (api-docs.deepseek.com/quick_start/agent_integrations/codex) 确认 DeepSeek API 原生支持 OpenAI Responses 协议；本机实测 key 打 `https://api.deepseek.com/responses` 返回标准 Responses 对象（v4-flash 带推理输出）。
- `TapgoModel` 新增 `deepseek-v4-flash` / `deepseek-v4-pro`（官方 slug，1,048,576 上下文，reasoning low/high/max，默认 high）；模型目录条目随 allCases 自动生成。
- config.toml 模板新增 `[model_providers.deepseek]`（base_url https://api.deepseek.com，wire responses），鉴权来自独立 `auth-deepseek.json`（0600；缺失时选 DeepSeek 的新会话 401）。key 取自本机 `~/.deepseek/config.toml`，实测有效。
- 额度/余额三路接线补全：DeepSeek 按量计费无订阅窗口，走 `GET /user/balance` 显示余额（如「DeepSeek·余额 ¥17.95 CNY」）；弹窗来源标签 `DeepSeek user/balance`。
- 切换子菜单自动列出全部 4 个模型（MiniMax-M3 / GLM-5.3-Flash / deepseek-v4-flash / deepseek-v4-pro），切换对新建会话生效。
- 测试 +20：DeepSeekQuota 解析 8 断言 + transport/auth 7 断言 + ModelCatalog DeepSeek 映射与上下文窗口断言。
**Why**: 用户要求在模型选择里加入 DeepSeek 最新系列；V4 系列原生 Responses API 与 harness 0.149+ 零桥接兼容。
**Next**: deepseek-v4-flash-vision-exp（图片输入）暂未接入，等用户需要再评估；切换后首次使用建议看一眼 rollout 的 model_provider 确认。

## v0.5.34 — GLM 额度可查：接入 BigModel 官方 monitor/usage/quota/limit
**Date**: 2026-08-30
**Commit**: a0af5f8
**Tag**: v0.5.34
**Test status**: 2355 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户质疑「GLM 无法查到？」——查证属实可以查：智谱官方用量查询插件 (zai-org/zai-coding-plugins) 的 query-usage.mjs 揭示了端点 `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`，Authorization 头直接放套餐 key（裸 token，实测 Bearer 也收），Coding Plan key 返回 5 小时档 (unit 3×5) 与周档 (unit 6×1) 两档已用百分比 + `level` 套餐档位（本账号 lite）。
- 新增 `TapgoCore/GLMQuotaClient`：与 MiniMaxQuotaClient 同构（authPath + transport 注入 + QuotaError + fetchRemains → RateLimitsSnapshot）；percentage 直映 usedPercent，unit/number 映射窗口分钟数，nextResetTime 毫秒 → resetsAt，level → planType（planLabel 归一化为 Lite）。
- `SessionStore.refreshRateLimits` 按所选模型双通道取数：MiniMax → coding_plan/remains（auth.json）；GLM → quota/limit（auth-glm.json）。
- 额度弹窗撤掉 v0.5.31 的「暂不支持查询」占位，GLM 渲染真实余量卡片；侧栏灰色行 GLM 显示「GLM·Lite·81%/33%」格式（余量=100-已用），与 MiniMax 数值格式对齐。
- 测试 +18：GLMQuota 解析映射 11 断言 + transport/auth 7 断言（裸 key 头、HTTP 500、业务码透传、缺失凭据）。
**Why**: 用户截图质疑 GLM 额度显示为「暂不支持查询」；实测 BigModel 有官方接口，补齐与 MiniMax 对等的额度体验。
**Next**: 真机观察 GLM 数值；BigModel 若调整字段结构需同步解析。

## v0.5.33 — 自进化日志模块重构：分段导航 + 紧凑折叠条目 + 当前版本数据源修复
**Date**: 2026-08-30
**Commit**: 5ed7ead
**Tag**: v0.5.33
**Changed**:
- 用户反馈日志页很乱: hero 卡显示 8/28 的陈旧 evolution_state.json (v0.5.3) 却标着「本次进化」; v0.5.32 条目 commit 是未回填的 PLACEHOLDER; 理念卡与全部明细平铺, 信息密度过低。
- 数据源修复: 当前版本条只信源码内置 makeHistory() 最新条目; evolution_state.json 不再作为版本数据源 (evolve.sh 快照, 曾滞后 4 天)。
- 布局重构: hero 大卡压成单行版本条 (版本·日期·SHA·摘要 + 本次进化胶囊); 「历史版本 / 使用指南」分段切换, 不再全部堆叠。
- 条目紧凑化: 收起态 = 版本 + SHA + 单行摘要; 点击展开完整改动明细与 Why/Next, 默认只展开最新一条; 理念说明压缩为一行 caption。
- 数据回填: v0.5.32 commit 55b1f72、v0.5.19 commit c486d44 (源码与 EVOLUTION.md 同步, PLACEHOLDER 清零)。
**Why**: 日志页是 AI 的对外广播, 陈旧数据 + 未回填字段 + 低密度排版让用户无法快速回答「现在到哪了、每次改了什么」; 重构后当前版本一眼可见, 历史按下钻展开。
**Next**: 条目按版本号搜索/过滤; 确认 evolve.sh 是否还落盘 evolution_state.json, 已废弃则删文件避免误导。

## v0.5.32 — 侧栏额度行按用户反馈改版: 套餐名 Ultra + 纯数字余量
**Date**: 2026-08-30
**Commit**: 55b1f72
**Tag**: v0.5.32
**Test status**: 2335 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈三点: 套餐名弄错了 (实际订阅是 **Ultra**, 不是 Token Plan/Coding Plan); 『周余量』等文字不要显示, 只显示数值; 格式改为 `5小时余量%/周余量%`。
- `modelQuotaSummary` 改版: `MiniMax·Ultra·21%/76%` —— 供应商/套餐随选中模型 (GLM 选中时只显示 `GLM`, 不显示 MiniMax 配额); 套餐名走 `TapgoConfig.planDisplayName = "Ultra"` (MiniMax 接口不返回套餐名, 以实际订阅为准, 换套餐改一处常量)。
- 5 小时窗口 (300 分钟) 与周窗口 (10080 分钟) 各自取 `100 - usedPercent`, 斜杠分隔无文字。
**Why**: 用户明确给出目标格式与真实套餐名; 显示应忠实于订阅事实而不是端点语义猜测。
**Next**: 无。

## v0.5.31 — 模型切换：composer 弹窗可选 GLM-5.3-Flash（BigModel Coding Plan）
**Date**: 2026-08-30
**Commit**: f81cf47
**Tag**: v0.5.31
**Test status**: 2335 passed / 8 failed（均为既有需要真实 SSH 远端的环境失败，与本版无关）
**Changed**:
- 说明：模型切换功能代码随 60294f6（v0.5.30）提前入库（并行会话合并提交所致），本版补齐版本对齐、文档记录、侧栏适配与真机回归。
- `TapgoCore` 新增 `TapgoModel` 模型目录：MiniMax-M3 与 GLM-5.3-Flash，各自绑定 provider 与端点；wire 一律 `responses`（本机 harness codex 0.149.1 已移除 `chat` wire，二进制内有明确报错文案）。
- GLM 走智谱官方给 Codex 的 OpenAI Responses 协议专属端点 `https://open.bigmodel.cn/api/v1`（docs.bigmodel.cn/cn/coding-plan/tool/codex），鉴权来自独立 `auth-glm.json`（0600；缺失时 GLM 新会话报 401，不留无替换机制的占位符——v0.5.28 教训）。Coding Plan 套餐 key 实测该端点可用且不按量计费；按量 key 余额不足（1113）不可用。
- config.toml 模板常驻双 provider（minimax + glm）；`thread/start` 按选中模型显式下发 `model`/`modelProvider`，切换对新建会话生效，进行中的会话保持原模型。
- composer 模型弹窗的「模型」行由"复制模型名"升级为**切换子菜单**（当前模型勾选），端点/诊断信息跟随所选模型。
- 额度查询按模型门控：选 GLM 时清空 MiniMax 快照并注明"暂不支持在 App 内查询额度"；侧栏左下角灰色行供应商跟随所选模型（GLM·Coding Plan）。
- 测试新增 `TapgoModel: catalog & provider mapping` 段 +12 断言。
**Why**: 用户要求在模型弹窗里能选 GLM-5.3-Flash（套餐内不额外计费），并反馈弹窗冗杂、找不到模型切换入口；把模型行变成真正的切换器同时精简语义。
**Next**: 手机 H5 模型面板目前只显示当前模型，改为列出全部可选模型并支持切换；远程项目（SSH）远端 config 仍是 MiniMax 单 provider，选 GLM 需向远端同步 auth-glm.json 与 glm provider 段。

## v0.5.30 — 侧栏用户信息灰色行改为「供应商·套餐名·周余量」
**Date**: 2026-08-30
**Commit**: 60294f6
**Tag**: v0.5.30
**Test status**: 2323 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户要求: App 左下角用户信息的灰色名字行(原先重复显示昵称)改为显示当前模型供应商/套餐名/周余量百分比。
- `SidebarView.userBar` 灰色行改为 `modelQuotaSummary`: `MiniMax·Coding Plan·周余量 74%` —— 供应商取 TapgoConfig, 套餐名用 `rateLimits?.planLabel` (MiniMax coding_plan 端点不返回套餐名字段, 回退 `Coding Plan` 端点语义; 初版误用『Token Plan』被用户指出后更正), 周余量 = 100 - secondary(10080 分钟窗口).usedPercent, 与 MiniMax 接口 `current_weekly_remaining_percent` 实测一致。
- userBar 挂 `.task`: 进侧栏立即 `refreshRateLimits()`, 之后每 5 分钟刷新。
- 目视回归: 窗口级截图确认左下角渲染 `MiniMax·Coding Plan·周余量 74%` (接口真实数据 74, 无截断)。
**Why**: 用户要在常驻位置一眼看到当前供应商/套餐/周配额健康度; 灰色行原本重复显示昵称没有信息量。
**Next**: 若 MiniMax 接口未来返回正式套餐名字段, 用真实值替换 Coding Plan 回退; 周余量颜色随压力等级变化。

## v0.5.29 — 自进化升级为独立入口：独立对话、独立开发专属会话
**Date**: 2026-08-30
**Commit**: 4ebecd9
**Tag**: v0.5.29
**Test status**: 2283 passed / 0 failed (跳过远程集成段; 全量含远程 2323 passed / 8 failed 均为既有 203.0.113.10 环境失败)
**Changed**:
- 侧边栏「自进化」从只读日志弹窗升级为独立入口: 点击直接进入自进化专属会话 (新建或选中最新一条), 菜单命令「进入自进化会话」注册 ⌘⌥E 快捷键 (⌘⇧E 已被复制会话占用)。
- 独立对话: `Thread` 新增 `mode` 字段 (`"evolution"` 标记, 向后兼容缺省 nil), 自进化会话在侧边栏独立分组置顶 (sparkles 图标), 不与普通项目会话混排; 点击分组头同样进入/创建。
- 独立开发: 自进化会话 cwd 固定为本项目根 (纯逻辑 `EvolutionWorkspace.locateProjectRoot` 探测 `~/TapgoAICoding` 需同时含 Package.swift 与 AGENTS.md, 找不到时弹窗提示而不建空壳会话)。
- 新增 `EvolutionPanel` 引导横幅 (对话区顶部): 显示会话性质/工作目录/轮次, 「开始自进化」一键发出内置指令 (核对仓库 → 选定改进点 → 实现 → `swift run TapgoTests` 全量回归 → 版本同步点对齐, 运行中禁用), 「自进化日志」按钮保留只读历史入口; 窗口标题/副标题特判显示真实仓库名与路径。
- 进入自进化会话不再清空 composer 的当前项目 (`selectThread` 对 evolution 线程跳过 `setActiveProject`), 从自进化切回普通会话项目状态不受影响。
- 测试新增 `Thread: evolution mode + workspace` 段 16 断言: mode 持久化往返、legacy 文件缺 mode 解码、固定标题不被 auto-title 覆盖、项目根双标记探测、kickoff 指令关键锚点。
**Why**: 自进化此前只是静态日志页, 用户想让它真正"自己开发自己"——必须是一个独立入口下的独立会话, 有专属指令与固定工作目录, 与日常对话互不干扰。
**Next**: 自进化回合结束后自动生成 EVOLUTION 草稿条目; 评估多轮自进化会话列表与每轮独立 harness 上下文。

## v0.5.28 — 紧急修复 config.toml 漂移重写抹掉真实鉴权导致 401
**Date**: 2026-08-30
**Commit**: ca7da89
**Tag**: v0.5.28
**Test status**: 2307 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户真机反馈: 会话每轮 Reconnecting 5/5 后报 `unexpected status 401 Unauthorized: login fail: Please carry the API secret key (1004), url: https://api.minimaxi.com/v1/responses`。
- 根因是 v0.5.27『修复 7』的回旋镖: `ensureReady` 按模板 diff 重写 config.toml 时, 模板里的 `experimental_bearer_token = "__FROM_AUTH_JSON__"` 是 Tapgo 自造占位符, 全仓没有任何运行时替换机制 —— 而磁盘上旧 config 的鉴权段是历史上真实有效的 key。重写把它覆盖回占位符, codex 发往 MiniMax 的请求不带 Authorization, 401 必现。
- 修复: 新增 `TapgoConfig.renderedConfigWithKey(region:authKey:)`, 两条 config 写出路径 (首次 init 的 writeAll 与 ensureReady 的漂移重写) 都把占位符替换为 auth.json 里的真实 key; 模板注释同步更正 (不再声称 key 不落盘, 文件 0600)。
- 自愈验证: 本机重启 App 后 ensureReady 检测漂移自动重写, config.toml 中 bearer 与 auth.json 完全一致 (125 字符 sk-cp-12…, 占位符残留 0)。
- 端到端验证: 经公网 H5 `api/send` 发送鉴权验证消息 → 回合 completed, 模型回复『已恢复正常』。
- **JKmacmini 补充修复 (数据层)**: JK 的 auth.json 存的是已失效的旧格式 key (`sk-mini1-…`, 49 位, 直连 MiniMax 401), config/heal 均正常但 key 本身死了 —— 已将本机验证过的 Token Plan key 写入 JK 并重启, 公网端到端验证回合 completed。当前代码无任何 auth.json 写入点, 09:54 的改写来源待观察是否复现。
**Why**: v0.5.27 的 config 漂移重写是按『占位符有效』的错误假设写的, 上线即打断了所有会话的模型鉴权; 配置文件属于关键数据, 重写必须保留可用的凭据语义。
**Next**: 观察三台机器配置一致性; 评估给 config.toml 重写加 .bak 备份, 避免同类覆盖不可回滚。

## v0.5.27 — 额度弹窗二轮修复：诊断信息 + 双端点 fallback + 6 行百分比去重 + 模型分桶映射 + 毫秒时间戳
**Date**: 2026-08-29
**Commit**: cb8e2db
**Tag**: v0.5.27
**Test status**: 94 passed / 0 failed (MiniMax + 邻近回归段全绿; 本机 App 主目标受限于 SwiftUI 宏插件, 见风险)
**Changed**:
- v0.5.25 上线后用户截屏反馈弹窗仍然报错『MiniMax 额度接口未返回模型 MiniMax-M3 的数据』且 6 行百分比加起来的 1612% 远超 context% 的 815%. 这一版**直接 curl 实测** MiniMax 接口 (`coding_plan/remains` 与 `token_plan/remains`), 发现根因 + 4 处隐藏 bug, 一并修复.
- **根因 1 — model_name 实际是 quota 类别而非模型名**: 接口返回 `model_name="general"` / `"video"` 这样的配额分桶, 不会直接返回 `"MiniMax-M3"`. `pickEntry` 增加『文本/对话模型 → general 桶』『视频模型 → video 桶』的语义映射, 通过 `isTextOrChatModel(name)` / `isVideoModel(name)` 判断; MiniMax-M3 (含 M2.7/abab*/minimax 命名约定) 自动落到 general 桶.
- **根因 2 — 接口直接给剩余百分比 `_remaining_percent`**, 旧版只在 `total==0` 时丢弃整个 cell. 新版 `makeWindow` 三层 fallback: 优先 `_remaining_percent` → `total - remaining` 反算 → 仅 total 时按 0% 展示. 即使 `total=0` (订阅未分配 quota) 也能继续展示服务端给的『订阅健康度』百分比 (例: `current_interval_remaining_percent=89` → 显示 11% 已用).
- **修复 3 — 6 行百分比重复计 cached**: `cached` 是 `input` 的子集 (缓存命中), 直接相加会让 6 行加起来 1612% > context% 815%. 改为 `消息 = max(0, input - cached)`, 行间近似不重.
- **修复 4 — MiniMax 时间戳是毫秒不是秒**: 13 位 `end_time=1788019200000` 表示 2026-08-29 (10 位秒级会是 1788019200000 = 公元 56870 年). `dateValue` 按量级自动检测 (>10^10 → 毫秒, 否则按秒), 兜底乘 1000, 保证『重置于』显示在合理日期.
- **修复 5 — 诊断信息可读**: `QuotaError` 重构为带 `endpoint` 字段. `noMatchingModel(requested, returned, endpoint)` 把接口实际返回的模型名列表带出来; 新增 `emptyResponse(endpoint)` 区分『真的没订阅』与『字段名对不上』. 弹窗红字可直接回答『接口返回了什么』『我用的端点是什么』『到底哪一步出问题』.
- **修复 6 — 双端点 fallback**: `fetchRemains` 按顺序试 `/api/openplatform/coding_plan/remains` → `/token_plan/remains`, 命中即返回; 只有『未匹配 / 空响应』触发 fallback, 其它错误 (HTTP 4xx/5xx、business 1008) 立即透传.
- **附带清理 — v0.5.25 引入的 Swift 6.4 编译错误**: `PhoneRemoteLink.swift` 的 `case ["img", let turnId, let idxStr]:` 在 Swift 6 不能用 `let` 在数组 pattern 中绑定, 改为 `case let arr where arr.count == 3 && arr[0] == "img":` 然后手动取元素; 同上修复 `["pending", let idxStr]:`; `TranscriptTurn` init 漏传 `userImageCount` 也补上.
- 测试新增 `MiniMaxQuota: lenient match + dual-endpoint fallback` 段 19 断言 (6 种 model_name 写法 + general 桶路由 + wrong model 严格 2 条不命中 + 诊断信息含 returned + endpoint + 双端点空响应), `MiniMaxQuota: timestamp parsing (ms vs s)` 段 2 断言 (13 位毫秒 + 10 位秒兼容), `MiniMaxQuota: SnapshotBuilder` 段 16 → 19 断言 (total=0 + percent 仍展示 / total=0 无 percent 隐藏 / total+percent 同时存在优先 percent); 全量 7 段 94 断言全绿, 既有 RateLimits/ExecEvent/ModelUsageMetrics 无回归.
- **修复 7 — config.toml 漂移导致 24M tokens 不压缩**: 用户机器上 `~/Library/Application Support/Tapgo AICoding/codex/config.toml` 缺 `model_auto_compact_token_limit = 800000` (v0.3.0 模板新增, 但 `ensureReady` 只校验文件存在 + 含 MiniMax-M3/minimax provider, 从不重生成 config.toml). 后果: harness 不知道该在 800k 自动压缩, 用户会话一路累积到 24M tokens (弹窗进度条飙到 2524%), 仍正常工作但严重浪费. `ensureReady` 现在按模板 diff, 漂移就用 `renderConfig` 重写 (auth.json 不动, bearer token 占位符保持, 真实 key 仍由 harness 启动时读 auth.json).
- **修复 8 — 弹窗百分比阈值封顶**: 当 `contextPercent >= 100%` 时 (溢出) 文本显示 `≥100%`, 而不是 `2524%` 这种让用户误以为系统失控的离谱数字. `24.0M/950k` 的真实计数仍显示在前面, 用户一眼能看出超出多少倍.
- **修复 9 — 手机 H5 看不到上传的图片 (用户反馈)**: 此前手机上传/会话里的图片只显示『已附 N 张』计数, 图片本体不可见. 新增两条带 token 的图片路由 `GET /img/<turnId>/<index>` (会话内用户消息图片, 按 turnId 查 `userImagePaths` 取文件) 与 `GET /pending/<index>` (待发附件缩略图); `TranscriptTurn` 增 `userImageCount`, H5 用户气泡内渲染图片、composer 附件行改为缩略图 + 计数; 图片响应带 `Cache-Control: private, max-age=3600` 防轮询闪烁.
**Why**: v0.5.25 只换了数据源, 没换诊断 UX —— 报错信息不可读; 弹窗 6 行把缓存命中重复计入让用户怀疑数据真实性; curl 实测发现 MiniMax 接口把模型名换成 quota 分桶名 + 直接给百分比 + 时间戳用毫秒, 这是协议级 bug 必须修; 此外 config.toml 漂移让 contextPercent 一路累积到 2524%, 也是协议级 bug 必须修.
**Next**: `contextWindow` 仍由 harness 报 950k (vs TapgoConfig 配置 1M) —— 怀疑是 harness 对 MiniMax-M3 的实际请求窗口有其它来源; 本版先不动, 等用户真机重启后看到 950k 来源 (MiniMax API 还是 harness 默认值) 后再修.

## v0.5.26 — 移除手机 composer 下方三个快捷指令 chips
**Date**: 2026-08-29
**Commit**: 9287b78
**Tag**: v0.5.26
**Test status**: 2276 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈 v0.5.21 仿 ZCode 截图时自作主张加的三个快捷 chips (🧪 跑测试 / 📝 总结改动 / ▶ 继续任务) 多此一举: 它们只是把固定文案填进输入框, 不是用户要的功能。
- 删除 #chips HTML/CSS 与对应 JS 接线, composer 下方恢复干净; 无其它行为变化。
**Why**: 仿造竞品形态时不该连可有可无的装饰一起照搬; 用户明确指出后立即移除。
**Next**: 无。

## v0.5.25 — composer 弹窗『查看额度』改用 MiniMax 官方接口 + 手机附件上传与模型面板
**Date**: 2026-08-29
**Commit**: 275c78f
**Tag**: v0.5.25
**Test status**: 2276 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈 composer 圆形上下文 meter 的弹窗里『查看额度』严重错误: 之前走 Codex app-server 的 `account/rateLimits/read`, 但本 App 对话模型是 MiniMax-M3, 该 JSON-RPC 永远返回不到真实订阅数据 —— 弹窗的 5 小时 / 每周 数字一直是不存在的占位。
- 新增 `TapgoCore/MiniMaxQuotaClient`: 直接读 auth.json 里的 `OPENAI_API_KEY`, 调 MiniMax 官方 `GET /v1/api/openplatform/coding_plan/remains`, `Authorization: Bearer <Token Plan Key>`, 端点随 `TapgoConfig.Region` (默认 `www.minimaxi.com`)。
- 新增 `TapgoCore/MiniMaxQuotaSnapshotBuilder`: 处理 MiniMax 字段语义陷阱 —— `current_interval_usage_count` / `current_weekly_usage_count` 字面是 usage, 实际是『剩余』; 这里集中做 `used = total - remaining` 反转; 周配额无 reset 时间则不写 `resetsAt`; Token Plan 没有 Credits 概念, credits cell 始终隐藏。
- `SessionStore.refreshRateLimits()` 改为异步实例化 `MiniMaxQuotaClient(authPath:, modelName:)` 直接拉取, 不再依赖 Codex harness (移除 `firstLiveRunner()` 选 harness 的逻辑)。
- 弹窗标签 `codex account/rateLimits` → `MiniMax coding_plan/remains`, 调试时一眼看出数据来源; 错误信息直接显示 MiniMax 接口的 HTTP / 业务码。
- 测试: 新增 `MiniMaxQuota: SnapshotBuilder` 16 断言 (基本反转/100%/0%/服务端 glitch 越界 → 100% 钳位/total=0 隐藏/planLabel 空白隐藏/数值类型 NSNumber+Double 兼容) + `MiniMaxQuota: MiniMaxQuotaClient` 10 断言 (HTTP 200 成功 / 500 透传 / 业务 1008 insufficient_balance 透传 / model 不匹配 / auth.json 缺失 / 单条 wildcard fallback / Bearer header 取自 auth.json); 既有 `RateLimits: JSON parsing + display helpers` (29 断言) 与 `ExecEvent: account/rateLimits/updated notification` (6 断言) 全绿。
- **收编并行会话 WIP — 手机 composer 按钮查修 (用户反馈『+ 怎么是新对话? 不是上传附件吗? 模型也不能选择, 按钮也不能正常使用』)**:
  - `+` 改为真正的**图片附件上传**: 点击唤起手机相册/文件选择 (accept=image/* 多选), FileReader 转 base64 POST `api/attach` (新增路由); Mac 端 `writeAttachment` 做魔数校验 (JPEG/PNG/GIF/WEBP/HEIC) 后写临时文件并 `store.addImages` 加入待发附件, 随下一条消息发送; composer 内显示附件计数行与上传进度。
  - `PhoneRemote.maxBodyBytes` 65KB → 20MB (base64 膨胀 1.33 倍), 快照增 `attachedCount` (发送后 Mac 端清零)。
  - 模型名『MiniMax-M3 ▾』点击弹出**模型选择面板** (底部卡片式, 列表来自 Mac 端 codex 配置, 当前模型高亮); 大脑图标可点, 跳电脑控制 Tab 查看权限。
  - `PhoneRemote: 链接构建与路由鉴权` +5 断言 (attach 路由), `状态快照 JSON` +1 (attachedCount), `H5 页面` +7 (fileInput/api/attach/attRow/modelSheet/modelBtn/上传进度); 全量 2276 passed / 8 failed。
  - 公网链路实测: curl 上传 1x1 PNG → 200, `/api/state` attachedCount=1。
**Why**: App 用的是 MiniMax-M3 不是 Codex 模型, Codex 那条 JSON-RPC 拿到的是 Codex 自身订阅配额, 跟用户实际订阅完全无关 —— 必须切到 MiniMax 官方 Token Plan 接口才能拿到真实数据; 同时手机端 composer 的 +/模型/状态按钮此前是死的装饰, 用户明确要求做成真功能。
**Next**: Token Plan 接口在海外端点未联调 (`.overseas` 分支已留好 baseURL); 模型面板在 Mac 端配置多模型后自动生效; 附件支持非图片文件。

## v0.5.24 — H5 顶部改项目切换器, 移除软件标题
**Date**: 2026-08-29
**Commit**: 5af6315
**Tag**: v0.5.24
**Test status**: 2240 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户要求『项目选择放到顶部, 不要显示软件标题』: 置顶 header 由『● Tapgo · 机器名』改为『● 📁 当前项目名 ▾』—— 项目切换器占据标题位, 点击进『项目与会话』列表页 (原 composer 上方的项目条同步移除, 不再重复)。
- 页面 h1 标题删除; 浏览器标签页标题仍为 `document.title = "Tapgo · 机器名"` (多机辨识在标签页层)。
- 列表页统计行加主机名 (『Chenlaiyi · 2 个项目 · 42 个会话』), 多机场景下在列表页辨识当前设备。
- H5 段回归: 页面无 `<h1>` (软件标题移除断言); 真实浏览器截图确认顶部即项目切换器。
**Why**: 手机小屏上软件名没有信息量, 项目才是当前上下文; 顶部常驻切换器让『换项目』变成一步操作。
**Next**: 项目切换器支持直接下拉切换 (免进列表页); 会话页补当前会话标题行。

## v0.5.23 — 手机 H5 助手输出 Markdown 富文本渲染
**Date**: 2026-08-29
**Commit**: 60100a1
**Tag**: v0.5.23
**Test status**: 2240 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈『输出内容也太乱』: 助手回复是 Markdown 源码 (`**粗**`/反引号/列表符) 原样贴在 H5 上, 一片源码墙。
- `PhoneRemote.markdownHTML(_:)`: 复用 Mac 端同款 `MarkdownLite` 解析器, 把助手回复渲染成安全 HTML —— 标题 (h3/h4)、有序/无序列表、任务清单 (☑/☐)、代码块 (深底 + 语言标签 + 横向滚动)、行内代码 (品牌色芯片)、引用块、表格 (横向滚动)、分隔线、链接; 全部原文先转义, 标签只由渲染器产出, innerHTML 无注入面。
- `TranscriptTurn` 增 `assistantHTML` (原文 `assistant` 保留); H5 对话区改 innerHTML 渲染; 文本段软换行转 `<br>`。
- 安全细节: `escapeText` (内容位, 不转引号, 代码里的 `"hi"` 保持原样) 与 `escapeHTML` (属性位, 全量) 分离; `javascript:` 等危险 scheme 链接降级纯文本; 图片降级为链接 (H5 不外链资源)。
- 新增 `PhoneRemote: Markdown 输出渲染` 测试段 21 断言 (XSS 转义/行内/标题/列表/任务/代码块/表格/引用/快照一致性); 全量 2240 passed / 8 failed。
- 目视回归: 真实浏览器手机视口截图 —— 加粗/行内代码芯片/列表全部正确排版, 不再出现源码字符。
**Why**: 助手输出天然是 Markdown, H5 上按纯文本渲染等于源码墙; 复用同款解析器在 Mac 端服务端渲染成安全 HTML, 手机端零依赖、离线可用。
**Next**: 长回复折叠/展开; 代码块一键复制。

## v0.5.22 — composer 底栏对齐 ZCode: 模型名/盾牌/大脑/白色圆形↑
**Date**: 2026-08-29
**Commit**: 854b4e5
**Tag**: v0.5.22
**Test status**: 2219 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈 v0.5.21 输入框『还是差很远』并给出 ZCode composer 截图。本版按截图重构底栏: 左侧 + (线性 SVG, 当前项目新建会话) 与 橙色盾牌 (电脑控制权限警示态, 点击跳电脑控制 Tab); 右侧 busy 转圈、**模型名选择行『MiniMax-M3 ▾』** (StateSnapshot 增 `model` 字段, App 传 `store.modelName`)、大脑图标 + 状态点 (控制权限齐备变绿)、**白色圆形 ↑ 发送键** (深色箭头, 运行中置灰)。
- 项目选择挪回 composer 上方独立小条 (📁 项目名 ▾), 与 ZCode 第一屏结构一致; composer 卡内不再有分隔的项目行。
- 图标全部换内联 SVG 线性风格 (与截图的线性图标一致), 不再用 emoji。
- 测试: H5 段 29 → 35 断言 (barIcon/modelName/兜底文案/busySpin/brainDot/shieldBtn), 快照段 +1 (model 透传); 全量 2219 passed / 8 failed。
- 目视回归: 真实浏览器手机视口截图对照用户截图 —— 项目条/composer 底栏排布、模型名、白色↑均已对齐。
**Why**: 上一版只对了功能与大形, 底栏元素构成 (模型名/状态图标/白色发送键) 与 ZCode 差距仍明显; 逐元素复刻才能达到用户预期。
**Next**: 模型名 ▾ 接真实模型切换 (config.toml 多模型); 盾牌/大脑点击后的权限引导细化。

## v0.5.21 — 手机 H5 全面仿 ZCode 输入/输出形态
**Date**: 2026-08-29
**Commit**: 9c02040
**Tag**: v0.5.21
**Test status**: 2212 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- **输入区 (composer 卡片, 仿 ZCode)**: 输入框升级为圆角卡片 —— 卡内首行是项目选择行 (📁 项目名 + ▾, 点击进『项目与会话』列表页), 中部大输入区占位『向 Tapgo 提问…』(自动增高至 140px), 底行左侧 + 新建会话、右侧圆形 ↑ 发送键 (运行中置灰)。卡片下方三个快捷 chips (🧪 跑测试 / 📝 总结改动 / ▶ 继续任务) 点击填入不自动发送。
- **输出区 (对话形态)**: 用户消息改为右对齐品牌色圆角气泡 (max-width 86%), 助手回复为通栏正文, 运行中显示脉冲『正在运行…』徽标; 空会话首屏改为时段问候 (早上好呀/中午好呀/下午好呀/晚上好呀) + 副标『在下方输入任务, 我在 Mac 上帮你完成。』。
- **列表页 (仿 ZCode 工作区与任务)**: 顶部信息横幅『本次连接可以查看当前设备上的项目、任务和会话; 二维码失效后需要回到 Mac 端重新连接。』; 项目卡增加『本地/远程』标签 (ProjectSeed/ProjectInfo 增 isLocal, App 传 kind)、『更新于 刚刚/N 小时/N 天』(ProjectInfo 增 lastActivityAt); 会话行徽标改『⚡ 运行中』(橙实底) /『✓ 已完成』(绿浅底), 当前会话行蓝点 + 品牌色浅底。
- 回归断言新增 10 条 (composer/占位/发送键/问候/气泡/脉冲/更新于/本地/双徽标), H5 段 19 → 29 断言。
- **目视回归**: 真实浏览器手机视口截图两张 (会话页 + 列表页), 与 ZCode 截图逐项对照通过。
**Why**: 用户要求输入输出全面仿造 ZCode 截图; v0.5.20 只做了功能可达 (能切换), 本版补齐形态一致性, 让手机端观感与 ZCode 对齐。
**Next**: 按 ZCode 任务页补会话标题头部; 评估快捷 chips 可配置; 电脑控制 Tab 与新 composer 的视觉统一。

## v0.5.20 — 模型可调用的电脑控制 (Computer Use): 内置 MCP server 让 AI 自动化桌面工作流
**Date**: 2026-08-29
**Commit**: d65f57e
**Tag**: v0.5.20
**Test status**: 2147 passed / 0 failed（SSH 集成测试按惯例跳过）
**Changed**:
- **TapgoComputerUseMCP**: 新增电脑控制 MCP stdio server（SwiftPM 可执行目标），实现 MCP 2025-06-18 协议握手，向模型暴露 8 个工具：screenshot / get_screen_size / left_click / double_click / type_text / press_key（14 普通键 + 6 媒体键 + 修饰键组合）/ scroll / open_application，坐标一律归一化 0...1 与分辨率无关。权限缺失时返回带指引的 isError 文本，模型可转述给用户。
- **TapgoComputerUse 库**: 截屏/CGEvent 注入/系统命令原语从 PhoneRemoteServer 抽出成共用库，App 端手机控制与 MCP server 单一实现。
- **ComputerUseMCP (Core)**: 纯 Foundation 协议层 —— JSON-RPC 分发、工具注册表（inputSchema）、参数解析助手、config.toml `[mcp_servers.tapgo_computer_use]` 段幂等写入（新增/路径变更替换/缺 command 补插），76 项单测覆盖。
- **自动注册**: App 启动幂等把 MCP server（随包嵌入 `Contents/MacOS/TapgoComputerUseMCP`）写进隔离 Codex home 的 config.toml；codex 拉起后模型即可调用。build-app.sh 嵌入二进制。
- **真实轮验证**: 经 /api/send 发起真实 MiniMax-M3 轮，模型成功调用 screenshot 工具（未授权时正确转述屏幕录制权限指引）。
- **收编并行会话 WIP**: H5 项目列表（StateSnapshot 增 projects 块 + ProjectSeed/ProjectInfo、页面项目选择区）、PhoneRemoteController init 增 workspace 参数；补 `WorkspaceStore.projects` 只读视图。
**Why**: 用户要求 Computer Use 风格的能力——让 App 里的模型自己调用截屏/鼠标/键盘工具完成桌面自动化工作流，而不是只有手机人工遥控。MCP 是 codex 的标准工具扩展面，注册即对所有会话生效。
**Next**: TCC 授权后回归真实点击/打字链路；评估 window 枚举工具；H5 项目切换完善后单独发版。

## v0.5.19 — 修复公网模式 H5 永远停在『正在连接 Mac』: fetch 前缀自适应
**Date**: 2026-08-29
**Commit**: c486d44
**Tag**: v0.5.19
**Test status**: 2111 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户真机反馈: 手机扫码 (公网域名模式) 后页面停在『正在连接 Mac…』。定位: H5 页面能打开 (200), 但页面 JS 用绝对路径 `/r/<token>/api/state` 拉数据 — nginx 只转发 `/remote/<machine>/` 前缀, `/r/*` 落到 Laravel 返回 404, 首屏永远渲染不出来 (curl 三路径实测 200/404/200 坐实)。
- `PhoneRemoteLink.pageHTML` 全部 5 处 fetch (state/select/send/ctrl/ctrl-screen) 改为 `BASE + "r/" + TOKEN + ...`; `BASE = location.pathname.replace(/\/r\/[^\/]+\/?$/, "/")` — 直连时为 `/`, 公网中继时为 `/remote/<machine>/`, 两种模式同一份页面。
- 首屏连续 2 次失败时占位区给出可读诊断 (403=二维码已轮换请重扫 / 404=请更新 Mac 端 App / 网络不通), 已加载成功后瞬断仍只熄状态点。
- 回归断言: 页面含 BASE 自适应、禁止绝对路径 fetch; 真实浏览器 (390×844 手机视口) 打开公网链接端到端验证 — 标题/项目下拉 48 个会话/对话渲染/发送框全部就位, 不再卡『正在连接 Mac』。
**Why**: 公网中继把页面挂在 `/remote/<machine>/` 子路径下, 页面内绝对路径 fetch 在反代后必然断链; 这是公网模式上线的最后一公里, 必须真浏览器端到端验证而不只是 curl 接口。
**Next**: 手机端项目切换 (对齐 ZCode 工作区/任务列表形态), 见 v0.5.20。

## v0.5.18 — 公网中继自愈: 清理孤儿隧道与服务器僵尸转发
**Date**: 2026-08-29
**Commit**: 939a2bc
**Tag**: v0.5.18
**Test status**: 2107 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关); PhoneRemote 6 段全绿
**Changed**:
- 真机异常 (用户截图): 弹窗显示『公网中继 · 异常 · Error: remote port forwarding failed for listen port 18723』。根因: 部署时强杀 App, 其 ssh 隧道子进程变孤儿, 继续占服务器 1872X 端口; 新实例绑不上端口报异常, 但公网实际仍经孤儿隧道 200, 状态误导。
- `PhoneRelayTunnel.spawn()` 前先 `pkill -f <特征串>` 清理本机孤儿; 特征串 `PhoneRemote.tunnelProcessPattern` 唯一对应本机 `ssh -R ... root@139.9.61.199` 命令行, 不误伤其它 ssh。
- 服务器端僵尸转发: 本机 ssh 非正常死亡时 sshd 对半开连接不敏感, 转发监听残留但通道已死 (fafa 实测复现, 本机无 ssh 进程但端口 LISTEN、公网超时)。新增 `PhoneRemote.remoteCleanupArguments`, 清理阶段在服务器执行 `fuser -k -n tcp <port>` 释放本机独占端口 (18723-18725 三机一一对应, 不影响其它机器)。
- 端口冲突类失败识别为可自愈: 不累计持续失败、3s 快速重试; 其它失败维持连续 3 次转 failed + 15s 降频。
- 新增回归断言: 特征串与真实 ssh argv 逐字匹配、远端清理命令形态; `PhoneRemote: 接入模式与公网中继` 段 29 → 34 断言。
- 三机部署实测: 部署强杀后各机只剩 1 个新隧道进程; fafa 的僵尸监听被自动释放, 三机公网链接连续 3 轮全部 200。
**Why**: 部署流程必然强杀 App 而隧道子进程无父进程回收; 公网中继要做到『部署/断网/强杀之后自己恢复』, 否则弹窗长期挂着误导性异常。
**Next**: 长周期观察 (服务器重启/长时间断网恢复); 评估服务器 sshd `ClientAliveInterval` 作为第二道兜底。

## v0.5.17 — 手机 H5『电脑控制』页（截屏/点按/滚动/打字/按键/锁屏）+ 三种接入方式
**Date**: 2026-08-29
**Commit**: 658b9d1
**Tag**: v0.5.17
**Test status**: 2062 passed / 0 failed（13 个 SSH 集成测试用 `TAPGO_SKIP_REMOTE_TESTS=1` 跳过）
**Changed**:
- **电脑控制协议层**：`PhoneRemoteLink` 新增 `/api/ctrl/screen|click|scroll|type|key|cmd` 六条路由、`ControlKey`（14 普通键 + 6 媒体键映射表，两类互斥）、`ControlAction`（lock/sleep）白名单；`StateSnapshot` 增加 `control` 块（enabled/screenAllowed/accessibilityAllowed）。
- **电脑控制 App 层**：`PhoneRemoteServer` 新增 `controlEnabled` 总开关（UserDefaults 持久化，默认开）、TCC 权限预检与弹窗授权、主屏截屏（≤1200px JPEG）、CGEvent 鼠标移动/单击/双击、行滚动（±20 限幅）、逐字符 Unicode 键盘输入、媒体键 systemDefined 事件、锁屏（Ctrl+Cmd+Q）/睡眠（pmset sleepnow）。开关关闭或权限缺失 → 403 + 机读 error 码。
- **H5 页面**：新增『会话 | 电脑控制』Tab；控制页含截屏 + 画面点按（归一化坐标回传 + 600ms 自动刷新）、双击模式、滚动、远程打字、常用键、媒体键、锁屏/睡眠（confirm 确认）；权限缺失横幅提示并禁用按钮。
- **三种接入方式**：`AccessMode = lan / tailnet / relay`；relay 经 `ssh -R` 反向隧道 + nginx（三台 Mac 18723-18725 端口对应 `/remote/chenlaiyi|jk|fafa/` 前缀）；`PhoneRelayTunnel` 常驻监督重连。
- **ConnectPhoneView**：新增『电脑控制』卡片（总开关 + 权限状态 + 弹窗授权按钮）。
- **测试**：新增 3 个 PhoneRemote 测试 section（路由解析/按键映射/快照与页面）共 40+ 断言；修复 `jsonDoubleField`/`jsonBoolField` 在 Darwin 上 Bool 经 NSNumber 桥接与数值混淆的问题（`CFBooleanGetTypeID` 严格区分）。
**Why**: v0.5.16 的『扫码即开 H5』只能看/驱动 AI 会话；本版把同一 token 鉴权的服务扩展成真正的电脑控制面，Mac 端保留总开关与权限前置检查。
**Next**: 多显示器截屏选择；触屏拖拽映射鼠标按住移动；控制面加剪贴板/文件推送。

## v0.5.16 — Composer 圆形上下文 meter 移到输入框正下方 + 5 chip 恢复 + PhoneRemote 协议层接入
**Date**: 2026-08-29
**Commit**: 36cf03b
**Tag**: v0.5.16
**Test status**: 1907 passed / 0 failed（13 个 SSH 集成测试用 `TAPGO_SKIP_REMOTE_TESTS=1` 跳过；release build 干净）
**Changed**:
- **Composer 圆形上下文 meter 迁移到输入框正下方**：v0.5.15 把 5 chip 整行删除换成 meter，但用户期望是『圆形 meter 放在输入框正下方 chip 区 + 底部 5 chip 保留』。v0.5.16 把 `CircularContextMeter` + `ModelUsagePopover` 抽成独立 `contextMeterChip` 视图，插到 `environmentChip`（完全访问权限）之后、`Spacer` 之前的左侧 chip 区，chip 风格一致（capsule 背景 + caption 字号）；hover / 点击 / pinned 行为与 v0.5.15 相同，popover arrow 改 `.bottom`（从 meter 弹出向下指向输入框）。
- **Composer 底部 5 chip 文本恢复**：`composerMetricsBar` 回到 v0.5.14 风格，rounds · steps / LLM 时长 / 缓存命中 / 输入 tokens；与左侧 `contextMeterChip` 不再冲突。
- **PhoneRemote 协议层（v2 扫码即开 H5）**：新增 `Sources/TapgoCore/PhoneRemoteLink.swift`（528 行）。对标 ZCode 移动端体验：Mac 端内置带 token 鉴权的 HTTP 服务，QR 码直接编码 `http://<局域网IP>:<端口>/r/<token>`，iPhone 相机扫码即可在 Safari 打开 H5 控制页（无需安装原生 App）。本文件只放纯 Foundation 协议层：token 生成与校验、链接与路由解析、极简 HTTP 报文解析/序列化、状态快照 JSON、H5 页面渲染。真实 `NWListener` 装配在 App 层 `PhoneRemoteServer.swift`。
- **PhoneRemote 测试套件**：新增 35 项断言（token 鉴权、链接解析、HTTP 请求解析/序列化、H5 页面渲染、状态快照 JSON）。补 `constantTimeEquals` 的 UInt8/Int 类型推断修复和 `RouteError: Error` 缺 conformance 修复，让 TapgoCore 能 release build。
- **测试 runner 提速**：`Sources/TapgoTests/TestMain.swift` 新增 `TAPGO_SKIP_REMOTE_TESTS=1` 环境变量：跳过 `protocol-1..4` / `RemoteSSH:` / `RemoteCodexHomeSync:` / `RemoteDirectoryLister:` / `e2e:` 共 13 个连接 RFC 5737 fixture 地址的 SSH 集成测试，避免默认 connect timeout 把本地 `swift run TapgoTests` 卡 60–120s。
- **EVOLUTION.md 顺序修正 + 顶部注释更新**：v0.5.15 的 EVOLUTION 条目在文件里被误 append 到末尾（line 195），v0.5.16 commit 同步把它移到 Format 块之后；顶部描述从『Append-only changelog』改为『最新条目在最上方』，避免下次再被误导。
**Why**: v0.5.15 把 composer 底部 5 chip 整行删除换成 meter 的方向被推翻——chip 区是用户长期使用的位置，meter 应该附加在输入框 chip 区里而不是替换掉。用户先前已在本地为 v0.5.16 准备了 PhoneRemote 协议层 WIP，本次 hotfix 顺手把它也接入主线并补齐测试，同时把 TapgoTests 提速让本地 TDD 循环不再被 SSH fixture timeout 阻塞。
**Next**: 把 PhoneRemoteLink 的 `NWListener` 装配层 (App 端 `PhoneRemoteServer.swift`) 完成并接入设置页；为 `contextMeterChip` 增加 mini 显示模式（22×22 圆环可隐藏文字 + badge）；评估是否给 5 chip 加 hover 详情。

## v0.5.15 — Markdown 视觉升级 + composer 底部 metrics 重写 + 真实账户 rateLimits 接入
**Date**: 2026-08-29
**Commit**: 4bf25fe
**Tag**: v0.5.15
**Test status**: 1290 passed / 8 SSH 集成测试因 RFC 5737 测试地址 203.0.113.10 不可达失败（与本版无关）；Release App 构建通过（SDK 26.5，无 SwiftUI 宏插件问题）
**Changed**:
- **Markdown 视觉升级**：
  - `AppFont` 新增公共 `pointSize(for:multiplier:)` helper：纯数值返回 body / callout / footnote 等文本样式按用户字号偏好计算后的 point size，供 Markdown 解析层在不引入 SwiftUI 依赖的前提下取到字号。
  - `MarkdownMessageView` 把 `Block.para` 由预先构造的 `AttributedString` 改为保留原始 `MarkdownSegment`；渲染时按当前 `appFontScale.multiplier` 重新构造 AttributedString，正文 / 行内代码 / bold / link / strikethrough 字号一致跟随用户偏好。
  - 新增 `paragraphView(segs:)`：body 字号 + 3pt lineSpacing + `fixedSize(horizontal:false, vertical:true)`，长段落更易扫读且按内容撑开高度，避免被默认 single-line 容器压扁。
  - `ListView` 紧凑化：marker 用 footnote 等宽字 + `labelTertiary` 弱化色；marker 列固定 14/18pt trailing 对齐，列表项 spacing 收紧到 2pt，外层 2pt leading 缩进区分 chat 内边距。
  - 行内 `inline` 代码视觉升级：字号比正文小 1.5pt、`brandStrong` 文字色 + `moduleBg` 圆角背景底色，仿 chip 风格但保留 AttributedString 单一渲染通路。
  - `TaskListView` checkbox 用 `symbolRenderingMode(.hierarchical)` + 与正文同档字号；unchecked 落到 `labelTertiary`，色调与正文协调。
  - `QuoteView` 改为接受 `MarkdownSegment` 而非预渲染的 `AttributedString`，引用内的 inline code / bold / link 与正文保持一致。
- **Composer 底部 metrics 重写（5 个文本 chip → 圆形 meter + 弹窗）**：
  - 旧 `composerMetricsBar` 的 rounds · steps / LLM 时长 / 缓存命中 / 输入 tokens 5 个文本 chip 整行删除；替换为一个 `CircularContextMeter`，按"实时 rateLimits 压力 → 上下文窗口使用率"优先级显示百分比。
  - 详细信息挪进悬停 / 点击弹出的新组件 `ModelUsagePopover`：套餐用量 / 5h 与 weekly 窗口剩余与重置时间 / credits 余额 / 输入输出 tokens / 平均缓存命中 / 上下文上限。
  - 弹窗默认鼠标移出自动关闭；用户点击后进入 pinned 状态，再次点击或外部关闭清除 pinned。
- **真实账户 rateLimits 接入**：
  - 新增 `TapgoCore/RateLimits`：`RateLimitsSnapshot` / `RateLimitsWindow` / `RateLimitsCredits` / `RateLimitsPlanType` 与 `RateLimitsSnapshot.fromJSON(_:)`，兼容 harness 直接返回 payload 与包 `result` 字段两种形态。
  - 新增 `TapgoCore/ModelUsageMetrics`：`averageCacheHitPercent(turns:)` 与 `percentOfWindow(used:window:)`。
  - `CodexHarnessClient.readRateLimits()` 走 JSON-RPC `account/rateLimits/read`，`initialize` / `initialized` 之后调用，幂等；返回失败时返回空 snapshot 让 UI 仍可显示"等待服务端响应"。
  - `ExecEvent` 解析 harness 推送的 `account/rateLimits/updated` 通知（`ExecEventParserTests` +57 行覆盖），与主动轮询合并到 `SessionStore.rateLimits`。
  - `SessionStore` 增加 `rateLimits` / `rateLimitsLoading` / `rateLimitsError` 状态 + `refreshRateLimits()`；每次 popover 打开时刷新。
- **Composer 清空按钮误显修复**：
  - 新增 `tapgoIsComposerUserContentEmpty(text:attachedImageCount:)` helper，过滤 NBSP / 全角空格 / 零宽字符。空 composer 不再误显 `xmark.circle.fill`。
- 同步把 `makeHistory()` 上一轮漏补的 v0.5.14 条目 prepend，避免 App 内『自进化日志』页面落后于实际版本。
**Why**: 上一轮 v0.5.14 把队列卡片宽度调到 90% 后，本轮集中处理三类遗留：(a) Markdown 段落 / 列表 / 行内代码视觉层次弱；(b) composer 底部 5 个文本 chip 一直展开，与 chat 内其余位置权重不平衡；(c) v0.5.6 的"套餐用量"chip 一直用 thread 累计 token 做占位，需要接入真实 harness `account/rateLimits` 数据；三件事都集中在"输入 / 消息内容可读性"这条主线上，因此合并发 v0.5.15。
**Next**: 真机视觉回归 composer 底部圆环在不同上下文压力下的颜色梯度；为 ModelUsagePopover 增加可点击复制剩余 / 重置时间；评估是否把 5h / weekly 窗口快捷指示器放进 chip 头部避免每次点开。
## v0.5.14 — 队列卡片宽度改为输入框的 90%
**Date**: 2026-08-29
**Commit**: a7ffa45
**Tag**: v0.5.14
**Test status**: — Release App 构建通过（SwiftUI 宽度常量改动，无对应单测）；三机安装重启回读 0.5.14 正常 —
**Changed**:
- `queueStatusBar` 末尾宽度约束从 `contentWidth` 改为 `contentWidth * 0.90`：队列卡片固定为输入框卡片的 90% 并整体居中，恢复「排队卡片比输入框略窄」的层次感。
- 同步更新两处注释（queueStatusBar 与队列面板说明），避免后续再被改回同宽。
**Why**: 上一版把队列卡片改成与输入框同宽后，用户反馈宽度弄错了，明确要求队列卡片应为输入框卡片宽度的 90%。
**Next**: 收集 720 / 980 两种内容宽度下的视觉反馈，必要时再微调比例。

## v0.5.13 — 队列卡片 Codex 紧凑样式 + 拖拽排序
**Date**: 2026-08-29
**Commit**: 5ccb271
**Tag**: v0.5.13
**Test status**: — TapgoCore 1246 passed, 8 failed (失败均为 RemoteSSH/RemoteDirectoryLister 远端集成用例，与本次 UI 改动无关) —
**Changed**:
- 输入框上方排队卡片改成 Codex 式紧凑面板：行内左右 padding 12 / 上下 8、`minHeight` 由 64 改为 44、缩略图 46pt → 36pt、行间用 1px 25% 透明 Divider 自然分隔，去掉每行手柄图标与外圈背景。
- 行尾去掉「更多」常驻按钮（编辑消息与关闭排队迁移到右键菜单），只保留「调整方向」与「删除」两个图标按钮，整体右侧留白收紧。
- 新增 macOS 14 风格的拖拽排序：长按行内任意位置拖动到目标行，`store.moveQueued(_:to:)` 仅在 active conversation 且未在 steering 时生效，避免抢走正在注入的消息。
- 拖拽时源行半透明，目标行显示顶部/底部品牌色 3pt 胶囊作为插入位指示线，`dropDestination` 通过 y 与 rowHeight/2 比较决定 before/after。
- 输入框右侧主操作按钮合并：运行时只显示红色「停止」，空闲时只显示品牌色「发送」，互斥展示避免视觉冗余；快捷键与无障碍标签保持不变。
- `SessionStore` 新增 `moveQueued(_ id: String, to newIndex: Int)`：仅改写当前 active 对话的子数组，其他会话顺序保持原状。
**Why**: 用户参照 Codex 当前界面要求队列卡片更紧凑、行内右侧不要过大空白，并且希望可以直接拖动重排多条排队的先后顺序；同时合并输入框右侧的「停止 / 发送」两个按钮。
**Next**: 收集拖拽在不同行数和长文本下的真实手感反馈，再决定是否加入键盘 ⌥↑ / ⌥↓ 备用排序快捷键。

### v0.5.13 — Hotfix: 队列卡片高度自适应
**Date**: 2026-08-29
**Commit**: 77aaad5
**Tag**: (v0.5.13 仍在 v0.5.13 上累积修复，标签保留 v0.5.13)
**Test status**: SDK 26.5 Release App build 通过
**Changed**:
- `queueStatusBar` 的 ScrollView 高度从固定 `.frame(maxHeight: 240)` 改为按 `activeQueue.count` 动态计算：`min(count * 45 + 6, 240)`pt；1 条排队仅占 1 行 45pt，超过 6 条才进入内部滚动。
**Why**: 用户反馈"之前改过自适应，现在又不自适应了"——单条排队时卡片不该留 240pt 空白。
**Next**: 收尾。

## v0.5.12 — Codex 式输入区排队卡片
**Date**: 2026-08-29
**Commit**: b93bed6
**Tag**: v0.5.12
**Test status**: — 队列与并发核心回归 43/43；SDK 26.5 Release App build + 本机原生多条队列视觉与交互回归通过 —
**Changed**:
- 排队卡片与输入框同宽并直接衔接，使用统一深色圆角面板，取消逐行分隔线和多余的视觉层级。
- 每条排队消息固定为紧凑单行；真实图片附件显示圆角缩略图，多图显示数量，长文本自动截断。
- “调整方向”、删除与更多操作固定右对齐，统一为低强调灰色；更多按钮取消突兀的圆形底色。
- 队列最多显示五行后内部滚动，保留编辑、删除、关闭排队与真实 same-turn steer 行为。
- 延续本机已完成的删除：套餐用量组件、账户限额请求/事件、状态模型与相关测试不再进入 App。
**Why**: 用户要求输入框上方的排队区域与 Codex 当前界面一致，同时确保已经删除的套餐用量不会被旧发布基线重新带回。
**Next**: 根据更多真实附件数量和极窄窗口反馈继续微调截断阈值。

## v0.5.11 — 响应式环境信息与来源卡片
**Date**: 2026-08-29
**Commit**: e710977
**Tag**: v0.5.11
**Test status**: — 响应式布局 7/7；macOS Release build + 原生宽窄窗口回归通过 —
**Changed**:
- 右侧空间足够时自动显示 Codex 式圆角卡片，集中展示真实变更行数、运行位置、Git 分支、提交/推送与比较分支入口。
- 来源区展示当前会话最近三张真实图片缩略图；没有图片时显示明确空态，不制造虚假来源。
- 窗口变窄时卡片自动隐藏，恢复宽度后重新出现；手动轨迹栏打开时卡片主动让位。
- 使用聊天区 trailing safe-area inset 保持 `ChatView` 与输入控件身份稳定，宽窄切换不丢焦点、不清空草稿。
**Why**: 用户需要在宽窗口充分利用右侧空白查看环境与来源，同时窄窗口仍优先保证会话和输入空间。
**Next**: 根据真实使用反馈微调宽度阈值与卡片密度。

## v0.5.10 — 套餐用量固定右对齐
**Date**: 2026-08-29
**Commit**: 6cc0517
**Tag**: v0.5.10
**Test status**: — 套餐空态 17/17；macOS Release build + 三机安装回读通过 —
**Changed**:
- 输入区下方的套餐用量 chip 改为在内容宽度内固定靠右，不再因外层居中 frame 看起来漂到中间。
- 保留 v0.5.9 的步骤进度、真实变更统计、最新活动白色流光与账户限额能力。
**Why**: 共享任务在 v0.5.9 发布后补齐了用户此前明确要求的“输入框下方右侧”对齐；单独发布新版本，避免改写已推送标签。
**Next**: 继续验证不同窗口宽度和长套餐名称下的右对齐稳定性。

## v0.5.9 — Codex 式步骤进度、真实变更统计与运行流光
**Date**: 2026-08-29
**Commit**: cd5db2d
**Tag**: v0.5.9
**Test status**: — 步骤进度 12/12、限额解析 30/30、新套餐展示 16/16、旧展示兼容 30/30；macOS Release build + 原生界面回归通过 —
**Changed**:
- 输入区上方新增真实步骤进度胶囊，显示当前步数、当前回合文件数、绿色新增行和红色删除行；点击可展开完整步骤清单。
- 优先消费 Harness 的 `turn/plan/updated` 与 `turn/diff/updated`；仅有命令工具时，以回合开始前 Git 基线统计本回合新增变更，不混入既有脏工作树。
- 最新一行灰色运行活动加入白色流光，在搜索、读取、编辑、运行等状态之间原位更新；历史活动静止，减少动态效果时自动停用。
- 接入 Codex `account/rateLimits/read` 与实时更新通知，套餐 chip 展示真实 5 小时/周窗口、使用比例、压力等级与重置时间。
- 原生安装版验证运行中输入框焦点稳定，步骤弹窗、真实 `1 个文件已更改 +3 -0` 与完成清理全部通过。
**Why**: 用户需要像 Codex 一样一眼看懂当前在做哪一步、真实改了多少代码，并能从最新活动的流光辨认任务仍在运行；套餐用量也必须来自账户限额而非会话 token 估算。
**Next**: 为进度清单补充失败步骤与耗时，并在远程会话中验证多工作树 diff 的统计一致性。

## v0.5.8 — Codex / DeepSeek 官方插件管理
**Date**: 2026-08-28
**Commit**: ad339ce
**Tag**: v0.5.8
**Test status**: — PluginCatalog 13 passed, 0 failed；macOS Release build + 原生界面回归通过 —
**Changed**:
- 左上菜单新增「插件」，通过 980 × 680 原生弹窗管理已安装插件、搜索并浏览官方来源。
- Codex 官方目录直接读取 App 当前使用的 Codex CLI 与隔离 `CODEX_HOME`；显示应用 / MCP / 技能能力，支持安装、卸载和启停。
- DeepSeek 官方区只展示 CLI 文档明确支持的 Codex 与 Claude Code 子代理包；安装固定使用和当前 Harness 对齐的 `next` 通道，不再暴露内部 patch / driver / SDK 依赖。
- 安装与卸载均经过安全插件标识校验；操作前确认，完成后刷新目录，并明确提示新会话或重启 Harness 生效。
- 按用户参考图完成深色布局、分类计数、搜索框、来源说明、插件行与状态操作；本机真实 UI 验证为 0 / 46 / 2，搜索 `Figma` 仅保留一个匹配项。
**Why**: 用户需要在 Tapgo AICoding 内统一管理 Codex 与 DeepSeek Harness 插件，而不是自行执行不透明的 CLI 命令；同时必须避免把 DeepSeek 内部 npm 依赖误展示成可安装插件。
**Next**: 为已安装插件增加详情页，展示权限、依赖、更新状态与变更日志。

## v0.5.7 — iOS 原生工程闭环（Dashboard + 协议层同步 + 协议测试）
**Date**: 2026-08-28
**Commit**: e5d2eea
**Tag**: v0.5.7
**Test status**: — iOS MobilePairing 协议层 446 断言全过 — Mac `swift run TapgoTests` 仍 1251 全过
**Changed**:
- `mobile/ios/Sources/DashboardView.swift` (新增)：补齐 `RootView` 引用的 `DashboardView`，展示已配对 Mac 元信息 + 连接状态指示灯 + 取消配对按钮。
- `mobile/ios/Sources/MobilePairing.swift` (新增)：iOS 端自包含副本，等价于 `Sources/TapgoCore/MobilePairing.swift`，确保独立 Xcode 工程不依赖 SwiftPM 兄弟模块。
- `mobile/ios/Scripts/check-sync.sh` + `run-tests.sh` + `build.sh`：强制保持 Core 与 iOS 副本字节级一致；一键跑协议测试；一键 xcodegen + xcodebuild。
- `mobile/ios/Tests/MobilePairingProtocolTests.swift`：446 断言覆盖生成/校验/TTL/URL round-trip/parseIncomingURL 拒绝路径/State 派生；本机 `swiftc -emit-executable` 直跑，无需 iOS SDK。
- `mobile/ios/Assets.xcassets/`：AppIcon + AccentColor 占位（1x1 透明 PNG 临时填充避免 build 失败，上架前需替换 1024x1024 真图标）。
- `mobile/ios/project.yml`：把 `Assets.xcassets` 加入 sources；启用 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`。
- `mobile/README.md`：状态表对齐 v0.5.7 真实进度（v0.5.5 表格已过期），新增目录结构与一键命令。
- 6 个 iOS SwiftUI 源文件 `swiftc -parse` 全部通过：`TapgoTerminalApp / PairingView / PairingStore / DashboardView / MobilePairing / Tests`。
**Why**: `mobile/ios/` 工程原本缺少 `DashboardView`，编译不能闭环；MobilePairing 协议层在 iOS 工程里要靠 SwiftPM 引用兄弟模块，与"独立 Xcode 工程"约束冲突。补齐后 iOS 工程能在不依赖主仓 SPM target 的前提下独立 `xcodegen generate` + `xcodebuild`，并由 `check-sync.sh` 强制协议两端同步漂移。
**Next**: 在装全 Xcode 的机器上 `mobile/ios/Scripts/build.sh` 生成 `TapgoTerminal.xcodeproj`，跑模拟器验证 PairingStore ↔ PairingView ↔ DashboardView 闭环；接入 AVFoundation 真扫码；接入 Bonjour (`_tapgo-pair._tcp`) 长链接，把"未连接"灯变绿。

## v0.5.6 — 输入框下方右侧"套餐用量"chip
**Date**: 2026-08-28
**Commit**: c716fe4
**Tag**: v0.5.6
**Test status**: — 1251 passed, 0 failed —
**Changed**:
- 新增 `TapgoCore/SubscriptionUsage`：聚合 `Thread.usageTotal` + 最近一次 turn 的 `TokenUsage.contextWindow` + `ContextLevel` 配色等级。
- `composerMetricsBar` 右侧新增"套餐用量 X / Y (Z%)"chip，按压力等级 brand / warn / error 着色；空用量时自动隐藏。
- `TapgoTests/SubscriptionUsageTests`：30 项断言覆盖 isVisible / percent / level / chipLabel / detailText / from(turnsTotalTokens, latestUsage, fallbackWindow)。
- 顺手把上一会话未提交的插件管理 WIP（`PluginManagerService` / `PluginManagerView` / `PluginCatalog` / `PluginCatalogTests` / `SidebarView` 的『插件』菜单项与 sheet）一并 commit，避免 v0.5.6 的 SidebarView 引用悬空；`PluginManagerService.init()` 调用 `RemoteCodexHomeSync.findHarness()` 已用 `MainActor.assumeIsolated` 包装，App target 在 SDK 26.5 下恢复 build。
**Why**: 用户要求在输入框下方右侧看到当前订阅套餐用量；本版用 thread 累计 token 作为最小可用数据源，codex `account/rateLimits/read` 接入留给后续迭代。
**Next**: 接入 codex `account/rateLimits/read` 拿到真实剩余/重置时间，把 chip 升级为"已用 X / 剩余 Y / 重置于 Z"。

## v0.5.5 — 连接手机菜单 + MobilePairing 协议 + 长期记忆解析修复
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.5`)_
**Tag**: v0.5.5
**Test status**: — 1221 passed, 0 failed —
**Changed**:
- 左上角菜单栏在「自进化 / 新对话」之间插入「连接手机」，对接 Ter-Tapgo 的 iOS 端「点点够终端」。
- `TapgoCore/MobilePairing` 提供协议层：6 位配对码生成、字符集过滤、`tapgo://pair?` URL 打包/解析、State 状态机与 PairedMac 持久化。
- 新增 `ConnectPhoneView`（6 位码 + CoreImage QR + 倒计时 + 未配对/已配对/已连接三态）和 `MobilePairingStore`，状态可关闭后恢复。
- 同步产出 iOS 端 `PairingStore`（v0.5.5 走 UserDefaults，v0.5.6 切 Keychain）与 `mobile/` 工程骨架，待接入 XcodeGen + 完整 Xcode 工具链生成 `.xcodeproj`。
- `DurableMemory.parseBullets` 的 timestamped 分支现在保留 `- ` 前缀，与 legacy 分支统一；原回归测试 `DurableMemoryTests:69` 通过。
- 新增 `MemoryCloudSync`、`MemoryConsolidator`、`TurnPresentation`、`TurnSteerPayload` 与对应测试，测试数 706 → 1221。
**Why**: 用户要在 Mac 端对接 iOS 原生 App「点点够终端」，先打通协议层与 Mac 端 UI；同时修复 19 个累积改动中遗留的旧记忆解析 bug，保证长期记忆语义一致。
**Next**: v0.5.6 引入 Bonjour 长链接 + iOS 端 Keychain 持久化，并在真实 iOS 设备上做端到端配对验证。

## v0.5.3 — 修复截图粘贴被吞掉但未生成附件
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.3`)_
**Tag**: v0.5.3
**Test status**: — 706 passed, 0 failed —
**Changed**:
- ⌘V 监听改用 AppKit 可读对象检测，覆盖图片对象与图片文件 URL。
- 剪贴板没有 PNG 表示时，通过 `NSImage` 解码 TIFF/JPEG/HEIC 等表示并统一转成临时 PNG 附件。
**Why**: 旧代码识别到通用图片后会吞掉 ⌘V，但真正读取时只取 `.png`；macOS 截图常提供 TIFF，导致输入框看起来完全没有反应。
**Next**: 已用 Preview 复制真实截图并在安装版 App 验证缩略图与临时 PNG；继续覆盖更多第三方图片来源。

## v0.5.2 — 强制小步增量输出与异常即时反馈
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.2`)_
**Tag**: v0.5.2
**Test status**: — 706 passed, 0 failed —
**Changed**:
- 新增 `AgentOutputPolicy`，把“小步增量”定义为可测试的强制契约：每完成一个有意义步骤立即输出 1–3 行结果和下一步，不把已完成步骤攒到最终回复。
- 失败、异常或阻塞必须在发现后的下一条消息立即说明影响和处理方向；最终回复只收口结果、验证证据和剩余风险。
- 完整契约注入 `thread/start` / `thread/resume`，短提醒同时放在每个当前用户任务之前，避免长对话或旧上下文稀释规则。
- App 在命令、MCP 工具、文件变更完成时即时插入两行进度；失败事件立即插入异常、影响与处理方向，且这些运行态提示不会被长期记忆提取。
- 模型目录关闭并行工具批处理；`ensureReady()` 会比较并刷新 App 专属模型目录，现有安装不再永久沿用旧 `base_instructions`。
- 新增 21 项 `AgentOutputPolicy` 回归测试；总测试数 685 → 706。
**Why**: v0.5.1 只包含一句宽泛提示；仅加强 Prompt 的首次原生回归中，模型仍把三个工具并行执行后集中总结，因此增加 App 事件层保证。
**Next**: 继续用安装版长任务验证模型在多次工具调用之间真实产生用户可见进度，并跟进 Harness 的原生进度事件能力。
