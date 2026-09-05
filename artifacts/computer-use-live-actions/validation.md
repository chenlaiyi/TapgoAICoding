# 独立光标与真实操作验收

本轮版本：0.5.107。光标依据用户提供的参考图实现为原生 AppKit 绘制：浅色空心圆角箭头、淡青色柔光、透明鼠标穿透窗口，无标签。cursor-preview.png 为实际绘制代码的离屏预览。

## 实现与根因

- AXPress 并非所有控件均支持。输入框遇到明确的 actionUnsupported/notImplemented 时，按当前已验证元素的可见位置定向点击；禁用控件、不可见控件、失效观察仍拒绝操作。cannotComplete 不自动重试，避免动作重复执行。
- 原始 CGEvent 只设置屏幕位置不能提供有效的窗口内命中位置。使用 NSEvent 生成窗口信息，补齐窗口 ID 和局部坐标后 postToPid。实际 Fixture 事件日志由无效局部坐标变为目标控件坐标。
- 定向鼠标使用可选的 CGEventSetWindowLocation 系统符号，属于私有接口，未来 macOS 兼容性需要实测。符号不存在时明确返回错误，保留 AX 操作；不声称所有 OS/应用都已支持。
- 滚动通过 WindowServer 注入目标位置，并在发出前确认目标应用仍在前台。键盘焦点仍受 macOS 管理。这是独立的操作光标，不是第二套操作系统桌面。
- one-shot Helper 创建穿透光标窗口，操作后关闭；stdio 桥接和主 App 不创建多余光标窗口。未修改系统权限。

## 验证方法

- scripts/run-computer-use-live-actions.sh：编译临时原生测试 App，使用正式 Helper 的 MCP stdio/Launch Services 链路，验证输入框焦点迁移、中文键盘输入、语义按钮、坐标按钮、真实拖动选字、光标窗口层级、关闭清理与硬件指针位置。
- scripts/computer-use-smoke.py：原有截图、跨进程观察、失效编号拒绝、延迟粘贴、滚动实际位置、前置小对话框回归。
- Chrome 临时本地测试页：坐标点击输入框并输入中文、按钮更新 DOM、无 AX 元素的 Canvas 点击均已读回结果，硬件指针保持原位；测试后关闭该临时标签。
- TapgoTests 全量回归跳过外部远程 Harness 集成；最终通过数量见本轮交付报告。

设计参考是用户所附图片。API 依据：[Apple AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction)、[Apple CGEventField](https://developer.apple.com/documentation/coregraphics/cgeventfield)。窗口位置调查参考 [background-click 技术说明](https://github.com/Lakr233/bgclick-rev-skill/blob/main/bgclick-rev-skill.md)，实现已通过自身测试窗口和 Chrome 实测，不以资料描述代替验证。

本轮不创建公开 Release、不更新 Sparkle appcast；公开版本与三机直接安装分别报告。Developer ID 签名不等于 Apple 公证。


## 0.5.107 最终验收

- 本地逻辑回归：TAPGO_SKIP_REMOTE_TESTS=1 TAPGO_EXPECTED_VERSION=0.5.107 swift run TapgoTests，2874 通过、0 失败。跳过需外部 Harness 的集成项，不调用模型供应商。首次未设跳过项遇到默认虚拟 SSH 地址超时；版本断言使用仓库提供的待发布版本变量后全通过。
- 三机真实操作：JKMac mini 41 项、MacBook Pro 40 项、fafamacmini 40 项；数量差异来自启动就绪检查。三机截图/失效观察/延迟粘贴/滚动/小对话框各 62 项通过。本机首次粘贴失败，带错误回执重跑通过；保留剪贴板并发保护。
- 组合截图先完成捕获，再重新生成 AX 编号与指纹，MacBook Pro 原有标题栏瞬态导致的 token 失败已回归通过。
- 定时任务 UI：关闭按钮、Esc、嵌套编辑 Esc 通过；真实列表展示周一至周五 07:33 任务。
- 原句“周一到周五每天早上7点33打开zoom app”已在安装版完成本地创建，持久化回执含 Asia/Shanghai、下次周一 07:33、任务 ID；重复输入返回已有任务，文件数不增加。手动“立即运行”后 Zoom 进程启动，任务历史为 success，原下一次计划保持。
- 创建路径不启动模型。MCP 创建、查询、取消、参数校验、幂等、旧数据兼容由实际核心代码单测覆盖；后台自动到点仍要求 Tapgo 开启且 Mac 唤醒，不承诺自动唤醒。
- 同一份 Developer ID 签名 App 已直接安装并重启三机，App/稳定 Helper 均为 0.5.107，两项 TCC 均为 true。
- App SHA-256：a69b40eb42fd5a85a9f184a5792d03fd7561cce9360d96d879056cb4e45d9324。
- Helper SHA-256：89e908444c3a6975f338e8b564b4324700a367350b993378ceba3e6dbc2721e5。
- 安装 ZIP SHA-256：d6c564c580c99748631e88879334394ccd56ac5ff482d58af3cac7e6a10381a1。
- 用户并行对话另建同时间 launchd 任务，检测到后保留原配置并询问去重选择；没有擅自改写系统任务。
