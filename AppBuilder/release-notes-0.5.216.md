# Tapgo AICoding 0.5.216

## 搜索活动动词对齐 Codex 实机（按工具名派生）+ 历史测试修复

- Codex 截图实证 search 类活动动词按工具名派生：「查找设备页面验收窗口」（图 4，find）、「搜索 …」（search）、「查询 …」（query）。
- 此前 Tapgo 统一静态「查询」；现在按工具名关键词映射：search→搜索 / find|grep|glob→查找 / query→查询。
- 顺手修正 3 个历史遗留测试失败（v0.5.210 duration format 未更新测试、v0.5.211 image read 测试用 rollup title 而非 activity row label），回归从 3122/15 提升到 3125/12。

## 测试

全量回归 3125 通过 + 三机安装回读。
