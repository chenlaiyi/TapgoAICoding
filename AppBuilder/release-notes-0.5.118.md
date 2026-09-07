# Tapgo AICoding 0.5.118

## Composer slash 命令（对齐 Codex 桌面端）

- **`/clear`** — 清空当前会话的全部回合记录，同时取消正在跑的回合；线程元数据（id / title / projectId / cwd / goal / 固定状态）保留，下次发消息会创建全新的 harness 上下文。
- **`/model <查询>`** — 模糊匹配 provider / model 并切换下一个新会话的模型。查询可填显示名片段（如 `MiniMax M3`）、apiModel（如 `MiniMax-M3`）或精确 ID（如 `builtin:minimax::MiniMax-M3`）。命中 0 / 多 / 已注册但缺 key 三种情况都会弹 alert 提示如何消歧。已在跑的回合沿用旧模型（与 Codex 桌面端语义一致）。

测试覆盖 ComposerLocalCommand 解析（新增 11 个 case）+ SessionStore.selectModel 模糊匹配；SSH 远程集成与 auth.json 环境性失败仍稳定与 v0.5.117 一致。开发者签名有效；尚未完成 Apple 公证。
