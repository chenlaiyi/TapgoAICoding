# Codex Desktop 消息界面对齐 QA

- source truth: `/Users/chanlaiyi/TapgoAICoding/artifacts/codex-complete-parity-v0592/08-codex-vs-tapgo-natural-combined.png` 左侧 Codex Desktop 实机窗口
- implementation target: Tapgo AICoding v0.5.92 macOS 深色模式，同尺寸消息窗口、同类完成态任务
- final implementation: `/Users/chanlaiyi/TapgoAICoding/artifacts/codex-complete-parity-v0592/11-tapgo-v0592-final-same-viewport.png`
- final comparison: `/Users/chanlaiyi/TapgoAICoding/artifacts/codex-complete-parity-v0592/12-codex-vs-tapgo-v0592-final.png`
- viewport: Codex 与 Tapgo 均为 1148 × 1344 px 原始窗口截图；最终并排图直接拼接，未缩放、未拉伸
- states covered: 长正文、表格、列表、行内代码、完成过程、单文件变更结果卡、完成态操作、composer

## 初始审计

- P0: 无。
- P1: Tapgo v0.5.91 侧栏与选中态明显亮于 Codex；主画布也偏亮，界面层级仍是 ZCode 色阶。
- P1: 完成态页脚常驻时间和文字按钮，单文件结果卡仍按批量文件列表组织，信息噪声高于 Codex。
- P1: composer 的项目、权限、电脑控制、用量、模型均使用胶囊，停止按钮为红色文字按钮，与 Codex 的纯文本控制和圆形动作按钮不同。
- P2: 思考/工具过程仍残留类别色与卡片化明细；流式占位使用扫光文字，不符合 Codex 的安静进度指示。

## 比较历史

1. baseline: `08-codex-vs-tapgo-natural-combined.png`，存在上述 P1/P2，未通过。
2. iteration 1: 将 Codex 实测深色层级、安静过程轨迹、图标式完成操作、审核结果卡和简化 composer 同步实现；同视口复核发现侧栏仍比 Codex 窄、composer 偏高。
3. iteration 2: 侧栏默认宽度锁定 292 pt，输入编辑区最小高度由 60 pt 收紧到 38 pt；`12-codex-vs-tapgo-v0592-final.png` 显示消息起点、内容宽度、composer 起点与高度已同位。

## 最终结论

- P0: 0；核心任务选择、消息阅读、复制/反馈、新建任务、模型/权限、发送/停止和差异审核均保持真实可操作。
- P1: 0；画布、标题栏、侧栏、选中态、内容列、完成过程分隔和 composer 的主要视觉层级均已对齐 Codex。
- P2: 0；常驻时间文字、长动作标签、过程类别色、扫光动画、多余胶囊和已应用徽章均已移除。
- 可接受差异：两款 App 使用各自真实任务数据；Codex 参考窗口当前包含文件变更，Tapgo 对照任务为无文件变更的完成态，但 `FileEditBatchView` 的审核入口由源码、构建与结构测试独立覆盖。Tapgo 保留自身“电脑操作”和额度圆环功能，但已压缩为图标级次要控件。

final result: passed

---

<!-- 历史 QA 记录，原样保留 -->
# 输入器上方分隔线修正验收（v0.5.60）

- 视觉真值：`artifacts/reference-desktop/main.png`（目标 IDE 3.10.1，871 × 768 px）。
- 最终实现：`artifacts/reference-desktop/tapgo-overlay-active-v0.5.60.jpg`（Tapgo AICoding 0.5.60，871 × 768 px）。
- 全屏并排证据：`artifacts/reference-desktop/reference-vs-tapgo-v0.5.60.png`（1742 × 768 px；两张原图直接横向拼接）。
- 输入器聚焦证据：`artifacts/reference-desktop/reference-vs-tapgo-composer-v0.5.60.png`（1376 × 210 px；两侧各裁切 688 × 210 px，未缩放）。
- 视口与密度归一化：两款 App 均为深色模式、活跃会话、871 × 768 原始截图；源图与实现图像素尺寸一致，无缩放或密度换算。

## Findings

