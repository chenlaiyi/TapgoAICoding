# Tapgo AICoding 迁移到 DeepSeek Harness Desktop

本分支以 DeepSeek Harness 上游提交 `477b4f420553e8a52c2fbccc464d7561b239c443`（`0.1.7-rc.2`）替换原 SwiftUI / Codex app-server 源码。旧实现保留在 `main` 分支的 `a3cc04f722da132ab5e83feb78d3bca56757384c`，可回滚。

## 已验证

- 上游源码在 macOS arm64、Node 24.15.0、pnpm 11.7.0 下执行 `pnpm install --frozen-lockfile` 与 `pnpm run build` 成功。
- 本机已安装的官方 DSH Desktop 为 `0.1.7-rc.2`，Bundle ID 为 `com.deepseek.dsh`；真实界面可打开，已有 TapgoAICoding 工作区。
- 尚未替换 Tapgo App、daemon 或用户数据。

## 覆盖已安装 Tapgo App 前必须完成

1. 为派生版设置独立产品名、Bundle ID、URL scheme、图标、签名、公证与更新源。上游 Desktop 发布脚本绑定 DeepSeek 身份与下载设施，不可直接沿用。
2. 把 Tapgo 项目和对话数据映射到 DSH 已发布的会话格式。测试应使用隔离目录，不得直接写入现有 `~/.dsh` 或 Tapgo 用户数据。
3. 迁移并验证 Tapgo 专有能力：手机配对与遥控、公网中继、跨 Mac 部署，以及需要保留的 iOS 集成。
4. 构建可分发的 macOS App，完成隔离端到端任务验证，再将同一产物安装到三台 Mac，并分别回读版本、进程与真实界面状态。

上游源码采用 MIT 许可证；分发派生版时保留 `LICENSE` 和第三方声明。
