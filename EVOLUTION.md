# Evolution Log

> Append-only changelog for self-evolution iterations of **Tapgo AICoding**.
> Each entry corresponds to one git tag (one full build → test → commit → push cycle).
> Rollback to any version: `git checkout vX.Y.Z && ./scripts/build-app.sh`.

## Format

```
## vX.Y.Z — <one-line summary>
**Date**: YYYY-MM-DD
**Commit**: <short SHA>
**Tag**: vX.Y.Z
**Test status**: 110/110 green (or however many passed)
**Changed**:
- bullet
- bullet
**Why**: 1–2 sentences on the motivation / problem solved.
**Next**: what the following iteration plans to tackle (or "see state file").
```

## v0.3.0 — Initial shipped baseline (pre-evolution)
**Date**: 2026-08-25
**Commit**: 6422947
**Tag**: _none — pre-evolution baseline_
**Test status**: 110/110 green
**Changed**: (see git history: `git log dd13454..6422947`)
- 设置新增"账户"tab 退居 + 重新设计扫码登录界面
- 移除侧边栏"@ 插件"菜单项（保留输入框内插入技能入口）
- 管理员微信扫码登录门禁 + 输入排队/插话 + 用户消息操作条与头像昵称
**Why**: User-facing gating + UX polish before opening the self-evolution loop.
**Next**: v0.3.1 — evolution infrastructure scaffold (next entry).

appended
dirty
dirty
dirty
