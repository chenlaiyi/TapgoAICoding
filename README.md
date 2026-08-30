# Tapgo AICoding

**简体中文** | [English](README_EN.md)

Tapgo AICoding 是一个原生 macOS SwiftUI 编码 Agent 客户端。它以 [OpenAI Codex Harness](https://github.com/openai/codex) 的 `app-server` 为运行时，通过 JSON-RPC 持续管理对话、工具、审批、文件改动和命令执行，并把这些能力组织成适合多项目、长任务和多台 Mac 协同开发的桌面工作区。

当前版本：**v0.5.51** · macOS 14+

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
| 电脑控制 | 独立 `Tapgo Computer Use.app` Helper、11 个 MCP 工具、截图、语义元素读取与点击、鼠标、键盘、滚动和启动应用 |
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

当前 MCP 工具：

```text
list_applications   get_app_state    click_element
screenshot          get_screen_size  left_click
double_click        type_text        press_key
scroll              open_application
```

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

规范测试命令：

```bash
TAPGO_SKIP_REMOTE_INTEGRATION=1 swift run TapgoTests
```

v0.5.51 的最新验证结果为 **2411 passed / 0 failed**。该模式只跳过依赖真实 SSH 主机的远程环境段，其余 Core、Harness、模型、存储、队列、手机远程和电脑控制测试都会执行。

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