- P0：0；P1：0；P2：0。
- 字体与文案：沿用 v0.5.59 已验收的系统字体、输入占位和真实会话内容，本次未改变。
- 间距与布局：输入器上方已恢复连续背景和自然留白；没有贯穿右侧工作区的横向分隔线，输入器圆角边框仍完整。
- 颜色与令牌：会话背景、输入器表面和边框继续使用现有深色令牌，无新增颜色或阴影。
- 图像与图标：本次不新增或替换资产；既有 SF Symbols 与 App 素材未受影响。
- 全屏图可判断整体层级；横线只有 1 px 左右，另用输入器聚焦图判断，因此不能只靠全屏图通过。
- 目标 IDE 与 Tapgo 的会话文字、项目数量和模型名称属于真实数据差异，不影响本次输入器边界比较。

## 比较历史

- 先前 v0.5.59 实现存在 P2：活跃会话分支在 `ComposerView` 前插入 `Divider()`，形成参考图中不存在的全宽横线。
- 修复：移除该条件分隔线，并新增结构回归断言，禁止输入器上方重新出现同类 `Divider`。
- 修复后证据：`tapgo-overlay-active-v0.5.60.jpg` 与聚焦并排图均显示输入器上方为连续深色背景；本机签名 Release App 的真实 AX 会话、输入器和相关按钮仍可访问。

final result: passed

---

# 目标 IDE 桌面整体框架重新验收（v0.5.59）

- 参考图：`artifacts/reference-desktop/main.png`（目标 IDE 3.10.1，871 × 768 px）。
- 实现图：`artifacts/reference-desktop/tapgo-overlay-active-v0.5.59.jpg`（Tapgo AICoding 0.5.59，871 × 768 px）。
- 并排图：`artifacts/reference-desktop/reference-vs-tapgo-v0.5.59.png`（两张原图直接横向拼接，未缩放、未拉伸）。
- 状态：通过（2026-09-01，本机 Developer ID 签名 Release App）。

## v0.5.58 纠错记录

- v0.5.58 使用 945 × 768 的不同宽度实现图，且把系统左右平铺误判为 目标 IDE 的覆盖层结构；原“通过”结论无效。
- 该版本已从自动更新 `appcast.xml` 移除并改为 GitHub 草稿，未安装到本机、JKmacmini 或 fafamacmini。

## 同视口并排验收结论

- P0：0；任务创建、项目/任务选择、输入和发送主路径没有阻断。
- P1：0；整窗灰色底板、右侧贯穿标题栏的深色覆盖层、侧栏、任务顶栏、消息区与输入器均无裁切、重叠或结构错位。
- P2：0（框架范围）；左右底色取样分别为 目标 IDE `RGB(51,51,51) / RGB(22,22,22)`、Tapgo `RGB(50,50,52) / RGB(21,21,23)`，侧栏边界和输入器上下边缘在同视口中基本同位。
- 侧栏真实交互已回读：“分组”为无标题扁平任务列表；“项目”为项目树与独立任务分区；侧栏收起后可用标题栏按钮恢复。
- 主区不再自动插入环境卡或输入器指标条；右侧轨迹/环境信息只在用户主动打开时显示，不挤压 目标 IDE 式会话画布。
- 内容文本、项目数量、模型名称与任务状态来自两款 App 各自真实数据，属于有意数据差异，不作为框架视觉缺陷。

---

# Codex 流式输出与输入框回归

- 参考：用户提供的 Codex 桌面端运行中及任务完成截图（深色模式）。
- 状态：通过（2026-08-28，本机 `/Applications/Tapgo AICoding.app`）。
- 历史结果：passed

## 视觉与状态

- 运行中顶部持续显示“已处理 X”及分隔线。
- 运行中每段关键消息后只显示一行灰色当前活动，搜索、读取、编辑、运行、思考在原位置替换。
- 任务完成后，每段重点内容之间保留一行灰色分类摘要；技能读取、上下文压缩、工具加载及读取/运行组合均使用完成态文案。
- 默认不显示原始 shell 命令、工具参数或重复运行卡片。
- 停止操作只保留在会话头和输入区，不附着到历史命令。

## 交互

- 真实任务持续流式输出时写入三段中文草稿，6 秒后内容完整保留。
- 输入框保持焦点；未发生控件重建、草稿回写或自动滚动抢焦点。
- 回归草稿已清空，未发送，不影响用户正在运行的任务。

---

# 插件管理界面回归

