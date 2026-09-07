# Tapgo AICoding 0.5.120

## Composer slash 命令补齐

- **`/review [scope]`** — 在当前项目下创建引导 thread 预填"审阅 diff"提示。scope 可省略或以下值：
  - `working`（默认 / 留空）→ `git diff HEAD` 工作树相对 HEAD 的未提交改动
  - `staged` → `git diff --staged` 已 add 但未 commit
  - `main` → `git diff origin/main...HEAD` 当前分支与 main 的差异
  - 任意 git ref → `git diff <ref>`
- prompt 引导 Codex 先 `--stat` 看全貌，再看完整 patch，再 cat SPEC/AGENTS 等约定，最后给风险 + 设计 + 测试 + 文档同步四项审查报告 + 优先级排序的"建议改动"清单。

测试覆盖 ComposerLocalCommand 6 个新 case（bare 视为 working scope，scope 名称 trimming，prefix/suffix 边界）；本机 fafamacmini 3110 passed / 12 failed（12 项失败均为 SSH 远程集成 + auth.json 环境性，与改动无关）。开发者签名有效；尚未完成 Apple 公证。
