# v0.5.299

feat(evolution): 反馈漏斗接入看板

## 变更

- evolution-feedback-funnel.py 新增 snapshot 子命令：原子写 state/feedback_funnel.json（带 schemaVersion/generatedAt），--out - 可打印 stdout，--quiet 静默。
- evolve.sh 每轮收尾（含 --resume 路径）刷新该快照，失败只 WARN，不影响发布结果。
- TapgoCore.FeedbackFunnelSnapshot：宽容解析（缺字段不崩、缺文件返回 nil），口径始终以 Python 工具为真源，App 不重复实现计算。
- App 指标详情新增「反馈草稿 / 反馈转化 / 反馈等待」三张卡；手机端 H5 自进化卡片新增一行反馈漏斗摘要。
- 测试：漏斗回归扩到 36 项（快照落盘/载荷/stdout/quiet），Swift 指标 +4、PhoneRemote 快照 +3、H5 页面 +3。

反馈转化率与等待时长进入 App 指标详情与手机端卡片

## Next

EVO-021 操作者模型基线: 用真实 runner 跑 3 个任务，记录首份 model_eval_history 与成本（待操作者提供 runner）
