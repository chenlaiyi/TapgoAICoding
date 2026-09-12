# v0.5.313

test(evolution): H5 渲染执行级测试

## 变更

- 新增 scripts/tests/evolution-h5-render.mjs（EVO-054）：最小 DOM stub 里加载真实 app.js，用真实 fetch 回调驱动 refresh() → renderEvolution()，断言渲染进 DOM 的文案与 hidden 状态；40 项断言覆盖完整渲染、evolution 消失后恢复、漏斗/指标为空边界、CSS hidden 不变量。
- 变异验证证明测试有牙：把漏斗改回修复前扁平键 → 5 项失败（含用户可见症状「漏斗行可见」）；可见性边界 > 0 写成 >= 0 → 1 项失败；还原后 40/40 绿。甄别掉一个假阳性——evolution 为 null 时子行保留旧 hidden 标志，但子行在已隐藏卡片子树内且无 author display 覆盖，用户不可见，故断言用户可见语义而非改生产代码迎合测试。
- 共享 fixture evolution/h5-fixtures/evolution-state.json：Swift 契约测试（EVO-053）增加 4 项断言，校验它仍能解码为 EvolutionStatus 且覆盖 app.js 读取的每个顶层键，避免 Node 侧拿服务器给不出的形状自说自话。
- 接入 scripts/tests/run-all.sh 单绿门禁（需要 node，缺失时明确失败而不是静默跳过）。

手机端自进化卡片渲染纳入秒级门禁

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
