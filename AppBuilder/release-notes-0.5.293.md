# v0.5.293

feat(evolution): 远端锁 TTL

## 变更

- evolution-remote-lock.sh 重构：抽 make_lock_commit/push_lock_lease/report_held，新增 --ttl（默认 EVOLVE_LOCK_TTL_SECONDS=14400）。
- acquire 遇到 started 超过 TTL 的锁会打印 REMOTE LOCK STALE RECLAIMED 并自动接管；元数据读不出 started（例如手推 ref）时只报 HELD 且明确 auto-reclaim disabled，绝不自动接管。
- 新增 reclaim 子命令：force-with-lease 覆盖当前锁，供 evolve.sh --break-remote-lock 使用（不再先删 ref 再抢，消除竞态窗口）。
- status 增加 ttlSeconds/ageSeconds/remainingSeconds/stale 输出；--ttl 非整数直接拒绝（exit 2）。
- 回归：锁测试 4→15 项，失败注入 135→138 项（S29 端到端陈旧锁自动回收后完成发布）；真实 GitHub 远端已实测 stale→自动回收→release→FREE。

陈旧远端锁自动回收，reclaim 显式抢占

## Next

EVO-038 反馈闭环转化率: drafts → check → backlog → 版本的转化率与等待时长
