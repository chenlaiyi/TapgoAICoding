# v0.5.282

feat(evolution): 多机协调锁

## 变更

- 新增远端 evolution-lock 原子互斥与持有者状态
- 冲突退出 9,显式 break 才能抢占,失败注入 S15

publish 前远端原子互斥,冲突显示持有者/时长,显式 break 才可抢占

## Next

EVO-028 发布 canary/灰度: 先只让一台客户端升级，观察后再全量 appcast
