# Tapgo AICoding · 长期记忆快照

> 本文件由 Codex 会话开始时注入的“已清洗的长期记忆”落盘而成，供本地查阅与跨会话复用。
> 生成时间：2026-08-28 19:48 (Asia/Shanghai)
> 来源会话：当前 Codex 会话（CODEX_HOME=`/Users/chenlaiyi/Library/Application Support/Tapgo AICoding/codex`）
> 注意：Codex 本地记忆库 `memories_1.sqlite`（表 `stage1_outputs`）当前为 0 条，本快照以注入到会话中的清洗后内容为准。

## 跨会话记忆（已清洗）

- Tapgo AICoding 位于 `/Users/chenlaiyi/TapgoAICoding`，是 macOS 原生 SwiftUI 客户端，通过 Codex Harness `app-server` 的 JSON-RPC stdio 协议执行编码任务，并使用独立 Codex home
- Tapgo AICoding 使用 MiniMax-M3，模型与 Harness 能力必须以实际工具调用、当前工作区、测试和原生 App 结果验证，不能凭摘要猜测
- 项目按 TapgoCore、TapgoAICoding、TapgoTests 分层，发布流程使用构建脚本、自动化测试、Git 提交与版本标签形成可回滚闭环
- 本机仅有 CommandLineTools 时可能缺 SwiftUI 宏插件；App 目标需用匹配的完整 Xcode 工具链构建，并把 Core 测试与 App 构建分开报告
- 用户在多台 Mac 上协同开发；动代码前先核对远端主线、本地主线和未提交改动，避免覆盖其他任务或脏工作树
- 用户要求区分源码修改、测试、App 构建、已安装版本、原生界面回归和线上状态，不用其中一层代替另一层
- 用户偏好简体中文、语言精简准确，并要求每完成一个有意义步骤就用 1–3 行报告进度
- 失败或异常必须立即反馈，不得藏在最终总结；收到明确开发任务后应主动检查、实现并验证，不要只复述或追问下一步
- 项目名称为 Tapgo AICoding，开发约定记录在 AGENTS.md；使用简体中文协作。
- 开发前先 `git fetch origin` 并核对本地/远端/未提交改动；源码修改、测试、App 构建、已安装版本、原生界面回归五层需分开报告。
- 用户项目名为 **Tapgo AICoding**，根目录约定文件为 `AGENTS.md`，首行内容为 `# Tapgo AICoding 开发约定`。
- 项目使用 Swift 模块化结构，关键目录包括 `Sources/TapgoAICoding`（含 Services、Views）、`Sources/TapgoCore`、`Sources/TapgoTests`。
- 近期活跃工作涉及演进日志（`EVOLUTION.md`、`EvolutionLogView.swift`）以及新增的 AgentOutputPolicy（`Sources/TapgoCore/AgentOutputPolicy.swift`）及其测试（`AgentOutputPolicyTests.swift`）。
- 用户主项目路径为 `/Users/chenlaiyi/TapgoAICoding`，项目名为 Tapgo AICoding。
- 项目根目录存在 `AGENTS.md` 文件，首行为 `# Tapgo AICoding 开发约定`，作为开发约定的入口文档。
- 用户偏好助手逐步小量输出，而非一次性汇总多个步骤的结果
- 助手已通过分阶段执行命令并逐条独立报告的方式实现了增量输出
- 项目存在版本号多处同步的维护模式：`project.yml`、`Info.plist`、`EVOLUTION.md`、`git tag` 以及 `Sources/TapgoAICoding/Views/EvolutionLogView.swift` 的 `makeHistory()` 数组必须全部对齐
- `EvolutionLogView.swift` 的 `makeHistory()` 数组需要手动 prepend 新版本条目（注释明确：倒序、最新在最上），历史上容易遗漏导致 App 内“自进化日志”页面落后于实际版本
- 用户偏好简洁输出，希望流式响应中省略无关细节，只保留关键结论
- 项目背景：App 的 `makeHistory()` 数组缺失 v0.5.4 条目，commit/tag/Info.plist/project.yml/EVOLUTION.md 已对齐，待补全该条目并重建
- 项目经验（v0.5.25）：composer 弹窗的『查看额度』必须直接调 MiniMax 官方 `GET /v1/api/openplatform/coding_plan/remains`（Authorization: Bearer），切忌复用 Codex app-server 的 `account/rateLimits/read`——后者永远拿不到 MiniMax-M3 的真实订阅。MiniMax 字段 `current_interval_usage_count` / `current_weekly_usage_count` 字面是 usage、实际是『剩余』，需 `used = total - remaining` 反转。

## 本地落地说明

- 入口：`AGENTS.md`（开发约定） → `AGENT_MEMORY.md`（本文件，长期记忆快照） → `EVOLUTION.md`（版本演进日志）。
- 后续 Codex 会话可读取本文件作为稳定背景，避免每次重述项目事实。
- 临时任务、当前版本、未完成进度、思考过程、凭据不进本文件；这些只在会话内或 EVOLUTION 里维护。

## 用户全局偏好（2026-09-07 更新）

