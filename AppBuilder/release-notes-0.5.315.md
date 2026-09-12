# v0.5.315

fix(quota): DeepSeek V4.1 改名后仍显示余额

## 变更

- 新增 TapgoQuotaChannel 与 Provider.quotaChannel：内置供应商稳定映射到 MiniMax / GLM / DeepSeek 官方额度通道，自定义 Provider 为 nil。
- SessionStore、ModelUsagePopover、SidebarView 统一按 provider.quotaChannel 查询、显示来源与空态，不再用 TapgoModel(rawValue: apiModel) 判定额度通道。
- 回归：DeepSeek 模型 apiModel 改名 deepseek-v4.1-flash 后，builtInKind 与 quotaChannel 均保持 DeepSeek；真实余额接口同轮验证 HTTP 200 返回 ¥13.85 CNY。
- makeHistory 同步 prepend v0.5.315，修复首轮四方一致性校验暴露的日志同步缺失。

额度通道改按内置供应商身份路由

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
