# v0.5.288

fix(evolution): 月度维护安装路径

## 变更

- 修复 install-evolution-maintenance.sh：echo 里 $LABEL 后紧跟全角括号被 bash 3.2 并入变量名，真实安装直接 unbound variable（--print 路径不受影响）。
- 安装器新增 EVOLVE_LAUNCH_AGENTS_DIR 与 --skip-launchctl，安装路径可在临时目录内验证，不再触碰真实 LaunchAgents。
- 维护回归扩到 47 项：新增真实安装路径覆盖（plist 落盘 + plutil 校验 + 输出断言），并做负向验证确认能抓回该 bug。
- 本机已注册 launchd 任务（每月 1 日 10:00，runs=0、RunAtLoad=false）并核验 program/path。

修复安装脚本 unbound variable 并让安装路径进入回归

## Next

EVO-033 发布失败续跑: `--resume` 从失败阶段继续（push 成功但 release 失败时不再整轮重来）
