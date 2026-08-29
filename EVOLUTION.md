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

## v0.5.24 — H5 顶部改项目切换器, 移除软件标题
**Date**: 2026-08-29
**Commit**: PLACEHOLDER
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
**Commit**: PLACEHOLDER
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

