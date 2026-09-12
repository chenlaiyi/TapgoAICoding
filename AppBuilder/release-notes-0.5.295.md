# v0.5.295

feat(evolution): 三机界面自动断言

## 变更

- 新增 scripts/evolution-ui-assert.sh：不依赖 GUI 截图权限，用 App 自带 H5 服务断言——读 UserDefaults token、lsof 找 PID 监听端口（带重试）、/api/state 的 appVersion 必须等于期望版本、/r/<token> 骨架引用 app.js、assets/app.js 含 evolutionCard 标记、无 token 请求必须 403/404。
- 退出码分级 21 无进程/22 无 token/23 无端口/24 状态接口失败/25 版本不一致/26 骨架异常/27 资源缺标记/28 鉴权回归，--json 可机读。
- deploy-fleet.sh 远端安装重启后用 ssh 管道执行该断言（不依赖远端仓库版本），失败即部署失败；本地仅在 --restart-local 时断言，否则显式记 skipped；EVOLVE_SKIP_UI_ASSERT=1 可跳过。
- 真实反例：本机 /Applications 已是 0.5.294 但运行进程仍是 0.5.256，断言以 25 精确报出，这正是此前只回读版本/PID 抓不到的失效模式。
- 新增 23 项 UI 断言回归（真实 HTTP 桩服务）+ 新门禁 app-sources-parse-test.sh（swiftc -parse 覆盖 App target，本轮有一条被 ASCII 引号截断的字符串躲过全部单测直到 build 才炸，现提前到测试阶段）。

部署后断言 H5 界面可用且运行的是新版本

## Next

EVO-040 依赖路径探测: SDK 与 codex/gh 等路径自动探测，替换硬编码
