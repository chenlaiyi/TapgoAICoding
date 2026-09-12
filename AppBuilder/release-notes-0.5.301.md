# v0.5.301

feat(evolution): UI 快照基线比对

## 变更

- 新增 scripts/evolution-ui-diff.py：字节相同直接通过；否则用 Pillow 逐像素比较，按「通道差 > 8 的像素占比 ≤ 0.1%」判定，输出差异 bbox/最大通道差，--json 可机读，--diff-out 落差异图。
- 缺 Pillow 且两份快照字节不同时以 exit 3 明确报告无法比对，不假装通过（Pillow 是用户级安装，不能假设每台机器都有）。
- 新增基线 evolution/ui-baseline/evolution-ui.png：实测两次渲染逐字节一致（1800x1960, 199893B），像素门禁在同机稳定。
- evolution-ui-snapshot-test.sh 升级：渲染后与基线比对并加两个负向对照（sips 改尺寸、200x20 条带局部改动），--update-baseline 刷新基线。
- 测试从 3 项扩到 9 项；benchmark 的 machinery-executable 追加基线文件断言。

离屏渲染与基线做像素门禁，布局回归可拦截

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