- 参考视觉真值：`/var/folders/rc/12_j75493m5bd29vc05fzr3w0000gn/T/codex-clipboard-16b3a044-73f4-4052-a33a-f23f54aac2e5.png`
- 实现截图：`/var/folders/rc/12_j75493m5bd29vc05fzr3w0000gn/T/com.openai.sky.CUAService/Tapgo AICoding Screenshot 2026-08-28 at 11.53.44 PM.jpeg`
- 同屏比较：`/tmp/tapgo-plugin-qa-comparison.jpg`
- 视口：原生 SwiftUI sheet，980 × 680 pt；深色模式，DeepSeek 官方页。
- 像素与归一化：参考 2602 × 1066 px；实现 980 × 680 px。比较图按相同高度等比缩放，未拉伸；参考包含完整侧栏，实现聚焦弹窗，属于有意状态差异。

## 同屏比较结论

- 信息架构与参考一致：顶部分类标签、右侧搜索、纵向插件列表、行尾主操作。
- 字体使用系统字体，标题/说明/元数据层级清晰；弹窗内字号和行高在原生截图中无截断。
- 间距、对齐、圆角、边框和深色背景沿用现有 Tapgo AICoding 设计令牌，列表密度接近参考。
- 颜色保持克制，品牌色仅用于插件图标与选中标签；安装按钮的主次关系清楚。
- 图标全部使用 SF Symbols，无低清、拉伸或占位素材。
- 文案明确区分“Codex 官方”和“DeepSeek 官方”，并说明来源及重启生效条件；没有把 DeepSeek 内部依赖伪装成插件市场项目。
- 弹窗本身就是本次聚焦区域，无需再裁切；两条 DeepSeek 插件的名称、版本、能力标签和安装按钮均可辨认。

## 交互验证

- 左上“插件”入口可打开弹窗，关闭与刷新按钮可访问。
- 已安装、Codex 官方、DeepSeek 官方三个标签可切换，计数分别为 0、46、2。
- 搜索 `Figma` 只保留一个匹配项；清空后恢复完整目录。
- 安装按钮可访问；未实际安装第三方插件，避免在回归中擅自改变用户插件环境。

## Findings

- 无 P0/P1/P2 视觉或交互问题。
- 可接受差异：参考图把插件页作为主内容区展示；本需求明确要求弹窗，因此实现采用原生 sheet，并保留应用侧栏不被替换。

## 比较历史

- 首次同屏比较未发现需要修改的 P0/P1/P2 问题；无需二次迭代。

历史结果：passed

---

# 步骤进度、变更统计与运行流光回归

- 参考视觉真值：`/var/folders/rc/12_j75493m5bd29vc05fzr3w0000gn/T/codex-clipboard-78fe34bf-7334-47df-92d4-2d9a678d70f5.png`
- 实现截图：`/var/folders/rc/12_j75493m5bd29vc05fzr3w0000gn/T/com.openai.sky.CUAService/Tapgo AICoding Screenshot 2026-08-29 at 12.17.05 AM.jpeg`
- 同屏比较：`/tmp/tapgo-progress-comparison.jpg`
- 状态：本机 `/Applications/Tapgo AICoding.app`，真实 Harness 任务运行中，步骤弹窗展开。

## 同屏比较结论

- 进度胶囊与参考一致地悬浮在输入区上方，包含运行指示、第 3 / 4 步、文件数、绿色新增行和红色删除行。
- 实机数据来自真实回合：`1 个文件已更改 +3 -0`；回合开始前已有脏文件未被误计入。
- 点击胶囊后弹出四行步骤清单：已完成步骤使用绿色勾选，当前步骤使用旋转指示，待办步骤使用空心圆。
- 最新灰色运行活动保持单行原位更新，并带窄幅白色流光；历史活动保持静态。减少动态效果开启时自动停用流光。
- 输入框在任务运行、进度更新和弹窗展开期间仍是独立稳定控件，AX 焦点未被活动刷新抢走。

## 功能与异常回归

- 当前 Harness 没有 `apply_patch` 工具，普通 `exec_command` 改文件不会产生 `turn/diff/updated`；实现已用回合开始前 Git 基线补齐统计。
- 基线兜底只统计本回合新出现的路径，避免把共享脏工作树中的既有修改归到当前回合。
- 临时回归文件在任务完成后已删除；未提交、未改动其他文件。
- 专项测试 12/12 通过；Release App 构建及签名通过。

## Findings

- 无 P0/P1/P2 视觉或交互问题。
- 可接受差异：参考截图为更宽的 Codex 视口；实机为当前 Tapgo 窗口尺寸，但信息层级、交互状态和颜色语义一致。

final result: passed

---

# v0.5.54 目标 IDE 模型配置页 1:1 复刻回归

