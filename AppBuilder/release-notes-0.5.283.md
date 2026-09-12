# v0.5.283

feat(evolution): 发布 canary/灰度

## 变更

- 支持 draft+单机 canary+promote 灰度发布
- deploy-fleet --only/--exclude 与 S16/S17 失败注入

draft release 先单机验证,通过后才发布 appcast 并部署其余机器

## Next

EVO-029 回滚演练: 定期从上一 tag 回滚并跑 health-check，验证可恢复性
