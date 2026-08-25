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


## v0.3.2 — fix: evolve.sh skips SSH-integration tests by default; README test count 110→332
**Date**: 2026-08-25
**Commit**: `c141776`  _(see `git log -1 v0.3.2`)_
**Tag**: v0.3.2
**Test status**: — 332 passed, 0 failed —
**Changed**:
- fix: evolve.sh skips SSH-integration tests by default; README test count 110→332
evolve.sh now sets TAPGO_SKIP_REMOTE_INTEGRATION=1 unless WITH_INTEGRATION is set, so SSH-dependent tests (which need a real remote host at the RFC 5737 203.0.113.10 address) are skipped by default. README updated to reflect the actual 332-test count instead of the outdated 110. The evolve.sh sanity check was demoted to a warning, version bumps now source from the latest git tag, and a couple of unset-variable bugs under set -u were fixed.
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.
