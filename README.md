# Tapgo AICoding

**简体中文** | [English](README_EN.md)

Tapgo AICoding 是一个原生 macOS SwiftUI 编码 Agent 客户端。它以 [OpenAI Codex Harness](https://github.com/openai/codex) 的 `app-server` 为运行时，通过 JSON-RPC 持续管理对话、工具、审批、文件改动和命令执行，并把这些能力组织成适合多项目、长任务和多台 Mac 协同开发的桌面工作区。

当前版本：**v0.5.69** · macOS 14+

## 当前能力

| 领域 | 已实现能力 |
| --- | --- |
| 编码工作区 | 本地项目、SSH 远程项目、项目固定、目录选择、远端目录浏览、工作区状态持久化 |
| Agent 对话 | 流式回答、推理摘要、工具调用、命令输出、文件 Diff、审批、轨迹回放、中断与重试 |
| 并发与队列 | 多对话并行运行；同一对话支持消息排队、拖拽排序、删除、立即发送和注入当前回合 |
| 模型 | MiniMax M3、GLM 5.3 Flash、DeepSeek V4 Flash / Pro，以及任意兼容 OpenAI Responses API 的自定义模型 |
| 模型用量 | MiniMax / GLM 套餐余量、DeepSeek 余额、上下文用量及统一的剩余量展示 |
| 输入与内容 | 文本、截图和图片附件；Markdown、代码块、表格、任务列表、链接与图片渲染 |
| 搜索与导出 | 对话内搜索、全局会话搜索、复制消息、导出完整对话为 Markdown |
| 电脑控制 | 独立 `Tapgo Computer Use.app` Helper、11 个 Codex 同名主工具、8 个旧版兼容别名、AX 状态/截图、语义操作、鼠标键盘、剪贴板和拖拽 |
| 手机远程 | 扫码打开 H5 控制页；支持同一 Wi-Fi、Tailscale 和可选公网中继；可切项目/会话、发消息、上传图片和控制电脑 |
| 记忆 | USER / GLOBAL / KEY 三层持久记忆，读写开关、整理去重、容量限制和 iCloud Drive 跨 Mac 同步 |
| 插件 | 浏览、安装、启停和卸载 Codex 官方插件及受支持的 DeepSeek Harness 插件 |
| 自进化 | 专用自进化会话、版本日志、构建/测试/提交/标签闭环和可回滚状态文件 |
| 界面 | 深色/浅色/跟随系统、全局字号、设置中心、快捷键、命令面板和自适应布局 |

## 工作原理

```text
┌─────────────────────────────────────────────────────────┐
│ Tapgo AICoding.app                                      │
│ SwiftUI 工作区 · 对话 · 设置 · 轨迹 · 手机远程          │
└──────────────────────────┬──────────────────────────────┘
                           │ JSON-RPC over stdio
┌──────────────────────────▼──────────────────────────────┐
│ codex app-server                                        │
│ Thread / Turn · Agent Loop · Approval · Tool Events     │
└───────────────┬───────────────────────────┬─────────────┘
                │ Responses API             │ MCP
┌───────────────▼────────────────┐  ┌───────▼────────────────────┐
│ MiniMax / GLM / DeepSeek       │  │ Tapgo Computer Use.app     │
│ 或自定义兼容模型                │  │ 截屏 · UI 元素 · 鼠标键盘   │
└────────────────────────────────┘  └────────────────────────────┘
```

Tapgo AICoding 不实现另一套 Agent Runtime，而是直接使用 Codex Harness 的会话、工具、沙箱和审批协议。每个对话拥有独立 Runner，切换窗口或会话不会中断其他正在运行的任务。

## 系统要求

- macOS 14 Sonoma 或更高版本。
- Swift 5.9；构建完整 App 需要带 SwiftUI 宏插件的 macOS SDK。项目脚本默认使用 `macosx26.5`，可通过 `TAPGO_SDK` 覆盖。
- Codex CLI `0.149.1` 或更高版本。
- 至少一个可用模型及其 API Key。
- 电脑控制需要在 macOS“隐私与安全性”中授权独立 Helper 的辅助功能和屏幕录制权限。

## 快速开始

### 1. 获取代码

```bash
git clone https://github.com/chenlaiyi/TapgoAICoding.git
cd TapgoAICoding
```

### 2. 初始化独立 Codex Home

```bash
./scripts/init-tapgo.sh
```

初始化脚本会：

1. 检查 Codex CLI 版本。
2. 通过隐藏输入、环境变量或显式 `--from-file` 读取 MiniMax Key。
3. 创建独立的 `config.toml`、`auth.json` 和模型目录。
4. 启动 `codex app-server` 验证隔离目录是否真正生效。

也可以使用环境变量或明确指定的文件：

```bash
MINIMAX_API_KEY='…' ./scripts/init-tapgo.sh
./scripts/init-tapgo.sh --from-file /path/to/key-file
```

脚本不会扫描或迁移官方 `~/.codex/` 中的凭据。

### 3. 构建并启动

```bash
./scripts/build-app.sh
open 'Tapgo AICoding.app'
```

构建脚本只编译正式产品，并将以下内容封装到 App Bundle：

- `TapgoAICoding` 主程序。
- `TapgoComputerUseMCP` 可执行文件。
- 具有独立 Bundle ID 的 `Tapgo Computer Use.app` Helper。
- Info.plist、图标、权限和临时代码签名。

首次打开若出现 Gatekeeper 提示，请在 Finder 中右键 App，选择“打开”。

### 4. 登录与配置

进入应用后：

1. 使用 Tapgo 管理员账号完成登录。
2. 添加本地项目，或在设置中配置 SSH 远程主机。
3. 在“设置 → 模型设置”中选择模型、更新内置模型凭据或新增自定义模型。
4. 在“设置 → 常规”中确认审批策略和沙箱范围。
5. 如需电脑控制，在“设置 → 电脑控制”中启用能力并完成系统授权。

模型切换只影响新会话；进行中的会话保持创建时使用的模型和策略。

## 模型与凭据

### 内置模型

| 显示名称 | Provider | 默认端点类型 | 凭据文件 |
| --- | --- | --- | --- |
| MiniMax M3 | `minimax` | OpenAI Responses 兼容 | `auth.json` |
| GLM 5.3 Flash | `glm` | BigModel Responses | `auth-glm.json` |
| DeepSeek V4 Flash | `deepseek` | DeepSeek Responses | `auth-deepseek.json` |
| DeepSeek V4 Pro | `deepseek` | DeepSeek Responses | `auth-deepseek.json` |

自定义模型可在设置中填写显示名、品牌、API Model ID、Base URL、API Key 和上下文窗口。配置会写入独立模型注册表并生成对应 Provider，不需要修改源码。

所有模型配置都位于：

```text
~/Library/Application Support/Tapgo AICoding/codex/
```

凭据和配置文件使用 `0600` 权限。不要把这些文件复制进仓库，也不要在 Issue、日志或截图中公开 Key。

## 电脑控制

v0.5.46 起，电脑控制由独立的 `Tapgo Computer Use.app` Helper 承载真实 macOS TCC 身份，不再借用主 App、Terminal 或其他宿主进程权限。

v0.5.55 的主工具与 Codex Computer Use 同名、同参数语义：

```text
click   drag   get_app_state   list_apps   paste
perform_secondary_action   press_key   scroll   select_text
set_value   type_text
```

能力包括：自动启动并绑定目标 App；AX 树与窗口截图联合读取；默认状态差量与 `disableDiff=true` 完整回读；按元素或窗口点坐标点击；左/右/中键与连击；拖拽；按元素/坐标横纵滚动；xdotool 风格按键；纯文本、Markdown、HTML 粘贴并恢复原剪贴板；精确文本选择/光标定位；执行元素明确暴露的次级 AX 动作。旧版 `list_applications`、`click_element`、`set_element_value`、`screenshot`、`get_screen_size`、`left_click`、`double_click`、`open_application` 继续可用。

启用步骤：

1. 打开“设置 → 电脑控制”。
2. 开启“启用电脑控制”。
3. 分别打开辅助功能和屏幕录制设置。
4. 按界面提示把真实 Helper App 拖入系统允许列表。
5. 返回应用重新检测；新建会话或重启 Harness 后使用。

密码输入框等安全文本不会通过 Accessibility 元素树返回真实内容。授权状态、Helper 状态和 MCP 注册状态分别回读，不能互相替代。

## 手机远程控制

侧边栏“连接手机”会启动 Mac 内置的短期 Token HTTP 服务并生成二维码。手机使用相机扫码后直接在浏览器打开 H5 控制页，无需安装原生手机 App。

当前支持：

- 查看项目、会话、对话内容和运行状态。
- 切换项目与会话、新建会话、发送消息。
- 上传图片并查看对话图片。
- 选择模型并查看当前模型名称。
- 在已授权时截图、点击、滚动、输入、发送功能键和锁定/睡眠 Mac。
- 同一 Wi-Fi、Tailscale，以及部署完成后的可选公网中继。

链接中的 Token 应视为临时访问凭据；不用时请停止服务或刷新二维码。`mobile/ios/` 中的原生 iOS 工程仍是实验性配对客户端，当前推荐入口是扫码打开 H5 页面。

## 记忆与跨设备同步

记忆文件位于：

```text
~/Library/Application Support/Tapgo AICoding/memory/
├── user.md          # 跨项目用户偏好
├── memory.md        # 全局环境与工具事实
└── keys/            # 按 Git 分支隔离的项目记忆
```

设置中心可以分别控制读取、写入和 iCloud Drive 同步。同步范围仅限记忆 Markdown 文件，不包含 API Key、代码仓库或完整对话。写入前会做内容清理、去重和容量限制；临时任务、推理过程、凭据和版本快照不应进入长期记忆。

## 数据与安全边界

Tapgo AICoding 与官方 Codex 使用完全不同的主目录：

```text
官方 Codex          ~/.codex/
Tapgo AICoding      ~/Library/Application Support/Tapgo AICoding/codex/
应用状态            ~/Library/Application Support/Tapgo AICoding/state/v1/
应用日志            ~/Library/Logs/Tapgo AICoding/harness.log
```

- 不读取或改写官方 Codex 配置及认证文件。
- 对话按 ID 分文件保存，文件权限为 `0600`。
- 审批策略支持永不询问、每次请求询问、仅不受信任操作询问。
- 沙箱支持只读、工作区可写和完全访问。
- 默认“完全访问 + 自动批准”适合受信任的本地开发环境，但风险最高；处理陌生仓库时应主动收紧。
- 公开仓库中不得提交 `.env`、`auth*.json`、私钥、证书、Token 或生产部署凭据。

## 常用快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘N` | 新建会话 |
| `⇧⌘N` | 新任务并选择目录 |
| `⌘O` | 打开本地目录 |
| `⌘,` | 打开设置 |
| `⌘↩` | 发送消息或注入当前回合 |
| `⌘.` | 中断当前任务 |
| `⇧⌘R` | 重试上一回合 |
| `⇧⌘F` | 在当前对话中查找 |
| `⌘K` | 聚焦会话搜索 |
| `⇧⌘P` | 打开命令面板 |
| `⇧⌘T` | 切换轨迹栏 |
| `⌥⌘E` | 进入自进化会话 |
| `⇧⌘E` | 复制完整对话为 Markdown |
| `⇧⌘D` | 切换界面主题 |

## 测试与构建

### 自动更新

v0.5.56 起，左侧栏顶部与应用菜单都提供“检查更新”。App 使用 Sparkle 从
GitHub Releases 获取更新，启动后立即后台检查，之后每小时检查；更新归档
必须同时通过 EdDSA 与 Apple 代码签名验证，才能原子替换当前 App。

发布归档和 `appcast.xml`：

```bash
./scripts/create-github-release-artifacts.sh
```

Sparkle 私钥只保存在 macOS 登录钥匙串，仓库只包含公钥、appcast 签名和
SHA-256。v0.5.55 及更早版本没有更新器，需要先手动安装一次 v0.5.56；v0.5.57
已作为首个跨版本更新包发布，后续版本可继续从 App 内更新。

规范测试命令：

```bash
TAPGO_SKIP_REMOTE_INTEGRATION=1 swift run TapgoTests
```

v0.5.64 的最新验证结果为 **2610 passed / 0 failed**。该模式只跳过依赖真实 SSH 主机的远程环境段，其余 Core、Harness、模型、存储、队列、手机远程、电脑控制和自动更新分发测试都会执行。

正式产品构建：

```bash
swift build -c release --product TapgoAICoding
swift build -c release --product TapgoComputerUseMCP
```

或直接执行完整 App 打包：

```bash
./scripts/build-app.sh
```

不要把裸 `swift build -c release` 当作正式打包命令：仓库中的 `TapgoTests` 是使用 `@testable import TapgoCore` 的可执行测试目标，Release 模式应明确指定产品。

## 项目结构

```text
TapgoAICoding/
├── Package.swift
├── Sources/
│   ├── TapgoCore/                 # 纯逻辑、模型、协议、存储和安全校验
│   ├── TapgoComputerUse/          # AppKit 截图与输入原语
│   ├── TapgoComputerUseMCP/       # 独立电脑控制 MCP Server
│   ├── TapgoAICoding/             # macOS SwiftUI App
│   └── TapgoTests/                # 自定义可执行测试套件
├── AppBuilder/                    # App / Helper 的 plist、图标和签名配置
├── scripts/                       # 初始化、构建、自进化和重启脚本
├── mobile/ios/                    # 实验性原生 iOS 配对客户端
├── EVOLUTION.md                   # 版本演进记录
├── AGENT_MEMORY.md                # 已清洗的稳定项目记忆快照
├── README.md                      # 中文主页
└── README_EN.md                   # English
```

## 自进化

自进化 = 让 AI 对 Tapgo AICoding 自身做迭代开发。App 内按 `⌥⌘E` 进入自进化会话，点「开始自进化」即可跑一轮「核对 → 选点 → 实现 → 全量回归 → 版本对齐」。

### 两种模式

| 模式 | 适用对象 | 行为 |
| --- | --- | --- |
| `--local`（默认） | 任何人 clone 下来的副本 | 版本先对齐上游，然后只 commit + tag 到**本地**：不 push、不发 Release、不动 appcast。构建出的 .app 会**关闭「自动安装更新」**，避免你的定制被上游版本静默覆盖。 |
| `--publish` | 仓库维护者 | 完整闭环：push main + tag → GitHub Release → 刷新 appcast（已安装客户端据此自动更新）。需要仓库写权限，且 Sparkle 私钥在 keychain。 |

```bash
# 先看计划（不修改任何文件，脏树也可运行）
./scripts/evolve.sh --dry-run patch "fix: 侧栏空工作区崩溃" "根因与改动说明"

# 本地演进：显式列出本轮修改路径，脚本只暂存这些路径
./scripts/evolve.sh --paths Sources/TapgoCore/Foo.swift,scripts/evolve.sh   patch "fix: 侧栏空工作区崩溃" "根因与改动说明"

# 维护者发布上线（同样要求 --paths；上传前强制 HEAD == origin/main）
./scripts/evolve.sh --publish --paths Sources/TapgoCore/Foo.swift \
  --why "用户反馈的根因与取舍" \
  --change "改动点一" --change "改动点二" \
  minor "feat: 深色模式" "说明"
```

`--why` 与可重复 `--change` 会写入 `evolution/versions/vX.Y.Z.json`，再渲染到
`EVOLUTION.md` 与 release notes；缺省时至少写入 commit message，不再出现空泛理由。

安全约束（v0.5.257 起）：

- `--paths` 是显式暂存白名单，未覆盖的脏文件会让脚本拒绝运行，避免误提交无关改动。
- 同机并发会被 `.git/tapgo-evolve.lock` 拒绝；版本号取 `origin/main` 可达 tag 的语义化最高值。
- 每轮在 `codex/evolution-vX.Y.Z` 分支提交；原分支只做 fast-forward，publish 会额外推送该审计分支。
- 构建后先跑 `scripts/health-check.sh`（版本/Mach-O/Sparkle/helper/PhoneRemote/签名 6 项）；publish 成功后自动调用 `scripts/deploy-fleet.sh` 三机部署并回读 PID，失败标记 `health_failed`。
- 测试与 `.app` 构建都在 commit 之前完成；失败会自动恢复被脚本改动的版本文件。
- `evolution_state.json` 记录 `committed / local_built / published / push_failed / release_failed` 分阶段状态，可据此续跑或排障。
- Shell 回归：`./scripts/tests/run-all.sh`（lib + records + metrics + 失败注入矩阵，已接入 evolve.sh 测试阶段）。
- 迭代指标：`./scripts/evolution-metrics.py`（成功率、失败、周期、测试量、backlog 开闭）；JSON 输出加 `--json`。
- App 内看板：「自进化日志」顶部展示成功率、迭代/失败数、中位周期、backlog 与最近 10 次周期迷你趋势。
- 测试 flaky 追踪：每次测试写入 `state/test_run_history.jsonl`；失败时自动重跑失败 section，区分 `environmentFailures` 与 `realFailures`，并可用 `scripts/test-failure-report.py flaky` 查看。
- 运行态进度：`evolve.sh` 写 `state/evolution_progress.json`（9 阶段）；会话横幅显示进度条、Token/用时，支持停止请求与上一 tag → 当前的 diff 审阅。
- 自改门禁：`evolution/protected-paths.json` 定义受保护路径；变更 evolve.sh/测试/AGENTS.md 等必须携带精确内容 token（`--approve-protected`），否则拒绝启动并写入 `protectedGate` 状态。
- 版本序列：Mac 0.x 记录在 `EVOLUTION.md`；iOS 1.0.x 独立存放于 `evolution/ios/EVOLUTION.md`，不参与 Mac tag/Info.plist/makeHistory 校验。
- 历史归档：v0.5.5 之前 11 个版本节存放于 `evolution/archive/EVOLUTION-pre-0.5.5.md`，主日志仅保留 v0.5.5 之后。
- worktree 验证：publish 前从 tag 创建 detached worktree 做 clean-checkout 构建，确保 tag 自包含；失败不推送并标记 `worktree_verify_failed`。
- UI 回归：`scripts/preview-evolution-ui.sh` 离屏渲染进度/指标/diff 组件为 1800×1960 PNG（不启动第二个 App）；`evolution-ui-snapshot-test` 自动断言尺寸与非空。
- 指标详情：日志页「指标详情」展示周期趋势柱状图、状态时间线、失败原因、flaky 列表与 health/worktree 通过数。
- 评测基准：`evolution/benchmark.json` 定义确定性检查（总分 100）；`evolve.sh` 每轮计分并写入 JSONL 历史，低于历史最高分即回滚不推送。
- 模型级评测框架：`scripts/evolution-model-eval.py` 提供固定任务、参考解自检与可插拔 runner；真实模型运行必须显式提供 `EVOLVE_MODEL_RUNNER`，Codex 不会自动委派其它 agent。
- 反馈回归注册表：`evolution/feedback/registry.json` 把 6 条真实用户反馈固定为最小复现检查，`scripts/evolution-feedback.py verify` 进入 benchmark。
- 模型评测防线：`scripts/run-model-eval.sh` 必须显式确认消费额度并提供 runner；单任务超时、token/费用/总时长超限会中断，结果回写指标看板。
- 反馈草稿：`scripts/evolution-feedback-draft.py discover` 扫描反馈快照关键词并去重写入 `drafts.json`；草稿需人工补最小复现 check 后才提升到正式 registry。
- 多 runner A/B：`evolution-model-eval.py ab --runners "name=cmd" --runners "name=cmd" --require-candidate-not-worse` 对比通过率/耗时/成本，候选退化即失败。
- 手机端状态：PhoneRemote 快照暴露自进化版本/阶段进度/benchmark/model eval/backlog，H5 首页显示自进化卡片。
- 草稿建议：`evolution-feedback-draft.py suggest` 按类别匹配现有测试 section，生成候选最小复现命令模板，人工确认后才提升 registry。
- 多机锁：publish 前通过远端 `refs/heads/evolution-lock` 原子互斥；冲突显示持有者与 age，只有显式 `--break-remote-lock` 才可抢占陈旧锁。
- 待办单一入口：`evolution/BACKLOG.md`（EVO-001..014），每轮完成后更新状态。
- 选点闭环：`scripts/evolution-backlog.py top` 取最高优先级未完成项；App 横幅显示「下一项」并注入 kickoff prompt，`evolve.sh` 未显式传 `--next` 时自动写入记录。

### 跟上上游，同时保留你的改动

本地演进几轮后，上游也会有新版本。直接 `git pull` 容易冲突或覆盖你的改动，用同步脚本更稳：

```bash
./scripts/sync-upstream.sh          # 预检：本地/上游各有多少 commit、分别是什么
./scripts/sync-upstream.sh --apply  # 以 rebase 方式把本地演进叠到上游之上
```

### 相关环境变量

| 变量 | 用途 |
| --- | --- |
| `TAPGO_REPO_SLUG` | 覆盖仓库归属（默认从 git remote 推断，格式 `owner/repo`）。fork 用户发布到自己仓库时无需改脚本。 |
| `TAPGO_PROJECT_ROOT` | 指定项目根目录。默认探测 `~/TapgoAICoding`，以及 `TapgoAICoding-main`、`tapgo-aicoding`、`~/dev/...`、`~/Projects/...` 等常见位置。 |
| `TAPGO_FEED_URL` | 本地定制构建时指定自己的更新源（配合 `--local` 使用）。 |

### 回滚

```bash
git checkout v0.5.51   # 任意历史版本
./scripts/build-app.sh
```

## 发布与回滚

版本演进记录在 [EVOLUTION.md](EVOLUTION.md)。正式发布应保持以下状态一致：

- `AppBuilder/Info.plist`
- `AppBuilder/project.yml`
- App 内自进化日志
- Git commit 与 `vX.Y.Z` 标签
- 本机及协作 Mac 上安装的 App 版本

回滚示例：

```bash
git checkout v0.5.51
./scripts/build-app.sh
open 'Tapgo AICoding.app'
```

切换历史标签会进入 detached HEAD；继续开发前应切回 `main` 并重新核对远端状态。

## 当前限制

- App 使用临时代码签名，首次运行和 Helper 授权需要人工确认。
- 电脑控制只在辅助功能、屏幕录制和 MCP 三项状态都有效时完整可用。
- 远程 SSH 集成测试依赖真实主机，默认离线测试会跳过这些段。
- 公网手机中继需要额外的服务器和反向代理部署；本仓库不包含生产凭据。
- `mobile/ios/` 尚未作为正式 App Store 客户端发布，Android 工程仍未完成。
- 当前构建脚本依赖可用的 SwiftUI 宏插件 SDK；更换 Xcode/SDK 后应先验证工具链。

## 许可证

仓库当前未提供独立开源许可证。公开可读不等于自动授予复制、修改或再发布权；如需对外开源，请先补充明确的 `LICENSE` 文件。
