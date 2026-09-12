# v0.5.275

feat(evolution): 模型级评测框架

## 变更

- 新增固定任务+参考解自检+可插拔 runner 的模型评测框架
- 真实模型运行需操作者显式提供 runner,自动流程只做参考解验证

3 个固定任务与参考解自检进入 benchmark,真实模型运行由操作者显式触发

## Next

EVO-020 回归用例固化: 把真实用户反馈转成最小可复现 fixture，进入 benchmark
