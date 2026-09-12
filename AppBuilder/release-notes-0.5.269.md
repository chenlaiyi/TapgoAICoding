# v0.5.269

feat(evolution): iOS 版本序列分离

## 变更

- iOS 历史移入独立日志,主日志留指针
- 记录校验按 scope 分流并补 iOS 回归

iOS 1.0.x 独立归档,Mac 0.x 校验不再受跨序列重复干扰

## Next

EVO-014 旧日志归档: 把 v0.5.5 之前与 iOS 历史移入 `evolution/archive/`，主日志保持可读
