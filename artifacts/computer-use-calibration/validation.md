# Computer Use 校准验收

2026-09-05，第一轮候选版本 0.5.102。

依据：当前 Codex `cua_repl` 实际返回的 Target API/Workflow，以及 [OpenAI Computer use 文档](https://developers.openai.com/api/docs/guides/tools-computer-use)。

- 新增 get_ax_state、get_screenshot、get_ax_state_and_screenshot；支持 disableDiffing，保留旧接口。
- 常驻桥接保存 120 秒内观察指纹；单次 Helper 核验 PID、启动时间、窗口和 AX 树及控件位置后操作同批元素对象。动作、截图、错误观察和桥接重启使旧编号失效。
- 前方小窗口优先于后方大窗口；滚动指定无效目标时返回错误；剪贴板并发修改不被恢复过程覆盖。
- Core 全量回归：2788 通过，0 失败（TAPGO_SKIP_REMOTE_INTEGRATION=1；远程 Harness 集成未运行）。
- 签名 App + Helper 构建成功，版本一致；真实 Launch Services 单次 Helper 链路：42 项检查通过。
- 真实测试覆盖 AX-only、值写入及回读、点击结果、重复编号拦截、上下文选词、粘贴结果、窗口截图、截图后编号失效、diff 重置、组合观察及前方小对话框。
- 测试窗口最初缺少标准编辑菜单，Codex 对照也无法粘贴；修正测试窗口后上述检查通过。

可重现脚本：scripts/computer-use-fixture.swift、scripts/computer-use-smoke.py。仅操作 /tmp/Tapgo CU Fixture.app 的合成数据，不访问用户文件或网络，不更改系统权限。

尚未提供：Codex 持久 JavaScript cua 运行时、浏览器 tab/DOM、独立浏览器会话。不能宣称全能力 1:1。签名与系统 TCC 授权分开验收；此阶段尚未公开发布。

## 第二轮 0.5.103

- 粘贴改为 NSPasteboardItemDataProvider 延迟提供数据；最多等待 2 秒读取，随后恢复原剪贴板；并发复制时保留新内容。数据读取不等于最终 UI 完成，仍须目标值回读。
- 滚动改为目标区域尺寸的 90% 每页，支持大于 0、不超过 10 的小数页数，保留旧版 dy 行滚动。
- 全量 Core：2795 passed / 0 failed；签名 App/Helper 构建与 codesign --verify --deep --strict 通过。
- 真实 Launch Services Helper：62 checks passed。新增 450ms 延迟粘贴回读、第二个独立桥接改变文本后首个桥接旧编号被拒绝（且按钮效果不变）、0.5 页滚动及滚动条位置回读。
- 本次 GitHub 源码合并与三机 App 更新不代表已创建公开 GitHub Release 或更新 Sparkle appcast。
