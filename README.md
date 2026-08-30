# Tapgo AICoding

**简体中文** | [English](README_EN.md)

Tapgo AICoding 是一个基于 SwiftUI 的原生 macOS 客户端，为 [OpenAI Codex Harness](https://github.com/openai/codex) 提供图形界面。内置支持 **MiniMax M3、GLM 5.3 Flash、DeepSeek V4 Flash / Pro**，并允许添加兼容 OpenAI Responses API 的自定义模型。应用通过标准输入输出与 Harness 的 `app-server` JSON-RPC 协议通信，不依赖 Shell 调用，也不使用旧式 exec 模式。v0.5.44 面向已通过 [Codex 0.150.1](https://github.com/openai/codex/releases/tag/rust-v0.150.1) 验证的服务端请求协议，并参考了 [DeepSeek Harness dsh-v0.1.1-rc.2](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.1.1-rc.2) 的恢复、上下文压缩和默认拒绝审批设计，但不嵌入其 Developer Preview Node/Python 运行时。

```text
┌──────────────────────────────────────────┐
│  SwiftUI 应用（本仓库）                   │
│  ─ NavigationSplitView：                  │
│     侧边栏 · 对话 · 轨迹                  │
│  ─ 编辑器（文字 + 图片，⌘↩ 发送）         │
│  ─ 对话持久化（跨启动恢复）                │
│  ─ 助手内容流式输出                        │
│  ─ 内联工具调用、文件改动、命令执行         │
└─────────────────┬────────────────────────┘
                  │ JSON-RPC over stdio
                  ▼
┌──────────────────────────────────────────┐
│  `codex app-server --listen stdio://`     │
│  ─ initialize / thread/start / turn/start │
│  ─ Agent 循环、沙箱、审批策略              │
│  ─ Turn / Item / Delta 通知                │
└─────────────────┬────────────────────────┘
                  │ HTTPS（兼容 OpenAI Responses API）
                  ▼
┌──────────────────────────────────────────┐
│  当前选择的模型和 OpenAI 兼容服务商         │
│  MiniMax · GLM · DeepSeek · 自定义          │
│  模型、端点与服务商写入隔离 config.toml     │
└──────────────────────────────────────────┘
```

## 为什么选择这套架构

- **Codex Harness 作为运行时**：由它负责 Agent 循环、沙箱、审批和轨迹记录；本项目专注提供原生 Mac 界面。
- **兼容 OpenAI API**：Harness 的 `model_provider` 插件支持 `base_url` 和 Bearer Token，可在不修改 Harness 的前提下切换内置或自定义服务商。
- **App-server 模式**：持续运行的 JSON-RPC 服务可提供流式增量、每个项目的生命周期、服务端审批请求和工具调用通知，能力比旧的 `codex exec` 模式完整。
- **可恢复上下文**：完成或失败的任务会恢复原 Harness 对话；若历史因压缩被裁剪，则回退到有长度限制的本地对话记录，不会静默丢失上下文。
- **默认拒绝审批**：保留当前 JSON-RPC 审批请求 ID，并明确回复 `accept` 或 `decline`；未知服务端请求会被拒绝，不会被默认批准或一直挂起。
- **稳定的 Agent 角色与记忆卫生**：编码 Agent 指令始终存在；只注入稳定、经过清理的用户和项目信息，拒绝推理轨迹、临时任务和版本快照进入长期记忆。
- **持续进度反馈**：每完成一个有意义的步骤，立即输出 1–3 行进度；失败和阻塞立即显示，最终答复只负责收尾。
- **剪贴板截图兼容**：⌘V 支持 PNG，以及 macOS 应用提供的 TIFF、JPEG、HEIC 等图像表示，并统一转换为临时 PNG 附件。
- **用户图片持久化**：发送的截图会复制到应用自己的存储目录，重新启动后仍可显示在用户消息中。
- **实时任务时间线**：运行中的消息和工具事件即时显示，不必等待最终答复。
- **感知上下文压缩**：保留 Harness 自动压缩能力，同时移除侧边栏和编辑器中容易误导的单对话上下文百分比。
- **Swift/SwiftUI**：真正的原生 Mac 应用，不使用 Electron；二进制约 5 MB，启动迅速。

## 与官方 Codex 完全隔离

Tapgo AICoding 不会读取或修改 `~/.codex/` 中的任何内容。它的配置、鉴权、模型目录和会话历史全部保存在独立的 Codex 主目录中：

```text
~/Library/Application Support/Tapgo AICoding/
└── codex/
    ├── auth.json                          # 0600，MiniMax 凭据
    ├── auth-glm.json                      # 0600，GLM 凭据（如已配置）
    ├── auth-deepseek.json                 # 0600，DeepSeek 凭据（如已配置）
    ├── config.toml                        # 0600，模型和服务商配置
    ├── model-catalogs/
    │   └── tapgo-catalog.json             # 内置与自定义模型目录
    └── sessions/                          # Harness 侧对话历史
```

日志保存在 `~/Library/Logs/Tapgo AICoding/harness.log`。

官方的 `~/.codex/config.toml` 和 `~/.codex/auth.json` 不会被触碰，因此官方 Codex 桌面应用和 CLI 可以继续正常使用。

`init-tapgo.sh` 不会读取官方 Codex 主目录或其备份；凭据只来自用户明确指定的文件、环境变量或隐藏式交互输入。

## 项目结构

```text
TapgoAICoding/
├── Package.swift                       # SwiftPM 可执行目标
├── scripts/
│   ├── init-tapgo.sh                   # 写入隔离配置、鉴权和模型目录
│   ├── build-app.sh                    # 将二进制封装为 Tapgo AICoding.app
│   └── build-icon.sh
├── AppBuilder/
│   ├── Info.plist
│   ├── PkgInfo
│   ├── TapgoAICoding.entitlements      # 无沙箱，仅供本地使用
│   └── project.yml                     # 可选的 xcodegen 配置
├── Sources/TapgoAICoding/
│   ├── App.swift                       # @main 和启动流程
│   ├── Models/                         # Thread、Turn、TurnItem、ToolCall
│   ├── Services/
│   │   ├── TapgoConfig.swift           # 独立 CODEX_HOME 和模板文件
│   │   ├── CodexHarnessClient.swift    # stdio JSON-RPC 客户端
│   │   └── SessionStore.swift          # ObservableObject 状态
│   ├── Views/                          # 侧边栏、对话、终端、Diff、审批、轨迹
│   └── Resources/
│       └── L10n.swift
├── README.md                           # 中文说明（GitHub 默认显示）
└── README_EN.md                        # 英文说明
```

## 首次安装

```bash
cd ~/TapgoAICoding
./scripts/init-tapgo.sh
```

该脚本会：

1. 检查是否安装 `codex` CLI（Homebrew cask，版本不低于 0.149.1）。查找顺序为：显式指定的 `HARNESS_BIN`、Homebrew 路径、`~/.local/bin/codex`、最后是 `PATH`。
2. 仅从显式 `--from-file` 路径、`MINIMAX_API_KEY` / `TAPGO_API_KEY` 环境变量或隐藏式交互输入中读取 MiniMax-M3 Bearer Token；脚本不会搜索 `~/.codex/` 备份。
3. 以 `0600` 权限将密钥保存到 `~/Library/Application Support/Tapgo AICoding/codex/auth.json`。
4. 写入模型目录和 `config.toml`，然后使用指定的 `CODEX_HOME` 启动 Harness，确认 `initialize` 响应中的 `codexHome` 指向隔离目录。

完成后：

- 官方 Codex 桌面应用和 CLI 仍使用 `~/.codex/`。
- Tapgo AICoding 只使用 `~/Library/Application Support/Tapgo AICoding/codex/`。
- 两者可同时运行，互不影响。

## 运行

```bash
./scripts/build-app.sh
open 'Tapgo AICoding.app'
```

脚本会：

1. 执行 `swift build -c release`，生成 `TapgoAICoding` 可执行文件。
2. 使用正确的 `Info.plist`、`PkgInfo` 和临时代码签名，将二进制封装为 `Tapgo AICoding.app`。
3. 使用 Bundle ID `com.tapgo.aicoding`，显示名称为 `Tapgo AICoding`。

首次启动后，应用会保留在 Dock 中，并显示 `AppIcon.icns` 图标。

**首次启动提示**：macOS 可能显示 Gatekeeper 警告。请在 Finder 中右键应用，依次选择“打开”→“打开”；完成一次后即可正常双击启动。

## 主要功能

| 功能 | 实现位置 |
|---|---|
| 多对话侧边栏，持久保存 Harness Thread ID | `SidebarView` |
| 助手内容流式输出 | `CodexHarnessClient` → `SessionStore` → `ChatView`；生成期间显示 `StreamingIndicator` 动画 |
| 推理轨迹和摘要 | `reasoning/textDelta` 原始轨迹与 `reasoningSummaryTextDelta` 摘要，分别折叠显示 |
| 助手 Markdown 渲染 | `MarkdownLite` → `MarkdownMessageView`；支持代码块、行内代码、粗体、删除线、标题、列表、任务列表、自动链接、引用、分隔线、表格和图片 |
| 复制助手消息 | `MessageRow` 中的 `CopyIconButton`，复制完整答复 |
| 导出 Markdown 对话 | 顶部 `square.and.arrow.up` 按钮 → `TurnMarkdown.render` |
| 多模型切换 | 内置 MiniMax M3、GLM 5.3 Flash、DeepSeek V4 Flash / Pro，并支持自定义兼容模型；切换对新对话生效 |
| 多模态输入 | `ComposerView` + `CodexHarnessClient.run(images:)` |
| 内联工具调用 | `MessageRow` 的 `.toolCall` 分支 |
| 嵌入式终端输出 | `CommandExecutionView` |
| 文件修改预览 | `FileChangeView` |
| 审批流程 | 设置 → 运行中的 `approvalPolicy`；Harness 请求时通过 `ApprovalRow` 批准或拒绝 |
| 轨迹回放 | `TrajectoryView`；支持每轮状态、开始时间、耗时和分类筛选 |
| 中断运行中的任务 | `ChatView` 工具栏调用 `turn/interrupt` JSON-RPC 方法 |
| 并行对话 | 每个对话拥有独立 Runner、队列、取消路径、审批路由和运行状态；切换对话不会中断其他任务 |
| 对话持久化和恢复 | `ThreadStore` 保存 `turns` 与 `harnessThreadId`；发送消息时通过 `thread/resume` 恢复 |
| 每轮 Token 用量 | `Turn.usage`，从 `turn/completed` 解析并显示在 `ChatView` |
| 上下文用量和快捷设置 | 顶部上下文进度条；编辑器内可切换沙箱与审批策略 |
| 对话内搜索（⌘⇧F） | 搜索用户输入、助手文本、推理、命令输出、工具参数和结果、文件路径与 Diff、审批原因 |
| 全局字号 | 设置 → 外观；支持小、中、大字号，并通过环境值注入所有视图 |

## 测试

```bash
TAPGO_SKIP_REMOTE_INTEGRATION=1 swift run TapgoTests
# 720/720 必须全部通过；跳过需要真实远程 Codex 主机的 SSH 集成测试

# 运行包含 SSH 集成测试的完整套件；没有真实远程主机时预期失败
swift run TapgoTests

swift build                 # Debug 构建
swift build -c release      # Release 构建
```

本项目没有使用 XCTest 或 swift-testing，因为本机 CommandLineTools Swift 工具链不包含这两个框架。`Sources/TapgoTests/` 中的 `TapgoTests` 可执行目标使用自定义 `TestRunner`，提供 `expect`、`expectEqual` 和 `expectThrows`，任何失败都会返回非零状态码。

测试直接导入应用使用的 `TapgoCore`，因此验证的是实际校验器、存储逻辑和 SSH 参数构造器，而不是单独复制的测试实现。当前测试范围包括：

- **`RemoteCommandBuilder`**：限制路径、主机、用户和命令；拒绝 `;`、`&&`、`$()`、换行、NUL 和超长输入；验证 `buildSshArgv` 参数结构。SSH 参数属于远程代码执行攻击面，因此这是最重要的一组断言。
- **`Project` / `RemoteHost` / `WorkspaceState`**：验证“不得伪造当前目录”的约束；远程项目的 `displayPath` 必须显示远程目标，而 `harnessCwd` 保持在本地镜像目录；同时验证 Codable 往返。
- **`WorkspaceStore`**：新增时去重、目录 `0700` / 文件 `0600` 权限、远程镜像创建，以及删除主机时的级联处理。
- **`ThreadStore`**：每个 ID 单独使用 `0600` 文件；一次性完成 v0 → v1 迁移，并重命名旧 `threads.json`，避免重复迁移；验证 `turns` 和 `items` 的持久化及往返。

## 本项目明确不做的事情

- **不共享官方 Codex 凭据**：每个服务商的凭据都保存在 Tapgo AICoding 的独立目录中，不复用官方 Codex 的认证文件。
- **不提供任意推理等级**：设置中只提供服务端默认、`none` 和 `high`；非默认值仅在 `turn/start` 时发送，旧的 `low` / `medium` 持久值会自动迁移。
- **不修改 `~/.codex/`**：官方 Codex 被视为完全独立的程序；初始化只接受明确的 `--from-file`、环境变量或隐藏式交互输入，不扫描官方配置或历史备份。
- **不使用 app-server Token 存储**：Token 保存在 `~/Library/Application Support/Tapgo AICoding/codex/auth.json`，文件权限为 `0600`，不写入 Keychain，以保持与 Codex 自身存储方式一致。

## 配置项

以下默认内容位于 `~/Library/Application Support/Tapgo AICoding/codex/config.toml`，由 `init-tapgo.sh` 写入；在应用内切换模型后，相应模型和服务商配置会同步更新：

| 配置 | 固定值 |
|---|---|
| `model` | `MiniMax-M3` |
| `model_provider` | `minimax` |
| `[model_providers.minimax].base_url` | `https://api.minimaxi.com/v1`（中国区） |
| `model_catalog_json` | `…/model-catalogs/tapgo-catalog.json` |

> 审批策略和沙箱模式属于运行时设置，不写入 `config.toml`。它们保存在 `UserDefaults` 中，并随 `thread/start` 发送；可在设置 → 运行或编辑器快捷选项中修改。服务商地址也可在设置 → 运行中调整；覆盖值会写入 `config.toml`，并从下一次 Harness 运行开始生效。

如需临时切换区域，可在执行 `init-tapgo.sh` 时传入 `TAPGO_BASE_URL=…`，脚本会使用该值。

## 限制与后续计划

- **对话持久化已完成**：Thread、Turn 和 Item 保存在 `state/v1/threads/<id>.json`，启动时重新载入，因此侧边栏和聊天记录可以跨重启保留。本地磁盘副本是界面历史的事实来源，不会重新向 Harness 拉取历史 Item。
- **对话恢复已完成**：重新打开的对话保留 `harnessThreadId`；继续发送消息时使用 `thread/resume`，不会新建 Harness Thread。
- **推理轨迹和摘要**：原始 `reasoning/textDelta` 折叠在“思考过程”中；`reasoningSummaryTextDelta` 流式写入独立的“思考摘要”。最终 `reasoning/summary` 数组仅在没有流式内容时用于补全轨迹。
- **审批可配置，默认关闭询问**：应用默认使用 `approvalPolicy: never`。可在设置 → 运行中选择“询问”，让 Harness 在执行命令、修改文件或调用工具时暂停并要求批准。不同 Codex 版本的请求和响应格式采用尽力兼容策略；如果严格策略导致任务挂起，请切换回“永不询问”或点击“中断”。

## 故障排查

- **应用显示“首次运行”页面**：尚未执行 `scripts/init-tapgo.sh`，或 `auth.json` 缺失/为空。执行脚本后点击“重新检查”。
- **Harness 立即退出**：执行 `tail -f ~/Library/Logs/Tapgo\ AICoding/harness.log` 查看日志；常见原因是密钥错误或上游 API 返回 402。
- **提示 `Model provider minimax not found`**：独立目录中的 `config.toml` 已过期或被手动修改；重新执行 `scripts/init-tapgo.sh`。
- **应用损坏或出现 Gatekeeper 警告**：在 Finder 中右键应用，选择“打开”→“打开”。本地构建采用临时代码签名，严格的 Gatekeeper 策略可能仍要求首次手动确认。
- **macOS 14 以下构建失败**：`Package.swift` 要求 macOS Sonoma。

---

## 自我演进流程

功能发布后，Agent 可以通过 `codex app-server` 持续迭代本仓库，无需人工逐个编辑文件。每次迭代都经过统一的门禁流程：

```bash
./scripts/evolve.sh patch \
  "fix: sidebar crash on empty workspace" \
  "Root cause: SidebarView assumed ≥1 project; guard with empty state."
```

该命令会依次：

1. 更新 `AppBuilder/Info.plist` 中的 `CFBundleShortVersionString` 和 `CFBundleVersion`。
2. 执行 `swift build -c release`；失败立即中止。
3. 执行 `swift run TapgoTests`；任何测试失败都会中止。
4. 向 `EVOLUTION.md` 追加记录。
5. 提交代码并创建带注释的 `vX.Y.Z` Git 标签。
6. 执行 `git push origin main --tags`。
7. 使用新二进制重新构建 `Tapgo AICoding.app`。
8. 写入 `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`。
9. 输出结果摘要和回滚命令。

如果第 2 或第 3 步失败，脚本会恢复 `Info.plist`，并且不会创建提交。

### 重启后继续迭代

```bash
./scripts/restart-and-resume.sh
```

该脚本会正常结束当前 `Tapgo AICoding.app` 进程，启动刚构建的新应用，并输出状态文件路径，供新会话恢复上下文。

底层 `codex app-server` 通过 `thread/resume` 保存 Thread；状态文件还会保存下一步任务、上次提交 SHA 和版本号。因此，即使迭代过程中应用被重启，也可以在新一轮对话中继续。

### 随时回滚

```bash
git checkout v0.3.7
./scripts/build-app.sh
./scripts/restart-and-resume.sh
```

每次已发布迭代都会创建 Git 标签并推送到 `origin/main`，因此 GitHub 本身也是备份。需要回退两个版本时，选择更早的标签，切换、重建并重启即可。

### Agent 永远不能做的事情

- 修改 `~/.codex/`；Tapgo AICoding 只能使用独立的 `~/Library/Application Support/Tapgo AICoding/codex/`。
- 未经用户明确同意升级主版本号。
- 在测试未全部通过时创建版本标签。
- 工作树存在未跟踪文件时推送。