- 参考视觉真值：`/Users/chanlaiyi/TapgoAICoding/design-reference-reference-model-settings.png`（目标 IDE 实机，871 × 768 px）。
- 最终实现截图：`/Users/chanlaiyi/TapgoAICoding/design-implementation-model-settings-final.png`（本机已安装 v0.5.54，890 × 769 px）。
- 同视口比较：`/Users/chanlaiyi/TapgoAICoding/design-qa-reference-model-settings-comparison.png`（最终实现归一化到 871 × 768 后水平拼接）。
- 聚焦比较：`/Users/chanlaiyi/TapgoAICoding/design-qa-reference-model-settings-focus-comparison.png`（两侧模型主卡均裁切为 602 × 419 px）。

## 同屏比较结论

- 设置侧栏、标题区、模型主卡的起点、宽高、供应商栏分隔和 419 px 卡片高度均与参考同视口对齐。
- 供应商栏、连接方式、剩余额度、三列额度卡、模型列表、模型行高及添加入口的视觉层级一致；最终模型三行与参考在聚焦图中同高收尾。
- 字体、深色背景、圆角、边框、状态色与图标沿用 Tapgo AICoding 原生 SwiftUI 设计令牌；图标均为 SF Symbols，无占位或低清素材。
- 额度使用真实智谱 ProviderRegistry Key 读取；本次验收恰逢 5 小时窗口于 08:30 重置，因此最终截图显示 100% 剩余，而参考截图是重置前 74%，属于实时数据差异。
- Tapgo 只展示产品已有的设置入口，没有伪造 目标 IDE 的浏览器控制、子智能体等未实现页面；这是范围约束，不是模型页视觉缺失。

## 交互与运行链路验证

- 智谱、MiniMax、DeepSeek 供应商可切换；当前运行模型仍保持用户原有 MiniMax M3，浏览智谱详情不会改动会话模型。
- 编辑模型、添加模型、添加供应商三个表单均由真实 AX 操作打开并取消；未填写、未保存、未删除任何用户配置。
- ProviderRegistry 的供应商/模型选择真实进入 `thread/start` 的 `model` 与 `modelProvider`；GLM-5.3、GLM-5-Turbo 和自定义 Provider 不再被旧注册表回退到 MiniMax。
- v0.5.53 迁移后的 0600 ProviderRegistry 可直接通过启动校验、会话鉴权和三家额度查询；MiniMax/智谱显示窗口剩余，DeepSeek 显示官方余额，无需恢复旧 auth 文件。

## Findings

- 三轮同视口比较已修复卡片纵向位置、主卡宽高、套餐区高度和模型行密度。
- 无剩余 P0/P1/P2 视觉或核心交互问题。
- 可接受差异：目标 IDE 专属 MCP 额度在 Tapgo 无对应真相源，不再占用额度卡；第三列改为真实套餐信息。目标 IDE 的“升级”按钮在 Tapgo 对应为真实可用的“管理”。

final result: passed

---

# v0.5.46 电脑控制系统授权与 Helper 拖拽引导回归

