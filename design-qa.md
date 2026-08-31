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

# v0.5.54 ZCode 模型配置页 1:1 复刻回归

- 参考视觉真值：`/Users/chanlaiyi/TapgoAICoding/design-reference-zcode-model-settings.png`（ZCode 实机，871 × 768 px）。
- 最终实现截图：`/Users/chanlaiyi/TapgoAICoding/design-implementation-model-settings-final.png`（本机已安装 v0.5.54，890 × 769 px）。
- 同视口比较：`/Users/chanlaiyi/TapgoAICoding/design-qa-zcode-model-settings-comparison.png`（最终实现归一化到 871 × 768 后水平拼接）。
- 聚焦比较：`/Users/chanlaiyi/TapgoAICoding/design-qa-zcode-model-settings-focus-comparison.png`（两侧模型主卡均裁切为 602 × 419 px）。

## 同屏比较结论

- 设置侧栏、标题区、模型主卡的起点、宽高、供应商栏分隔和 419 px 卡片高度均与参考同视口对齐。
- 供应商栏、连接方式、剩余额度、三列额度卡、模型列表、模型行高及添加入口的视觉层级一致；最终模型三行与参考在聚焦图中同高收尾。
- 字体、深色背景、圆角、边框、状态色与图标沿用 Tapgo AICoding 原生 SwiftUI 设计令牌；图标均为 SF Symbols，无占位或低清素材。
- 额度使用真实智谱 ProviderRegistry Key 读取；本次验收恰逢 5 小时窗口于 08:30 重置，因此最终截图显示 100% 剩余，而参考截图是重置前 74%，属于实时数据差异。
- Tapgo 只展示产品已有的设置入口，没有伪造 ZCode 的浏览器控制、子智能体等未实现页面；这是范围约束，不是模型页视觉缺失。

## 交互与运行链路验证

- 智谱、MiniMax、DeepSeek 供应商可切换；当前运行模型仍保持用户原有 MiniMax M3，浏览智谱详情不会改动会话模型。
- 编辑模型、添加模型、添加供应商三个表单均由真实 AX 操作打开并取消；未填写、未保存、未删除任何用户配置。
- ProviderRegistry 的供应商/模型选择真实进入 `thread/start` 的 `model` 与 `modelProvider`；GLM-5.3、GLM-5-Turbo 和自定义 Provider 不再被旧注册表回退到 MiniMax。
- v0.5.53 迁移后的 0600 ProviderRegistry 可直接通过启动校验、会话鉴权和三家额度查询；MiniMax/智谱显示窗口剩余，DeepSeek 显示官方余额，无需恢复旧 auth 文件。

## Findings

- 三轮同视口比较已修复卡片纵向位置、主卡宽高、套餐区高度和模型行密度。
- 无剩余 P0/P1/P2 视觉或核心交互问题。
- 可接受差异：ZCode 专属 MCP 额度在 Tapgo 无对应真相源，不再占用额度卡；第三列改为真实套餐信息。ZCode 的“升级”按钮在 Tapgo 对应为真实可用的“管理”。

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

# ZCode 电脑控制与输入区入口回归

- 参考设置：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/zcode-computer-control-audit/01-zcode-computer-control-enabled.png`
- 参考输入区：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/zcode-computer-control-audit/03-zcode-input-button-visible.png`
- 实现设置：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-control-v0544/04-settings-switches-enabled.png`
- 实现输入区：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-control-v0544/07-composer-warning.png`
- 设置同屏比较：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-control-v0544/08-zcode-vs-tapgo-settings.png`
- 输入区同屏比较：`/Users/chanlaiyi/.codex/visualizations/2026/08/30/01a052a9-a532-7e22-8604-2fe3e40fb042/tapgo-computer-control-v0544/09-zcode-vs-tapgo-composer.png`
- 视口与归一化：ZCode 设置 871 × 768 px、Tapgo 设置 1080 × 720 px；ZCode 输入区 871 × 768 px、Tapgo 输入区 1125 × 768 px。设置比较按 720 px 高度、输入区比较按 768 px 高度等比缩放并水平拼接，未拉伸。

## 同屏比较结论

- 信息架构保留 ZCode 的关键层级：电脑控制总开关、独立的输入区入口显示开关、Accessibility、Screen Recording 与工具注册真值。
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
- 可接受差异：ZCode 截图所在机器权限已授权；Tapgo 本机没有这两项系统授权，因此实现截图显示真实的橙色未授权状态。未在验收中擅自修改 macOS 隐私与安全性设置。

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
