# Tapgo AICoding 0.5.221

## 源码同步 v0.5.220 的编译修复（SendableClosureCaptures）

- v0.5.220 期间修复 Swift 6 release build 的 `SendableClosureCaptures` 错误（search 完成态过去式逻辑里的闭包捕获），确保了发布构建可过。
- 该修复让 v0.5.220 发布产物可正常编译，但没有 commit 到源码。本版仅把该修复纳入源码 + bump 版本号，保持源码与发布产物一致。
- 没有用户可见行为变化（v0.5.220 已包含此修复的产物）。

## 测试

全量回归 3125 通过 + 三机安装回读。
