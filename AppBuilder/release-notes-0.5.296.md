# v0.5.296

feat(evolution): 依赖路径探测

## 变更

- 新增 scripts/evolution-deps.sh：evo_detect_sdk/evo_detect_codex/evo_require_tool/evo_deps_report，只定义函数、source 无副作用。
- SDK 解析顺序：TAPGO_SDK 显式 → 偏好 EVOLVE_SDK_PREFERRED（默认 macosx26.5，装了就用）→ 本机最新已装 SDK → xcrun 默认；走非偏好分支打 WARNING，全部失败才报错并列出已装 SDK。
- codex 解析顺序：EVOLVE_CODEX_BIN → PATH → /opt/homebrew/bin → /usr/local/bin → ~/.local/bin；找不到时明确报错。
- 13 处 SDK 硬编码与 3 处 codex 硬编码收敛到该模块：launchd plist 改用 __CODEX_BIN__ 占位符由安装器替换，init-tapgo 复用 evo_detect_codex，反馈注册表 5 条检查去掉 -sdk 硬编码，预检新增 codex 解析行。
- 新增 30 项 deps 回归（含静态守卫：无残留硬编码、可覆盖 ROOT 的脚本必须从 SCRIPT_DIR 加载模块）。

SDK 与 codex 收敛到单点真源，升级机器不再硬失败

## Next

EVO-041 自进化成本归属: App 把当前会话的 token/成本传给 evolve.sh（`EVOLVE_RUN_TOKENS`/`EVOLVE_RUN_COST_USD`），让单轮成本指标有真实数据