- 参考视觉真值：`/var/folders/z2/vmz80fpn1_j3bkp25xhym1140000gp/T/codex-clipboard-2e545212-cf1b-42c0-9db0-87edc2c3594f.png`（1187×732）
- Tapgo 实现截图：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-permission-v0546/tapgo-settings.png`（1080×720）
- 浮动拖拽面板：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-permission-v0546/drag-panel.png`（636×188，窗口内容 590×142）
- 同屏比较：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-permission-v0546/source-vs-tapgo.png`（2248×720）
- 状态：本机 `/Applications/Tapgo AICoding.app` v0.5.46 Release，真实 Helper、真实系统设置与真实权限回读。

## 同屏比较结论

- 延续参考页的左侧分组导航、右侧标题与深色卡片结构；电脑控制总开关、输入框入口开关、Accessibility 与 Screen Recording 状态均处在相同阅读层级。
- 两项系统权限分别使用蓝色“打开辅助功能设置 / 打开屏幕录制设置”入口，不再使用无法区分目标页的通用隐私设置按钮。
- Tapgo 比参考多显示真实“电脑控制 MCP 已注册”和检测修复卡，属于能力真值与恢复路径，不是空壳装饰。
- 字号、边框、圆角、分隔、开关、警告与成功色复用 Tapgo 现有设计系统；未新增占位素材或近似手绘图标。

## 系统授权与交互验证

- 安装包包含独立 `Tapgo Computer Use.app`，固定 bundle id 为 `com.tapgo.aicoding.computer-use-helper`；深度签名通过。
- 权限检测通过 Launch Services 启动 Helper 并回写只读 JSON；初始实测为 Accessibility=false、Screen Recording=false，避免继承 Terminal 或主 App 权限。
- 点击辅助功能入口精确打开 macOS“隐私与安全性 → 辅助功能”；系统列表识别 `Tapgo Computer Use.app`。
- 点击屏幕录制入口精确打开 macOS“隐私与安全性 → 录屏与系统录音”；未自动开启屏幕录制权限。
- 两个入口都会创建 590×142 的置顶拖拽面板；面板使用真实 Helper 图标与 `.app` 文件提供器，文案随目标权限切换，关闭按钮可见。
- 未执行把 Helper 拖入屏幕录制列表，也未开启屏幕录制开关；辅助功能在回归过程中意外由 off 变为 on，已停止进一步系统设置操作并以 Helper 真值回读确认。

## Findings 与修复历史

- P1 已修复：直接执行 Helper 二进制会继承调用上下文，导致两项权限误报为 true；改为 Launch Services 启动 Helper 后正确回读 false/false。
- P1 已修复：原 MCP 位于主 App `Contents/MacOS`，系统授权身份不稳定；现迁移到独立 Helper App bundle，并让配置、设置页和 Composer 共用同一身份。
- 无剩余 P0/P1/P2 视觉问题；屏幕录制仍需用户在系统设置中完成授权，属于预期安全边界。

final result: passed

---

# 目标 IDE 电脑控制与输入区入口回归

- 参考设置：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/reference-computer-control-audit/01-reference-computer-control-enabled.png`
- 参考输入区：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/reference-computer-control-audit/03-reference-input-button-visible.png`
- 实现设置：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-control-v0544/04-settings-switches-enabled.png`
- 实现输入区：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-control-v0544/07-composer-warning.png`
- 设置同屏比较：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-control-v0544/08-reference-vs-tapgo-settings.png`
- 输入区同屏比较：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-control-v0544/09-reference-vs-tapgo-composer.png`
- 视口与归一化：目标 IDE 设置 871 × 768 px、Tapgo 设置 1080 × 720 px；目标 IDE 输入区 871 × 768 px、Tapgo 输入区 1125 × 768 px。设置比较按 720 px 高度、输入区比较按 768 px 高度等比缩放并水平拼接，未拉伸。

## 同屏比较结论

- 信息架构保留 目标 IDE 的关键层级：电脑控制总开关、独立的输入区入口显示开关、Accessibility、Screen Recording 与工具注册真值。
- 两个开关均使用 macOS 原生滑动样式；开启、关闭和保留入口三种状态的视觉语义清楚。
- Tapgo 沿用自身 SwiftUI 卡片、蓝色品牌色和现有侧栏密度，没有逐像素复制 Electron 外观；权限缺失使用橙色、MCP 已注册使用绿色，状态与本机权威回读一致。
- 输入区入口与项目、权限、额度和模型选择处于同一工具行；灰色表示能力关闭，橙色表示已开启但权限未齐，绿色预留给完全就绪状态。
- 全部图标使用 SF Symbols，无新增位图、占位素材、拉伸或低清资源。

## 五态交互验证

- 总开关关闭：权限卡片收起，电脑控制 MCP 配置段被移除；输入区入口按显示偏好保留并呈灰色。
- 入口显示关闭：返回工作区后 AX 树不再包含“电脑操作”，能力开关状态保持不变。
- 总开关与入口均开启：设置页显示两个开关为 on，MCP 为已注册；本机未授权的 Accessibility 与 Screen Recording 如实显示橙色警告。
- 输入区可见：AX 描述为“电脑操作，辅助功能未授权、屏幕录制未授权”，没有把缺权限误报为可用。
- 入口直达：关闭态首次点击及启用态再次点击都直接打开“电脑控制”页，不再误落到“常规”。

## Findings 与修复历史

- 第一次实现验收发现 P1：SwiftUI 默认将 Toggle 显示为复选框；已显式使用 `.toggleStyle(.switch)` 修复。
- 第二次安装验收发现 P1：入口首次打开时，目标页状态与 sheet 展示存在竞态，偶发进入“常规”；已改为携带初始页的 `sheet(item:)` 单一状态修复。
- 修复后未发现剩余 P0/P1/P2 视觉或交互问题。
- 可接受差异：目标 IDE 截图所在机器权限已授权；Tapgo 本机没有这两项系统授权，因此实现截图显示真实的橙色未授权状态。未在验收中擅自修改 macOS 隐私与安全性设置。

final result: passed

---

# Codex 式输入区排队卡片回归

- 参考视觉真值：`/var/folders/rc/12_j75493m5bd29vc05fzr3w0000gn/T/codex-clipboard-b6c98511-94d4-40be-b00f-609b40b612c7.png`
- 原生实现截图：`/var/folders/rc/12_j75493m5bd29vc05fzr3w0000gn/T/com.openai.sky.CUAService/Tapgo AICoding QA Screenshot 2026-08-29 at 1.18.51 AM.jpeg`
- 同屏聚焦比较：`/tmp/tapgo-queue-comparison-final.png`
- 状态：本机 v0.5.12 Release 同源独立 QA bundle，加载五条真实截图附件队列；临时数据夹具未进入生产源码。

## 同屏比较结论

- 队列卡片与输入框使用相同最大宽度并以 6pt 叠接，形成一组连续组件；20pt 连续圆角、1px 边框和深色面板与参考层级一致。
- 五条消息均保持 56pt 紧凑单行，长文本尾部截断；真实图片附件以 42pt 圆角缩略图显示。
- 逐行分隔线、更多按钮圆形底和 SwiftUI Menu 默认下拉箭头均已移除，避免多余视觉噪声。
- 行首使用低强调的转向箭头；“调整方向”、删除和更多固定右对齐，字号、颜色和间距与参考一致。

## 原生交互验证

- AX 树出现唯一 `queued-message-card`，包含五条 `queued-message-row-*`；每条均有图片、单行文本、调整方向、删除和更多菜单语义。
- 点击第一条删除按钮后，AX 明确移除该行的 6 个元素（126–131），其余队列顺序及输入框保持稳定。
- 卡片最多容纳五行，超出后在卡片内部滚动；输入框仍为独立原生文本控件，不因队列刷新重建。

## Findings

- 无 P0/P1/P2 视觉或交互问题。
- 可接受差异：参考图来自更宽的 Codex 窗口；Tapgo AICoding 遵循自身内容最大宽度，但行高、缩略图、操作密度与衔接方式按相同绝对尺寸实现。

final result: passed

---

# 响应式环境信息与来源卡片回归

- 参考视觉真值：`/var/folders/rc/12_j75493m5bd29vc05fzr3w0000gn/T/codex-clipboard-d93156ae-2539-4452-846b-bc7e15cb2caf.png`
- 宽屏实现截图：`/tmp/tapgo-adaptive-environment-wide.jpeg`
- 窄屏实现截图：`/tmp/tapgo-adaptive-environment-narrow.jpeg`
- 同屏比较：`/tmp/tapgo-adaptive-environment-comparison.jpeg`
- 状态：本机 `/Applications/Tapgo AICoding.app`，真实 SwiftUI 窗口宽窄切换。

## 同屏比较结论

- 宽屏时卡片固定在聊天区右侧，圆角、深色背景、分组分隔与参考一致，不覆盖会话内容。
- 卡片完整呈现“环境信息”和“来源”两个分组；变更、运行位置、分支、提交或推送、比较分支均使用真实项目数据。
- 来源区复用真实用户图片缩略图；当前回归会话没有图片时显示明确空态，不伪造素材。
- 字号、行高、图标、颜色语义与现有 Tapgo AICoding 设计系统一致；新增行绿色、删除行红色。
- 实现采用聊天视图的 trailing safe-area inset，卡片出现或隐藏时不替换聊天视图和输入控件身份。

## 动态布局与交互验证

- 放大窗口后 AX 树出现唯一 `adaptive-environment-card`，包含“环境信息”“来源”及真实 `main` 分支。
- 切到半屏后卡片立即从 AX 树消失；恢复上一窗口尺寸后卡片重新出现。
- 宽屏、窄屏、恢复宽屏三次布局切换期间，输入框始终保持 AX 焦点。
- 未发送草稿“响应式布局草稿保留验证”在三次切换中完整保留，回归结束后已清空。
- 手动轨迹栏仍保留原交互；打开完整轨迹栏时自适应卡片让位，避免重复侧栏。

## Findings

- 无 P0/P1/P2 视觉或交互问题。
- 可接受差异：参考会话包含图片来源，回归会话没有附件，因此实现截图展示来源空态；有图片的会话会显示最近三张真实缩略图。

final result: passed
