# Tapgo AICoding 0.5.119

## 命令面板升级为中心浮层（视觉对齐 Codex 桌面端）

- ⌘K 唤起的命令面板从 macOS sheet 改为覆盖式中心浮层：560×460、`.regularMaterial` 背景模糊 + 阴影 + 圆角边框；点背景关闭；spring 弹性动画（响应 0.28s / 阻尼 0.85）；选中行缩放进场（scale 0.96 → 1）。
- 不再沿用 sheet 的边缘滑入与系统灰底，整体观感接近 Codex 桌面端的命令面板。

## Composer slash 命令补齐

- **`/clear`** — 清空当前会话的全部回合 + 取消 in-flight turn；thread 元数据（id/title/projectId/cwd/goal/固定）保留；下次发消息创建全新 harness 上下文（已随 v0.5.118 发布）。
- **`/model <query>`** — 模糊匹配 provider/model（displayName/modelID/providerName）；命中唯一即切换；0/多/未配置三态 alert 提示（已随 v0.5.118 发布）。
- **`/init`** — 在当前项目下创建引导 thread（标题 `/init · <项目> · AGENTS.md`），预填"扫描项目结构起草 AGENTS.md"提示；用户审阅后将内容写入项目根。
- **`/compact`** — 折叠当前会话历史：每回合的 assistant items 替换为单条 "(已 compact)" 提示；user messages、turn metadata（id/status/startedAt/completedAt/usage）和 thread 元数据保留；harness thread handle 重置使下次发消息从干净上下文开始。回合正在跑时返回 `busy`。

## 命令面板与 slash 菜单同步

- `/clear`、`/model`、`/init`、`/compact` 在 composer 内 `/` 唤起的 slash 菜单都有对应行；`/model` 占位补全到 `/model `，其他直接执行。
- 提示文本同步覆盖：`输入 /goal 后加目标文字，回车设置；输入 /clear 清空当前会话；输入 /model 后加模型名/显示名/provider::model 切换；输入 /init 打开起草 AGENTS.md 的会话；输入 /compact 折叠当前会话历史。`

测试覆盖 ComposerLocalCommand 30 个 case（v0.5.118 18 + /init 6 + /compact 6）+ SessionStore.compactActiveThread 单元；本机 fafamacmini 3104 passed / 12 failed（12 项失败均为 SSH 远程集成 + auth.json 环境性）。开发者签名有效；尚未完成 Apple 公证。
