# v0.5.271

feat(evolution): worktree clean-checkout 验证

## 变更

- 新增独立 worktree clean-checkout 构建验证,失败不推送
- 失败注入扩到 63 项并新增 P3 backlog

发布前从 tag 独立构建,确保提交自包含;失败不推送

## Next

EVO-016 真实 UI 回归自动化: 不重启当前会话也能验证进度条、停止、diff sheet 与指标看板
