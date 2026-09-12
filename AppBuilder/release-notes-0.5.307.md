# v0.5.307

test(evolution): 维护任务真实触发与告警链路

## 变更

- 真实触发：launchd 任务此前从未执行过（runs=0），用 launchctl kickstart 跑了一次真实月度维护——runs=1、last exit code=0、状态历史新增 drill=v0.5.306 passed + archive=passed（7s），launchd 日志完整落盘。
- 告警链路补测：维护回归新增默认 osascript 分支（用假 osascript 记录 argv），断言 display notification 的标题与原因内容（含中文与路径）转义正确——此前只有 EVOLVE_MAINTENANCE_NOTIFY 被覆盖。
- 过程中修掉测试自身缺陷：假 osascript 曾写成文件而非目录（PATH 注入失效，那次失败用例发了真实通知）、chmod 作用在目录上。
- 实发验证：用真实 osascript 发出一条测试通知（exit 0），确认通知中心链路在本机可用。
- 维护测试 47→51 项；README 补「手动触发一次维护并验证三处证据」的操作步骤。

launchd 真跑一次 + osascript 分支补回归

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