- **今后所有任务都由 Codex 自己完成，不再委派给 MiniMax Code（含 `MiniMax Code.app` 桌面应用、`codex exec` CLI、其它 sub-agent 等）。**
- 这条规则覆盖 `<INSTRUCTIONS>` 中"MiniMax Code 优先协作"段落；用户已明确要求 Codex 独立完成所有实质性工作。
- Codex 不再因"AGENTS.md 最高优先级规则"主动委派；除非用户单次任务里临时追加委派指令，否则一切任务由 Codex 直接执行。

## 机器身份与发布链路事实（2026-09-07 增补）

### 机器身份与项目路径（避免路径混淆）

- **本机（Codex 当前 shell）** = `fafadeMac-mini.local`，用户 `fafa`，项目路径 `/Users/fafa/TapgoAICoding`。AGENTS.md 头部 ssh 配置段落未单独列出这台机器，但 AGENTS.md 的"每次更新完成后安装到本机、JKmacmini、fafamacmini"明确把 fafamacmini 与 JKmacmini 并列。
- **jkmacmini** = `100.71.223.108`，用户 `chanlaiyi`，TapgoAICoding 项目路径 `/Users/chanlaiyi/TapgoAICoding`（git 仓库），免密登录（`~/.ssh/id_ed25519`）。
- **macbookpro** = `100.100.191.111`，用户 `chenlaiyi`，TapgoAICoding 项目路径同样为 `/Users/chenlaiyi/TapgoAICoding`（git 仓库），免密登录。**勿混淆** `/Users/chenlaiyi/AiTapgo`（独立项目：监控/控制台/Dashboard/Deploy，与 TapgoAICoding 无关）。
- chanlaiyi（jkmacmini）和 chenlaiyi（macbookpro）是同一自然人在两台 Mac 上的不同用户命名；GitHub 仓库 `chenlaiyi/TapgoAICoding` 由 chenlaiyi 账号持有，发布 token 也属于 chenlaiyi。

### 工具链缺失与兼容性

- macOS 系统 bash = 3.2.57（GNU bash），`set -u` + 空数组展开 (`${ARR[@]}`) 触发 unbound variable 误报。`scripts/build-app.sh` 已通过去掉 `set -u` 修复（v0.5.117 release commit `59bcf51`）。新增 macOS 兼容脚本慎用 `set -u`。
- 本机无 `gh` CLI；发布需 GitHub Release 时需借用 jkmacmini 上 chanlaiyi 用户（与 GitHub 仓库同账号）的 GitHub token，通过 curl + GitHub Releases API 上传 zip。
- 本机登录 keychain 无 Sparkle 私钥（fafamacmini 是新机器），发布签名靠从 jkmacmini 导出的 PEM 文件。

### Sparkle 签名链路

- 私钥位置：macOS login keychain item，service = `https://sparkle-project.org`，account = `com.tapgo.aicoding`，value = 32 字节 ed25519 seed 的 base64（无 PEM 包装）。`sign_update` / `generate_appcast` 都直接接受这种格式作为 `--ed-key-file`。
- keychain 里同名 service 还有一条 account = `ed25519` 的旧 item（2026-07-09 创建），是历史密钥，**当前项目已不用**——发布时必须用 `com.tapgo.aicoding` 这条。
- 非交互 SSH 无法解锁 macOS keychain（缺登录密码）→ 导出私钥必须在 GUI 终端跑 `security find-generic-password -s "https://sparkle-project.org" -a "com.tapgo.aicoding" -w`，再 scp 到本机。
- `scripts/create-github-release-artifacts.sh` 已支持 `SPARKLE_KEY_FILE` 环境变量；本机用文件路径，jkmacmini 默认从 keychain 读。

### 代码签名陷阱

- 本机无 Developer ID 证书，`scripts/build-app.sh` 自动走 ad-hoc 分支，但 Sparkle.framework 与主 App 二进制各自 ad-hoc Team ID 不一致时 dyld 报 `code signature ... not valid for use in process`。解决：安装前对所有组件 `codesign --remove-signature`，然后 `codesign --force --deep --sign -` 整体强制重新签名。
- jkmacmini 上 Developer ID 证书存在但 `codesign --timestamp` 报 `errSecInternalComponent`（keychain 同样未在 SSH session 解锁）；回退到 ad-hoc + 强制重新签名同样可行。

### Release 自动化

- 当前没有 GitHub Actions workflow；`git push origin v0.5.X` 不会自动创建 Release。
- 标准发布流程：本地 fast-forward → `SPARKLE_KEY_FILE=~/.tapgo/sparkle/ed25519.pem bash scripts/create-github-release-artifacts.sh`（自动 commit appcast.xml + push）→ 在 jkmacmini 上用 chanlaiyi 的 token 调 GitHub API 创建 draft release → upload zip → PATCH `draft=false` 发布。
- 安装到 jkmacmini 时无需手动 scp 二进制，直接 `cd /Users/chanlaiyi/TapgoAICoding && bash scripts/build-app.sh && codesign --force --deep --sign - /Applications/Tapgo\ AICoding.app` 即可（jkmacmini 已 fast-forward）。
