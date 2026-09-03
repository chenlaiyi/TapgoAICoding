# Tapgo AICoding 0.5.83

- 「贴近目标 IDE 风格」收尾 + 商标风险清理：
  - Swift 标识符重命名：`DSHTheme.brandBlueZCode` → `brandBlueAccent`、`warnZCode` → `warnAccent`、`errorZCode` → `errorAccent`，`DesktopZCodeDesignTests` → `DesktopDesignParityTests`（TestMain filter 关键字 `Desktop: design parity` 同步更新）。DSHTheme 与 RightWorkbenchView 仍使用这些 token，但 release body / EVOLUTION / commit msg 里的 "ZCode" 全部消失。
  - 文档与脚本中性化：`AppBuilder/release-notes-0.5.74..0.5.82.md` + `EVOLUTION.md` + `design-qa.md` + `artifacts/zcode-right-environment-audit/audit.md` + `artifacts/zcode-vs-tapgo-0.5.75/`（仅 `fidelity-report.{json,md}`）+ `scripts/zcode-fidelity-report.sh` → `scripts/fidelity-report.sh` 中所有面向用户的 "ZCode / zcode" 替换为「目标 IDE / reference」。GitHub release body 也用 `gh release edit` 同步。
  - commit msg 不动历史：v0.5.74..v0.5.82 的 commit msg 中残留的 "ZCode" 不 amend（避免 force-push 破坏 v0.5.80..v0.5.82 tag 链）；本 release notes 与 EVOLUTION 已说明这一 trade-off。
- 测试：2684 通过 / 14 失败（13 个预存在远程 SSH 集成 + 1 个 appcast 对齐；token 重命名未引入新失败）。
- 已知限制：release body / EVOLUTION / 代码注释 已全面中性化；commit msg 历史项需在未来的 `git filter-repo` 重写历史 + force-push 时一起处理（v0.5.84+ 视情）。
