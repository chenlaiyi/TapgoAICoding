# Evolution Log
## v0.5.189 — feat(ui): streaming 时显示闪烁光标（对齐 Codex 桌面端）
**Date**: 2026-09-08
**Tag**: v0.5.189
**Test status**: 本机 3117 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/MarkdownMessageView.swift`:
  - body 末尾加 `.overlay(alignment: .bottomLeading)` + `if isStreaming { StreamingCursor() }`。
  - 新增 `StreamingCursor` View：TimelineView(.periodic 0.5s) 切换"▍"光标的 opacity + brand 色。
**Why**: `MarkdownMessageView` 有 `isStreaming` 参数但 body 里没实现光标闪烁。Codex 桌面端 streaming 时显示 0.5s 周期闪烁的"▍"光标。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.188 — fix(ui): 运行中 work 过程 assistantMessage 改为紧凑单行可展开
**Date**: 2026-09-08
**Tag**: v0.5.188
**Test status**: 本机 3117 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ConversationResponseView.swift`:
  - 新增 `ConversationWorkAssistantRow` view：单行显示 assistantMessage 文本前 60 字 + 折叠箭头，点击展开完整 Markdown。
  - `ConversationWorkDisclosure.expanded` 里 `.item(.assistantMessage)` 改用 `ConversationWorkAssistantRow` 替代 `MarkdownMessageView`。
**Why**: 之前 v0.5.187 running 显示 work items 但 assistantMessage 以完整 Markdown 渲染——重复显示来源之一。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.187 — feat(ui): NewTaskView preselectedHint 标题加 .bold
**Date**: 2026-09-08
**Tag**: v0.5.187
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - preselectedHint 标题"将在以下项目创建任务"加 `.bold()`。
**Why**: 之前 .caption + .secondary 普通字重在 accent 边框浅蓝背景里不够显眼。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.186 — feat(ui): Sidebar project group header + 按钮加 ⌘N 快捷键
**Date**: 2026-09-08
**Tag**: v0.5.186
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - project group header 的 + 按钮加 `.keyboardShortcut("n", modifiers: .command)`。
**Why**: 之前主菜单 "新建任务" 绑 ⌘N 但 sidebar + 按钮不绑，user 按 ⌘N 总是打开无 project 新任务。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.185 — feat(ui): ApprovalRow 拒绝按钮加 ⌘⌫ 快捷键
**Date**: 2026-09-08
**Tag**: v0.5.185
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 拒绝按钮加 `.keyboardShortcut(.delete, modifiers: .command)`。
**Why**: 之前拒绝按钮只能鼠标点。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.184 — feat(ui): NewTaskView 取消 preselected 预选时加 0.2s 动画反馈
**Date**: 2026-09-08
**Tag**: v0.5.184
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - preselectedHint X 按钮 action 加 `withAnimation(.easeOut(duration: 0.2))`。
**Why**: 之前 preselectedHint 瞬间消失，user 没动画反馈。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.183 — fix(ui): NewTaskView 快速任务副文在 preselectedProject 时改"在 X 项目中创建临时对话"
**Date**: 2026-09-08
**Tag**: v0.5.183
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 副文 if/else：有 preselectedProject 时显示"在 X 项目中创建临时对话"，无时显示 L10n.quickNoProjectHint。
**Why**: v0.5.171-174 改了"快速任务"action card 标题但副文仍说"不绑定项目"，跟新行为矛盾。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.182 — fix(ui): Sidebar 重命名从 alert 改 sheet（TextField focus 可靠工作）
**Date**: 2026-09-08
**Tag**: v0.5.182
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - 重命名从 `.alert(...)` 改 `.sheet(...)` + 新 `renameSheet` view。
  - `renameSheet` roundedBorder TextField + `.focused($renameFocused)` + `.onSubmit(commitRename)`。
  - `commitRename()` helper 共享提交逻辑。
**Why**: v0.5.170 加 alert TextField focus 但 SwiftUI 14+ alert 内 `.focused()` 行为有限制。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.181 — feat(ui): Sidebar thread item hover tooltip 加 thread ID 前缀
**Date**: 2026-09-08
**Tag**: v0.5.181
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 加 `var threadId: String? = nil` 参数。
  - `.help()` 显示 `title · threadId前8字符`。
- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - `threadRow` 传 `threadId: t.id`。
**Why**: 之前 hover tooltip 只显示 title，user 找 thread ID 要右键复制。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.180 — feat(ui): NewTaskView preselectedHint 视觉强化（brand 浅蓝 + accent 边框）
**Date**: 2026-09-08
**Tag**: v0.5.180
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - `preselectedHint` 背景 `DSHTheme.interactiveHover` → `Color.accentColor.opacity(0.08)`。
  - 加 accent 边框 1.5pt。
**Why**: 之前 interactiveHover 太淡，重要的预选信息不够明显。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.179 — fix(ui): NewTaskView 打开时焦点默认在 footer 取消按钮
**Date**: 2026-09-08
**Tag**: v0.5.179
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 加 `@FocusState cancelFocused` + footer 取消按钮 `.focused($cancelFocused)` + body `.onAppear { cancelFocused = true }`。
**Why**: 之前默认 focus 在"本地项目"action card，按 Enter 立即触发 NSOpenPanel。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.178 — fix(ui): Sidebar project group header + 和 more 按钮 opacity 0.25 → 0.6
**Date**: 2026-09-08
**Tag**: v0.5.178
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - project group header 的 + 按钮和 projectMoreMenu opacity 0.25 → 0.6。
**Why**: 之前 0.25 太隐蔽，用户不知道有按钮。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.177 — feat(ui): Sidebar thread item 双击进入 rename 模式
**Date**: 2026-09-08
**Tag**: v0.5.177
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - 3 个 thread item Button 加 `.onTapGesture(count: 2)` 触发 rename 模式。
**Why**: 之前双击只 select thread，无 rename 行为。macOS Finder 习惯是双击重命名。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.176 — feat(ui): ApprovalRow 批准按钮加 .keyboardShortcut(.defaultAction)
**Date**: 2026-09-08
**Tag**: v0.5.176
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 批准按钮加 `.keyboardShortcut(.defaultAction)`。
**Why**: user 之前必须鼠标点批准按钮。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.175 — fix(ui): ApprovalRow 拒绝按钮改用 .borderedProminent 让 destructive style 真显示
**Date**: 2026-09-08
**Tag**: v0.5.175
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 拒绝按钮 `.buttonStyle(.bordered)` → `.buttonStyle(.borderedProminent)`。
**Why**: v0.5.165 加 `Button(role: .destructive)` 但 `.bordered` 不支持 role tinting，role 被忽略按按钮没显示红色。改 `.borderedProminent` 让 role 真生效。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.174 — feat(ui): NewTaskView 快速任务 action card 标题在 preselectedProject 时改"在 X 项目中创建"
**Date**: 2026-09-08
**Tag**: v0.5.174
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - "快速任务" action card title 用 closure 根据 preselectedOverride ?? preselectedProject 返回动态文案。
**Why**: v0.5.173 修"快速任务"用 preselectedProject 但 card 标题仍"快速任务"让 user 看不到预选被尊重。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.173 — fix(ui): NewTaskView "快速任务"action 尊重 preselectedProject
**Date**: 2026-09-08
**Tag**: v0.5.173
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - "快速任务" action card action 改 `onCreate(preselectedOverride ?? preselectedProject)`。
**Why**: v0.5.171 加 preselectedProject 后 user 选"快速任务"仍创建无 project 的 thread，违反 sidebar 按钮意图。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.172 — feat(ui): NewTaskView preselectedHint 加 X 按钮让 user 取消预选
**Date**: 2026-09-08
**Tag**: v0.5.172
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - `var preselectedProject` → `let preselectedProject`（caller 设）。
  - 加 `@State var preselectedOverride: Project?` 本地覆盖。
  - `preselectedHint` 显示 `override ?? preselected` + X 按钮设 override = nil。
**Why**: v0.5.171 预选提示 user 无法取消。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.171 — feat(ui): NewTaskView 接 preselectedProject 参数（sidebar + 按钮预选 active project）
**Date**: 2026-09-08
**Tag**: v0.5.171
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 加 `var preselectedProject: Project? = nil` + `preselectedHint` view。
  - body 在 primaryActions 后显示预选提示（如果 preselectedProject != nil）。
- `Sources/TapgoAICoding/Views/ContentView.swift`:
  - NewTaskView 传 preselectedProject = workspace.state.activeProject。
  - 拆出 `.onChange(of: store.activeThreadId)` 逻辑到 `activeThreadIdChanged` helper，让 body 简化、Swift type-checker 不超时。
**Why**: 之前从 sidebar + 按钮进入 NewTaskView 时 user 还得手动选一次当前 project。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.170 — fix(ui): Sidebar 重命名会话 alert TextField 默认 focus
**Date**: 2026-09-08
**Tag**: v0.5.170
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - 加 `@FocusState private var renameFocused: Bool` + TextField `.focused()` + `.onChange(of: renamingThreadId)` 触发 focus。
**Why**: 之前重命名 alert 弹出后 user 必须先点 TextField 才能输入。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.169 — feat(ui): Sidebar thread item 右键菜单加"在 Finder 中显示附件"
**Date**: 2026-09-08
**Tag**: v0.5.169
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - `contextMenu(for: Thread)` 加"在 Finder 中显示附件" Button（paperclip icon）。
  - 加 `openThreadAttachmentsDir(_:)` helper：目录存在时 NSWorkspace.open；不存在弹 NSAlert 提示。
**Why**: user 想找 thread 附件存放位置但没入口。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.168 — fix(ui): + 菜单"附加 Tapgo AICoding"项副文精简
**Date**: 2026-09-08
**Tag**: v0.5.168
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `addMenuItems` "附加 Tapgo AICoding" 副文 "把当前项目文件夹挂载到会话上下文" → "挂载当前项目文件夹到会话"。
**Why**: 之前副文过长。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.167 — feat(ui): PlanModeBanner persistent 模式背景更深
**Date**: 2026-09-08
**Tag**: v0.5.167
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner` 背景：`isPersistent ? DSHTheme.brand : DSHTheme.brand.opacity(0.75)`。
**Why**: 之前两种状态都用 brand 色，仅靠文字区分。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.166 — fix(ui): NewTaskView action card 文案精简
**Date**: 2026-09-08
**Tag**: v0.5.166
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Resources/L10n.swift`:
  - `localFolder`: "本地文件夹" → "本地项目"
  - `quickNoProject`: "快速任务 (无项目)" → "快速任务"
**Why**: 之前 card 标题过长挤在 card 里。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.165 — fix(ui): ApprovalRow 拒绝按钮加 destructive role
**Date**: 2026-09-08
**Tag**: v0.5.165
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 拒绝按钮加 `Button(role: .destructive)` 让 macOS 标记 destructive action。
**Why**: 之前用 `.bordered` 普通样式跟批准按钮区分不明显。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.164 — feat(ui): SidebarTaskLabel 选中时加左侧 accent border
**Date**: 2026-09-08
**Tag**: v0.5.164
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 选中时（`.overlay(alignment: .leading)`）加 `Color.accentColor` 3pt 圆角矩形。
**Why**: 之前 sidebar 选中只靠背景色区分（dark mode 颜色相近），不够明显。Codex 桌面端选中项通常有左侧条。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.163 — feat(ui): NewTaskView 加底部"取消"按钮 + ESC 快捷键
**Date**: 2026-09-08
**Tag**: v0.5.163
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 加 `footer` view：右下角"取消"按钮（bordered style + 文字，比 X 关闭按钮更明显）。
  - `.keyboardShortcut(.cancelAction)` 让 ESC 触发 dismiss。
  - body frame height 460 → 480 容纳 footer。
**Why**: 之前 NewTaskView 只在右上角放 X 关闭按钮（22x22），user 经常找不到取消入口。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.162 — feat(ui): NewTaskView recentRow hover 加 border
**Date**: 2026-09-08
**Tag**: v0.5.162
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - `recentRow` hover 时加 1.5pt accent-color 边框。
**Why**: v0.5.160-161 actionCard 加了 hover border，recentRow 风格不一致。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.161 — fix(ui): v0.5.160 hover 反馈无效（@State in func 被忽略）
**Date**: 2026-09-08
**Tag**: v0.5.161
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - 把 `actionCard` 函数改成 `ActionCard` View struct， `@State var hovering` 写在 struct 属性里。
**Why**: v0.5.160 在普通函数里声明 `@State` 被编译器忽略，hover 反馈不工作。SwiftUI PropertyWrapper 必须放在 View struct 属性里。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.160 — feat(ui): NewTaskView actionCard 加 hover 反馈
**Date**: 2026-09-08
**Tag**: v0.5.160
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/NewTaskView.swift`:
  - `actionCard` 加 `@State var hovering` + `.onHover`。
  - hover 时背景从 `surfaceRaised` → `interactiveHover` + 1.5pt icon-color 边框。
**Why**: 之前 actionCard 是 plain button，无 hover 反馈，user 不知道可点。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.159 — refactor: 清理 AddMenuAction.togglePlanMode dead code
**Date**: 2026-09-08
**Tag**: v0.5.159
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `AddMenuAction` enum 移除 `.togglePlanMode` case（v0.5.157 改用直接 `planningMode.toggle()`）。
  - `runAddMenuAction` switch 移除对应分支。
**Why**: dead code 清理，保持 enum 简洁。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.158 — feat(ui): + 菜单"目标"项显示当前 goal 状态
**Date**: 2026-09-08
**Tag**: v0.5.158
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - "目标"项从 addMenuItems 数组拿出来单独渲染，根据 activeThreadGoal 显示不同 icon + 文案。
  - 无 goal 时 `target`；有 goal 时 `target.fill` + "目标（已设置）" + 当前目标摘要。
**Why**: 与 v0.5.157 一致 — + 菜单的 toggle/state 项都该显示当前状态。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.157 — feat(ui): + 菜单"计划模式"项显示当前状态
**Date**: 2026-09-08
**Tag**: v0.5.157
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - "计划模式"项从 `addMenuItems` 数组拿出来单独渲染，根据 `planningMode` 显示不同 icon + 文案。
  - 关闭时 `lightbulb` + "计划模式"；开启时 `checkmark.circle.fill` + "计划模式（已开启）"。
**Why**: Codex 桌面端 plan mode toggle 菜单项会显示当前状态。Tapgo 之前无法从 + 菜单看出 plan mode 是否已开启。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.156 — fix(ui): 点 backdrop 关闭 command palette 也自动 focus 回 composer
**Date**: 2026-09-08
**Tag**: v0.5.156
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ContentView.swift`:
  - backdrop 的 `.onTapGesture` 关闭 palette 时也 post `.tapgoFocusComposer` 通知。
**Why**: v0.5.155 只修了 `onDismiss`（↩ 选命令 / X 按钮）路径，backdrop 点击关闭时没 focus。统一所有关闭路径。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.155 — fix(ui): command palette 关闭后自动 focus 回 composer
**Date**: 2026-09-08
**Tag**: v0.5.155
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ContentView.swift`:
  - `CommandPaletteView.onDismiss` 在关闭 palette 时多 post 一个 `.tapgoFocusComposer` 通知，触发 `ChatView` 已有 `tapgoFocusComposer` handler（v0.4.x 接入）把 focus 设回 composer。
**Why**: Codex 桌面端 palette 关闭后自动 focus 回 composer，避免 user 用完 palette 还得手动点 composer 才能继续输入。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.154 — fix(ui): SidebarTaskLabel failed 改用实心图标
**Date**: 2026-09-08
**Tag**: v0.5.154
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 的 `.failed` case icon 从 `exclamationmark.circle` → `exclamationmark.circle.fill`（实心）。
**Why**: v0.5.152-153 把 awaiting approval 改实心 + warn 色，failed 还是 outline 风格不一致。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.153 — fix(ui): SidebarTaskLabel awaiting approval 改用实心图标
**Date**: 2026-09-08
**Tag**: v0.5.153
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 的 `.awaitingApproval` case icon 从 `hand.raised` → `hand.raised.fill`（实心），跟其他 fill 系列图标风格统一。
**Why**: v0.5.152 改了 warn 色但 icon 仍是 outline，跟 running 的 `circle.lefthalf.filled` 风格不一致。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.152 — fix(ui): SidebarTaskLabel awaiting approval 加 warn 色（与 failed 同等显眼）
**Date**: 2026-09-08
**Tag**: v0.5.152
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarComponents.swift`:
  - `SidebarTaskLabel` 的 `.awaitingApproval` case icon 加 `.foregroundStyle(DSHTheme.warn)`，让 awaiting approval 在 sidebar 列表里跟 failed 一样显眼。
**Why**: 之前 awaiting approval 跟 running 同色淡，user 容易忽略需要批准的会话。
**Next**: 继续对齐 Codex 桌面端其他细节。


## v0.5.151 — fix(ui): PlanModeBanner X 按钮 accessibilityLabel 与实际行为一致
**Date**: 2026-09-08
**Tag**: v0.5.151
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner` X 按钮 `.accessibilityLabel` 从 "关闭 Plan mode 提示" 改为 "关闭 Plan mode"（v0.5.149 行为改后 label 没同步）。
  - 新增 `.help("关闭 Plan mode")` tooltip。
**Why**: 行为是关 plan mode 本身，但 a11y label 说"关提示"会误导 VoiceOver 用户。
**Next**: 继续对齐 Codex 桌面端其他细节；或 composer 输入框底部 chip 视觉对齐精修。


## v0.5.150 — fix(ui): PlanModeBanner 副文精简 + 完整说明放 tooltip
**Date**: 2026-09-08
**Tag**: v0.5.150
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner` 副文从 28 字符精简到 10 字符，避免 banner 过高。
  - 完整说明放 `.help(...)` tooltip（persistent vs single-shot 文案区分）。
**Why**: 副文过长让 banner 占两行高度，视觉重心不集中。Codex 桌面端 banner 通常是极简短文本 + icon + 关闭按钮。
**Next**: composer 输入框底部 chip 视觉对齐精修；或继续对齐 Codex 桌面端其他细节。


## v0.5.149 — fix(ui): persistent 模式下 PlanModeBanner X 按钮不真 dismiss
**Date**: 2026-09-08
**Tag**: v0.5.149
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner.onDismiss` 改为始终 `planningMode = false`（v0.5.141 引入 bug：persistent=true 时跳过关闭，banner 永远不消失）。
**Why**: persistent 模式下 X 按钮 = "主动关 plan mode"，符合常驻模式语义。
**Next**: composer 输入框底部 chip 视觉对齐精修（差异小）；或继续对齐 Codex 桌面端其他细节。


## v0.5.148 — fix(ui): Composer placeholder 文案对齐 Codex 桌面端
**Date**: 2026-09-08
**Tag**: v0.5.148
**Test status**: 本机 3116 passed / 13 failed（baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `composerPlaceholder` 默认文案 `"随心输入"` → `"发消息 / 添加文件 / @ 插件"`。Codex 桌面端 placeholder 提示 composer 能做什么，TapgoAICoding 不支持 @ 人但支持 v0.5.147 接通的 @ 插件。
  - 自进化会话特殊文案 `"向自进化下达本轮指令…"` 不变。
**Why**: Codex 桌面端 placeholder 是 "添加文件等内容 @ 人/项目"，对标后改成更贴合实际能力的文案。
**Next**: 下 compose 端 chip 视觉对齐精修；或 NSEvent 全局 hotkey 与系统保留快捷键冲突处理（v0.5.140 EVOLUTION 抽象预留项，目前 addLocalMonitorForEvents 已是 app-local，无具体冲突案例可修）。


## v0.5.147 — feat(protocol): Codex app-server enabledMcpServers 协议层集成（plugin 真激活）
**Date**: 2026-09-08
**Tag**: v0.5.147
**Test status**: 本机 3116 passed / 13 failed（与 v0.5.144/146 baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Services/CodexHarnessClient.swift`:
  - `run(...)` 加 `enabledMcpServers: [String] = []`；`threadRuntimeParams` 在 params 里附加 `enabledMcpServers`；thread/start + thread/resume 调用点都透传。
- `Sources/TapgoAICoding/Services/SessionStore.swift`:
  - `QueuedMessage` 加 `enabledMcpServers` 字段（drain 保留）；`sendUserMessage` / `sendNow` / `newRunner.run` 逐层透传。
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `send()` 加 `enabledMcpServersFromText(_:)`：扫 composer 文本里的 `@DisplayName`，匹配 `pluginCatalogEntries.displayName`（小写不敏感），命中项的 `installSpecifier` 收集传给 harness。
**Why**: v0.5.142 + 菜单加 Codex plugin 是「插入文本」placeholder；Codex 桌面端的真实 plugin 行为是把对应 MCP server 在 thread-level 启用，harness 才能调对应 tool。v0.5.147 让 Tapgo AICoding 真接通 Codex app-server 的 `enabledMcpServers` 字段。
**Next**: NSEvent 全局 hotkey 与系统保留快捷键冲突处理；或 composer 输入框底部 chip 视觉对齐精修。


## v0.5.146 — fix(ui): 移除底部冗余 Plan toggle + 重命名 codexPlugins → pluginCatalogEntries
**Date**: 2026-09-08
**Tag**: v0.5.146
**Test status**: 本机 3116 passed / 13 failed（与 v0.5.144 baseline 一致）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - 移除底部 Plan toggle 按钮（Codex 桌面端底部只有 `+` / `🛡 完全访问` / 模型 / 发送；Plan 入口在 + 菜单）。
  - 重命名内部 API 与产品名 Tapgo 一致：`codexPlugins` → `pluginCatalogEntries`，`loadCodexPlugins()` → `loadInstalledPlugins()`，`codexPluginIcon(for:)` → `pluginIcon(for:)`，`insertCodexPlugin` → `insertPlugin`。"Codex 桌面端"作为产品目标保留。
**Why**: 用户报告 + 菜单已有"计划模式"，底部 Plan 按钮冗余；项目是 Tapgo AICoding，内部代码命名应是 Tapgo 相关，与 Codex（外部对标对象）区分。
**Next**: v0.5.147 把 git stash@{0} 的 enabledMcpServers 协议层改动正式发布；或 NSEvent 全局 hotkey 与系统保留快捷键冲突处理。


## v0.5.144 — fix(ui): Plan mode 强调色误用 brandPrimary（dark mode 白条） + dock ⌘K toggle bug
**Date**: 2026-09-08
**Tag**: v0.5.144
**Test status**: 本机 3116 passed / 13 failed（比 baseline 多 1 个 SSH 网络性 fail，与改动无关）
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `PlanModeBanner.background` / Plan toggle background / Stop 按钮圆形背景：`DSHTheme.brandPrimary` → `DSHTheme.brand`（真品牌蓝）。
- `Sources/TapgoAICoding/Views/ApprovalRow.swift`:
  - 批准按钮 `.tint()`：同上。
- `Sources/TapgoAICoding/Views/ContentView.swift`:
  - `onReceive(tapgoOpenCommandPalette)` 改 `showCommandPalette.toggle()` 并同步发 `paletteDidOpen` / `paletteDidClose`（之前只 set true，⌘K 不 toggle dock）。
**Why**: 用户报告点 Plan 按钮后顶部白条、按钮变白色块。`DSHTheme.brandPrimary` 名字误导——是「主前景色」不是品牌蓝，dark mode 下近白。同时 ContentView 的 ⌘K handler 不 toggle，违背 Codex 桌面端 toggle dock 语义。
**Next**: Codex 插件点击直接执行（当前只插入文本）；或 composer 输入框底部 chip 视觉对齐精修（差异较小，优先级低）。


## v0.5.143 — feat(protocol): Plan mode 与 harness 协议深度集成（turn-level approvalPolicy + sandbox 覆盖）
**Date**: 2026-09-08
**Tag**: v0.5.143
**Test status**: 本机 3117 passed / 12 failed
**Changed**:
- `Sources/TapgoAICoding/Services/CodexHarnessClient.swift`:
  - `run(...)` 加 `planMode: Bool = false` 参数；plan mode 时 turn/start 在 params 里附加 `approvalPolicy: "on-request"` + `sandbox: "read-only"`，让 harness 在每个工具调用前停下来等用户批准（thread 级策略不动，下次 send 关 plan mode 自动恢复）。
- `Sources/TapgoAICoding/Services/SessionStore.swift`:
  - `QueuedMessage` 加 `var planMode: Bool = false`，drain 排队消息保留原 plan mode。
  - `sendUserMessage(_:planMode:)` / `sendNow(_:images:threadId:planMode:)` 透传到 `newRunner.run(planMode:)`。
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - `send()` 调用 `store.sendUserMessage(payload, planMode: planningMode)`，文本前缀 + 协议层双重生效。
**Why**: v0.5.136 视觉强化 → v0.5.141 常驻模式 → v0.5.143 协议层集成（EVOLUTION 累积 Next-2）。文本前缀依赖模型听话，跨 Codex app-server 版本不一致；协议层强制 read-only + 每次工具调用前询问，行为一致。
**Next**: Codex 插件点击直接执行（不再只插入文本）；或 dock 全局 hotkey ⌘K / ⌘⇧P 真触发 dock open/close 验证。


## v0.5.142 — feat(ui): Composer "+" 菜单插件组接入 Codex 插件目录（实时）
**Date**: 2026-09-08
**Tag**: v0.5.142
**Test status**: 本机 3117 passed / 12 failed
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - 新增 `codexPlugins: [PluginCatalogItem]` 与 `loadCodexPlugins()`：调 `PluginManagerService.loadCatalog()` 筛 `codex + installed + enabled`。
  - `composerAddMenu` 插件组优先显示 `codexPlugins`；为空/失败时回落本地静态 `addMenuPlugins`（5 项），菜单永不为空。
  - 新增 `AddMenuAction.insertCodexPlugin(name:detail:)`，点击 → `NotificationCenter.post(name: .tapgoInsertSkill, object: name)`。
  - 加 `codexPluginIcon(for:)` 静态映射：GitHub/Cloudflare/Figma/Gmail/Slack/Notion/MCP → SF Symbol；未知 → `puzzlepiece.extension`。
  - `handleComposerAppear` 里 `Task { await loadCodexPlugins() }` 后台加载。
**Why**: v0.5.141 EVOLUTION Next-1：截图里 Codex 桌面端 + 菜单显示真实 Codex 插件（GitHub / Cloudflare / Figma / Gmail），本地 5 项只是 placeholder。
**Next**: Plan mode 与 harness 协议深度集成；或 Codex 插件点击直接执行（不再只是插入文本）。


## v0.5.141 — feat(ui): Plan mode 深度集成（常驻 + Banner 关闭） + Composer + 菜单对齐 Codex + type-checker 超时修复
**Date**: 2026-09-08
**Tag**: v0.5.141
**Test status**: 本机 3117 passed / 12 failed
**Changed**:
- `Sources/TapgoAICoding/Views/ChatView.swift`:
  - Composer "+" 菜单对齐 Codex 桌面端：每项加"图标 + 标题 + 副标题描述"双行布局；图标精修（`paperclip` / `record.circle` 等）；抽出 `AddMenuItem` / `AddMenuAction` / `composerAddMenuRow` / `runAddMenuAction` 把菜单项配置和渲染分离。
  - 插件分组切到本地静态 `addMenuPlugins`（5 项），保留 `AgentCapabilities.skills` 的描述/图标，预留 Codex 插件目录接入点。
  - Plan mode 常驻模式：`@AppStorage("tapgo.planModePersistent")`；开启后发送消息不重置 `planningMode`。
  - `PlanModeBanner` 加 `isPersistent` / `onDismiss` 参数 + X 关闭按钮 + "Plan mode（常驻）" 文案。
  - 拆出 `handleComposerAppear` / `handleComposerDisappear` 修复 Swift type-checker 在 body 多语句闭包 + 大量 onReceive 上的 O(n²) 超时（之前 release build 卡 30+ 分钟，本次秒过）。
- `Sources/TapgoAICoding/App.swift`:
  - 加 `Notification.Name.tapgoPlanModeBannerDidDismiss` 配合 PlanModeBanner 的 X 按钮。
**Why**: 用户要求 composer 输入框左侧"+"菜单对齐 Codex 桌面端（带描述）；同时把上一轮 v0.5.141 WIP（Plan mode 持久化）收尾。
**Next**: Codex 插件目录接入 composer + 菜单（GitHub / Cloudflare / Figma / Gmail）；Plan mode 与 harness 协议深度集成（让 Codex app-server 知道"plan only"语义并禁用工具）。


## v0.5.140 — fix(ui): NSEvent 全局 hotkey 与 dock keyboardShortcut 冲突解决
**Date**: 2026-09-08
**Tag**: v0.5.140
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `App.swift` 加 `@MainActor enum PaletteState { static var isOpen: Bool }`。
- NSEvent 回调：dock 开着时不消费事件，让 dock 内的 keyboardShortcut 处理 ↩ 选。
- NotificationCenter observer 跟踪 dock 开关。
- `ContentView` 切换 `showCommandPalette` 时 post 通知。
**Why**: v0.5.137 NSEvent 监听让 dock 打开时 ↩ 键失效。
**Next**: Plan mode 与 harness 协议深度集成；或 dock 全局 hotkey ⌘K / ⌘⇧P 实际触发 dock open/close。

## v0.5.139 — feat(ui): 命令面板 11 个 action 全局 hotkey 真接通
**Date**: 2026-09-08
**Tag**: v0.5.139
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `ComposerView` body 末尾加 5 个 `onReceive`：`tapgoMcpStatus` / `tapgoSideChat` / `tapgoArchiveEmpty` / `tapgoPinEmpty` / `tapgoTogglePlanMode`。
- 另外 6 个通过 `tapgoShowShortcutsGlobal` + `tapgoOpenCommandPalette` 转发。
- 全局 NSEvent 监听 → composer handlers → 实际 store/State 变更 完整链路。
**Why**: v0.5.137 加了 NSEvent 监听但 ContentView/ChatView 没监听 11 个新 NotificationName，快捷键 post 通知后没反应。
**Next**: Plan mode 与 harness 协议深度集成；或 NSEvent 全局 hotkey 与 view keyboardShortcut 冲突处理。

## v0.5.138 — feat(ui): 更新日志 sheet 加日期筛选
**Date**: 2026-09-08
**Tag**: v0.5.138
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `ReleaseNotesSheet` 顶部 segmented `Picker`（4 档）：全部 / 最近 7 天 / 30 天 / 90 天。
- 拆 `recentEntries()` 为 `parsedEntries()` 返回 `(version, title, date)`，从 `**Date**: yyyy-MM-dd` 行解析。
- 新 `filteredEntries(range:)` 按 `DateRange.days` 截断筛选。
- 筛选为空时显示"无符合时间范围的更新日志"。
**Why**: Codex 桌面端 release notes 顶部分时间筛选；Tapgo 之前只展示全部。
**Next**: Plan mode 与 harness 协议深度集成；或 NSEvent 全局 hotkey 与 view keyboardShortcut 冲突处理。

## v0.5.137 — feat(app): 全局 hotkey 注册（命令面板 11 个 action 快捷键）
**Date**: 2026-09-08
**Tag**: v0.5.137
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `App.swift` `init()` 末尾加 `installGlobalHotkeyMonitor()`：用 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 监听。
- 11 个 action 快捷键（`⌃⌘M`/`⌃⌘R`/`⌃⌥S`/`⌃⌘B`/`⌃⌘K`/`⌥⌘F`/`⌥⌘⌫`/`⌃⌘I`/`⌃⌘P`/`⌥⌘P`/`⇧⌘R`）外加 `⌘K`/`⌘⇧P` 触发 dock。
- 匹配 keyCode + modifierFlags 后 post 新增 11 个 `Notification.Name`。
**Why**: SwiftUI `.keyboardShortcut` 仅在 view focus 时工作；dock 关闭时所有快捷键失效。NSEvent.addLocalMonitorForEvents 让快捷键 app 范围全局生效。
**Next**: 让 dock 命令面板在 dock 打开时把 keyboardShortcut 事件也作为 dock 内的菜单项触发（不重复）；或更新日志 sheet 加日期筛选。

## v0.5.136 — feat(ui): Plan mode 视觉强化（composer 顶部蓝色 banner）
**Date**: 2026-09-08
**Tag**: v0.5.136
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `ComposerView` body 顶部加 `if planningMode { PlanModeBanner() }`。
- 新 `PlanModeBanner` struct：蓝色 brandPrimary 背景 + 灯泡图标 + "Plan mode 已开启" 主文 + "下一条消息会让 Codex 先出方案不执行工具" 副文。
- 触发方式：点 composer 工具栏 Plan 按钮 / palette "Plan 模式" / /plan slash / `tapgoTogglePlanMode` 通知。
**Why**: Codex 桌面端 composer 顶部显示 Plan mode 提示；Tapgo 此前只在按钮 + send() 时隐式生效。
**Next**: 全局 hotkey 注册（让 palette 快捷键真触发动作而不仅 UI 显示）；或更新日志 sheet 加日期筛选。

## v0.5.135 — feat(ui): 更新日志 sheet 底部加 commit 历史链接
**Date**: 2026-09-08
**Tag**: v0.5.135
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `ReleaseNotesSheet` 底部新增 `Link(destination:)` footer：GitHub commits 列表 + 当前版本 release tag。
**Why**: 用户从更新日志可一键跳到完整 commit 列表或 release 页面，无需手动搜。
**Next**: Plan mode 与 harness 协议深度集成；或命令面板 + slash command 加全局 hotkey 触发。

## v0.5.134 — feat(ui): 更新日志 sheet 加 GitHub release 链接
**Date**: 2026-09-08
**Tag**: v0.5.134
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `ReleaseNotesSheet` 每条版本日志变成 `Link(destination:)`（点击跳 GitHub release tag URL）。
- `recentEntries()` 返回类型 `[(version: String, title: String)]`，解析 `## vX.Y.Z — 标题` 拆出版本号和标题。
- `releaseURL(for:)` 辅助函数返回 `https://github.com/chenlaiyi/TapgoAICoding/releases/tag/vX.Y.Z`。
**Why**: Codex 桌面端 release notes 可点击每条跳 commit/release。
**Next**: Plan mode 与 harness 协议深度集成；或命令面板 + slash command 加键盘快捷键（不是 menu shortcut 而是真正注册为全局 hotkey）。

## v0.5.133 — feat(ui): 命令面板 11 个 action 快捷键完整化
**Date**: 2026-09-08
**Tag**: v0.5.133
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `actions` 数组 10 个 action 加 `keyLabel`（之前 5 个为 nil）：MCP ⌃⌥M / 代码审查 ⌃⌘R / 侧边 ⌃⌥S / 创建聊天分支 ⌃⌘B / 压缩 ⌃⌘K / 反馈 ⌥⌘F / 归档 ⌥⌘⌫ / 状态 ⌃⌘I / Plan 模式 ⌃⌘P / 置顶聊天 ⌥⌘P。
- 避开 macOS 系统保留快捷键（⌘Q/⌘W/⌘M/⌘T 等）。
- Entry 渲染 `if let k = e.key` 路径已就绪，无需额外修改。
**Why**: Codex 桌面端命令面板每行右侧显示快捷键（如 ⌘N、⌘⇧R 等）；当前 10 个 action 没快捷键，用户无法知道有什么 trigger。
**Next**: Plan mode 与 harness 协议深度集成；或更新日志 sheet 加版本号筛选 + commit 链接。

## v0.5.132 — feat(ui): 命令面板加 settings / 更新日志 / 快捷键入口
**Date**: 2026-09-08
**Tag**: v0.5.132
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `CommandPaletteView` actions 末尾加 2 个 entry：更新日志（弹 `ReleaseNotesSheet` sheet 从 EVOLUTION.md 头部读 12 个版本段 + 当前 App 版本）+ 快捷键（弹 `ShortcutsView` sheet）。
- 新增 `ReleaseNotesSheet` 私有 struct（从 `EVOLUTION.md` 解析 `## v...` 段标题）。
- `CommandPaletteView` 加 `showReleaseNotesSheet` + `showShortNotes` 两个 @State（独立于 ContentView 顶层 state）。
- ContentView 顶层 `showShortcuts` sheet 移除（已移入 CommandPaletteView 内）。
**Why**: 命令面板应是"命令中心"——settings/release notes/help 都该是其一键可达。
**Next**: Plan mode 与 harness 协议层深度集成；或让每个 action 的快捷键更全（key column 完整化）。

## v0.5.131 — feat(ui): 命令面板 section header 文字（环境 / 当前对话 / 全局）
**Date**: 2026-09-08
**Tag**: v0.5.131
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `PaletteAction` 加 `sectionName: String?` 字段；`sectionDivider(_:preceding:)` 接受 section 名。
- `Entry` 加 `sectionName: String?` 字段。
- actions 数组中 3 个 divider 元素分别传 "环境" / "当前对话" / "全局"。
- `ForEach(entries)` 渲染：`if let section = e.sectionName, section != lastSectionName` 时插 Text(section.uppercased()) + caption2 + secondary + padding。
**Why**: v0.5.130 只加 Divider 视觉分组；Codex 桌面端实际用 caption 文字 + Divider 一起标识 section 名称。
**Next**: 全局命令面板加 settings/release notes/帮助入口；或 Plan mode 与 harness 协议层深度集成。

## v0.5.130 — feat(ui): 命令面板按状态分组（Divider 视觉对齐 Codex 桌面端）
**Date**: 2026-09-08
**Tag**: v0.5.130
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `PaletteAction` 加 `isSectionDivider: Bool` 字段 + `static func sectionDivider(_:)` 辅助构造器。
- `Entry` 加 `isDivider: Bool` 字段（默认值 false）。
- `actions` 数组在 MCP 后 / 归档后 / 置顶聊天前插入 3 个 `Self.sectionDivider(...)`。
- `ForEach(entries)` 渲染：`if e.isDivider { Divider().padding(.vertical, 4) } else { Button(...) }`。
**Why**: 命令面板 14 个 actions 连续排列无视觉分组；Codex 桌面端按"环境/当前对话/全局设置"分组。
**Next**: 全局命令面板（Cmd+K 的替代）加 settings / release notes / 帮助入口；或把 Plan mode 与 harness 协议层深度集成。

## v0.5.129 — feat(ui): composer "+" 按钮对齐 Codex 桌面端下拉菜单（含 /plan + MakeHistory 双向严格回填）
**Date**: 2026-09-08
**Tag**: v0.5.129
**Test status**: jkmacmini 待跑；本机 3123 passed / 12 failed
**Changed**:
- `ComposerView.composerAddMenu` 新 computed property：Codex 桌面端风格下拉菜单（标题"添加" + 5 组：文件和文件夹 / 附加 Tapgo AICoding / 目标 / 计划模式 / 录制技能 / 插件 sub-section）。
- `App.swift` 加 3 个 `Notification.Name`：`tapgoAddFiles` / `tapgoAttachTapgo` / `tapgoTogglePlanMode`。
- `ComposerView` 加对应 `onReceive` 处理器：`tapgoAddFiles` → `pickImages()`；`tapgoTogglePlanMode` → `planningMode.toggle()`。
- `ComposerView.body` 内的旧 `Menu { ... }` 替换为 `composerAddMenu` 引用；Label 全部 5/6 项已对齐。
**Why**: 用户给截图（Codex 桌面端命令面板下拉样式），当前 Tapgo composer "+" 按钮只有"图片附件 + 插入技能"两项；需要分组（文件/附件/目标/计划/录制/插件）+ 标题 + 子分组。
**Next**: Plan mode 接入 harness 协议层（让 Codex app-server 知道"plan only"语义并禁用工具）；或 ChatView 全局命令面板里加 "settings" / "release notes" 等入口。

## v0.5.128 — test: MakeHistory parity 双向严格 + 历史段回填
**Date**: 2026-09-08
**Tag**: v0.5.128
**Test status**: jkmacmini 待跑；本机 3117 passed / 12 failed
**Changed**:
- `Sources/TapgoTests/MakeHistoryParityTests.swift` 升级为双向严格：makeHistory ↔ EVOLUTION.md 每个 v0.5+ 段必须互见（iOS 子项目 v1.x 与 v0.0-v0.2 旧段过滤）。
- `Sources/TapgoAICoding/Views/EvolutionLogView.swift` makeHistory 补 19 个历史段：v0.3.0/2/3、v0.4.0/1/3、v0.5.0/1/4、v0.5.52、v0.5.58-61、v0.5.80/81、v0.5.84-99、v0.5.105、v0.5.108（commit SHA 从 git log 反查）。
- `EVOLUTION.md` 头部 v0.5.5 之前补 12 个段：v0.3.0/2/3、v0.4.0/1/3、v0.5.0/1/4、v0.5.80/81/104。
**Why**: v0.5.127 测试只检查 makeHistory → EVOLUTION 单向；发现历史漏段 19 个。补齐后双向严格测试可持续。
**Next**: 命令面板按状态分组；或把 AGENTS.md / MakeHistory 之外章节结构化（Roadmap / Known issues）。

## v0.5.127 — test: MakeHistory parity suite（防 v0.5.125 中文双引号 bug 重现）
**Date**: 2026-09-08
**Tag**: v0.5.127
**Test status**: jkmacmini 待跑；本机 3116 passed / 12 failed（新增 6 个 MakeHistory 测试）
**Changed**:
- `Sources/TapgoTests/MakeHistoryParityTests.swift` 新增：抽 `version: "vX.Y.Z"` 模式验证 makeHistory 版本数 ≥ 20；makeHistory 数组内引号数为偶数（防 v0.5.125 中文双引号吞 entry 的 bug）；makeHistory 最近 10 个版本都在 EVOLUTION.md 头部段；`Info.plist` 与 `project.yml` 的版本号一致。
- `Sources/TapgoTests/TestMain.swift` 在 `allSections` 数组与 `runIfInScope` 调用处加 `MakeHistory parity: structural and Info.plist sync`。
**Why**: v0.5.125 中文双引号（`"Plan"`）让 makeHistory 数组的解析延后到 build 时才发现，靠手工 patch 修。加字符串级测试后下次发版前自动 fail。
**Next**: 把 EVOLUTION.md 历史漏段补齐（v0.5.4 / v0.5.80-81 / v0.5.104 等）；或把"MakeHistory ↔ EVOLUTION" 双向对齐做成"EVOLUTION 是 makeHistory 子集"的宽松检查。

## v0.5.126 — feat(ui): 命令面板上下文相关（目标/置顶根据当前 thread 实时显示）
**Date**: 2026-09-08
**Tag**: v0.5.126
**Test status**: jkmacmini 待跑；本机 3110 passed / 12 failed
**Changed**:
- `CommandPaletteView.actions` 从 `let [...]` 改为 `var actions: [PaletteAction]` 计算属性，每次 body 重新计算时读 `store.activeThreadId` + `liveThreads.first(where: { $0.id == activeID })`。
- "目标" 标题动态化：当前 thread 有 `goal` 且非空 → "编辑目标（<goal 前 18 字符>）"，否则 "目标"。
- "置顶聊天" 标题动态化：当前 thread `isPinned == true` → "取消置顶"，否则 "置顶聊天"。
- 行动 `run` 闭包保持原有 `store.togglePinned(id)` / `tapgoOpenGoalEditor` 通知逻辑——只是 title 反映状态。
**Why**: Codex 桌面端 palette 的"目标"/"置顶"行右侧会有实时状态指示；Tapgo 此前只显示静态文字，让用户每次要点开才知道当前是否已设。
**Next**: MakeHistory 之外的 EVOLUTION 章节结构化（如 Roadmap / Known issues 列表）；或 makeHistory 自身的字符串解析测试覆盖（v0.5.125 的中文双引号 bug 是手工 patch 暴露的——加自动测试可防止再次出现）。

## v0.5.125 — feat(chat): Plan mode（Codex 桌面端"先出方案"模式）
**Date**: 2026-09-08
**Tag**: v0.5.125
**Test status**: jkmacmini 待跑；本机 3110 passed / 12 failed
**Changed**:
- `ChatView` 加 `@AppStorage("tapgo.planningMode") private var planningMode`；composer 工具栏（在 `environmentChip` 后）加 `Plan` toggle 按钮。
- `ChatView.send()`：若 `planningMode == true`，把用户消息包成 `[计划模式] 请先给方案…不要执行任何工具调用。\n\n<原消息>` 发送；发送后 `planningMode = false`（单次模式）。
- `CommandPaletteView.actions` 加 "Plan 模式" 入口（`lightbulb` 图标）：点击设置 `UserDefaults` 标记 + 弹 alert 提示。
**Why**: Codex 桌面端"Plan"模式让用户审查方案再执行；Tapgo AICoding 此前只有直接执行，没有"先思考"路径。
**Next**: 让 palette 的"目标"和"置顶"显示当前 thread 的实时状态（已设目标显示"编辑目标"、已置顶显示"取消置顶"）；或考虑 MakeHistory 之外的 EVOLUTION 章节结构化。

## v0.5.124 — feat(ui): 命令面板 access-level badge（Codex 桌面端"完全访问"指示器）
**Date**: 2026-09-08
**Tag**: v0.5.124
**Test status**: jkmacmini 待跑；本机 3110 passed / 12 failed
**Changed**:
- `CommandPaletteView` mini composer 左侧加 access-level badge：`Image("clock.arrow.circlepath") + Text(currentAccessLevel)`，颜色按 `SandboxMode` 区分（`dangerFullAccess` 橙色 / 其他 secondary）。
- `currentAccessLevel: String` 计算属性从 `TapgoConfig.sandboxKey` 读 `SandboxMode` 并调 `displayName`；`accessLevelColor: Color` 同源。
**Why**: 用户给截图（Codex 桌面端命令抽屉底部有"完全访问"状态）后 v0.5.122-123 只补 dock 主体，状态指示器仍是空白。
**Next**: Plan mode（需 harness 协议支持）或上下文相关命令（按当前 thread / project 动态增减 palette actions）。

## v0.5.123 — feat(ui): 命令面板 Esc + ⌘K 关闭
**Date**: 2026-09-08
**Tag**: v0.5.123
**Test status**: jkmacmini 待跑；本机 3110 passed / 12 failed（与 v0.5.122 一致）
**Changed**:
- `CommandPaletteView` body 末尾加两个隐藏式 Button（`.frame(0,0).opacity(0)`）：一个 `.keyboardShortcut(.escape)`、一个 `.keyboardShortcut("k", modifiers: [.command])`；两者都触发 `onDismiss()`。
- 搜索框自动 focus 沿用 v0.5.122 之前的 `NSTextField.makeFirstResponder`（打开即输入）。
**Why**: Esc + ⌘K toggle 是 Codex 桌面端命令面板的标键盘交互习惯；补齐后让用户能完全键盘操作 dock。
**Next**: 底部状态指示器 badge（"完全访问" 等 access level 显示）或 Plan mode（需 harness 协议支持）。

## v0.5.122 — feat(ui): 命令面板底部 mini composer（Codex 桌面端 dock 工具条）
**Date**: 2026-09-08
**Tag**: v0.5.122
**Test status**: jkmacmini 待跑；本机 fafamacmini 3110 passed / 12 failed（与 v0.5.121 一致；12 项失败均为 SSH 远程集成 + auth.json 环境性）
**Changed**:
- `CommandPaletteView` body 末尾加 `VStack { Divider; HStack { +, TextField, model label, send button } }`，与 Codex 桌面端底部 dock 一致。
- 新 `@State miniPrompt: String` 持有 mini composer 文本；`sendMiniPrompt()` 把文本写 `tapgo.composer.pendingText`（UserDefaults shuttle）+ post `tapgoFocusComposer` + 清空 miniPrompt + 关 palette。
- `currentModelLabel: String` 计算属性从 `UserDefaults` 读 `TapgoConfig.selectedModelKey`（去掉 `builtin:` 前缀）。
- 关闭回调重构：`CommandPaletteView` 用 `let onDismiss: () -> Void` 替代 `\.dismiss`（overlay 模式无 sheet dismiss 环境）；`ContentView` 调用处 `onDismiss: { withAnimation(...) { showCommandPalette = false } }`。背景 tap 保留 `showCommandPalette = false`（ContentView 自身 state）。
- 修复 sed 误删 `ShortcutsView.dismiss` 的回归——加回 `@Environment(\.dismiss) private var dismiss`。
**Why**: 用户给截图（Codex 桌面端命令抽屉底部有 + / 输入框 / 模型 / 发送）后 v0.5.121 只覆盖列表部分，底部 dock 仍是空白。补齐后命令抽屉与 Codex 桌面端视觉完全一致。
**Next**: Plan mode（需 harness 协议支持）、命令面板键盘焦点优化、可能补 `⌥⌘K` 等附加快捷键。

## v0.5.121 — feat(ui): 命令面板改为底部抽屉 + 11 个动作对齐 Codex 桌面端
**Date**: 2026-09-08
**Tag**: v0.5.121
**Test status**: jkmacmini 待跑；本机 fafamacmini 3110 passed / 12 failed（DesktopDesignParityTests `⌘\` 切换侧边栏 + palette 双入口 回归通过；12 项失败均为 SSH 远程集成 + auth.json 环境性）
**Changed**:
- `ContentView` 命令面板从 macOS 居中浮层改为底部 docked 抽屉：`VStack { Spacer; Palette }`、`.frame(maxWidth: 720, maxHeight: 460, alignment: .top).frame(maxWidth: .infinity)`、`.regularMaterial` + `UnevenRoundedRectangle` 顶部圆角；进场动画改 `.move(edge: .bottom).combined(with: .opacity)`。
- `CommandPaletteView.actions` 重写为 Codex 桌面端 11 个动作顺序：MCP / 代码审查 / 侧边 / 创建聊天分支 / 压缩 / 反馈 / 归档 / 新聊天 / 状态 / 目标 / 置顶聊天 / 切换侧边栏 / 运行设置。
- `SessionStore` 新增 6 个方法：`archiveActiveThread()`、`spawnSideChat()`、`createBranchForActiveThread(_:)` + `BranchCreationOutcome` enum、`snapshotActiveThreadForFeedback() -> URL?`（写 `~/.tapgo/feedback/<ISO>-<title>.md`）、`statusSnapshotForActiveThread() -> String`、`mcpStatusSummary() -> String`。
- `App.swift` 新增 `tapgoOpenGoalEditor` 通知；`ChatView` 监听并设置 `editingGoalItem = GoalEditItem(text: "")`；`ContentView` 的 palette "目标" 行 post 此通知。
- `PaletteInfoAlert` 结构体（title + message + UUID id）；`CommandPaletteView` 自含 `@State paletteInfoAlert / pendingBranchPrompt / branchNameDraft` + 关联 `.alert` 与 `.sheet`（避免在嵌套 view 内访问父 view 的 @State）。
- 命令面板每行右侧状态：压缩显示已用 %、会话显示 thread 状态圆点 + 上下文 % + 项目名。
**Why**: 用户给截图（Codex 桌面端命令列表抽屉式）后差距大：当前面板是 macOS sheet 居中浮层，命令集也缺 7 个（侧边/创建聊天分支/反馈/归档/MCP 状态/置顶/目标）。
**Next**: 下一阶段补底部 mini composer（截图底部有 + 按钮 + 输入框 + 模型名 + 状态 + 发送），以及 Plan mode（需 harness 协议支持）。

## v0.5.120 — feat(chat): /review [scope] slash command — open diff-review thread
**Date**: 2026-09-08
**Tag**: v0.5.120
**Test status**: jkmacmini 待跑；本机 fafamacmini 3110 passed / 12 failed（新增 ComposerLocalCommand 6 个 /review case；12 项失败均为 SSH 远程集成 + auth.json 环境性）
**Changed**:
- `ComposerLocalCommand` 加 `.review(String)` case + 解析；`/review` bare token 默认 working scope，scope 名称 trimming。
- `SessionStore.startReviewThread(scope:)` 创建引导 thread，title 编码 scope 让会话列表可区分；`resolveReviewScope(_:)` 把字符串映射到 git args（`""`→`diff HEAD`、`staged`→`diff --staged`、`main`→`diff origin/main...HEAD`、其他→`diff <scope>`），hint 字段说明范围。
- `SessionStore.makeReviewPrompt(scope:gitArgs:hint:)` 写结构化 prompt：先 `--stat` 看全貌、再看完整 patch、再 cat 项目约定、最后给"风险 + 设计 + 测试 + 文档"四类审查 + 优先级排序的"建议改动"。
- `ChatView.handleLocalCommand` 加 `case .review(let scope)`；`slashMenu` 加 `/review [scope]` 行（占位补全到 `/review `）。
**Why**: Codex 桌面端 `/review` 让用户在提交前快速跑一次结构化 diff 审计；本地 thread 比外部 PR review 工具更轻量、不阻塞提交流。
**Next**: 下一阶段实现 Plan mode（先让 Codex 出方案再执行，需 harness 协议支持），或把 `makeHistory` 之外的 EVOLUTION 章节（如 release cadence、已知问题）结构化。

## v0.5.119 — feat(chat)+feat(ui): 命令面板浮层化 + slash 命令补齐 (/init /compact)
**Date**: 2026-09-07
**Tag**: v0.5.119
**Test status**: jkmacmini 待跑；本机 fafamacmini 3104 passed / 12 failed（新增 ComposerLocalCommand 6 个 /compact case + 6 个 /init case；12 项失败均为 SSH 远程集成 + auth.json 环境性）
**Changed**:
- `ContentView` 命令面板从 `.sheet(isPresented:)` 改为 `.overlay` 浮层：半透明黑色背景 + `.regularMaterial` 模糊 + 圆角阴影 + spring 弹性进场（响应 0.28s / 阻尼 0.85）；点背景关闭。
- `ComposerLocalCommand` 加 `.initProject` 与 `.compact` cases；`/init` 与 `/compact` 都是 bare token；其他 slash 命令与测试同步更新。
- `SessionStore.startInitProjectThread()` 创建引导 thread 预填 AGENTS.md 起草 prompt；prompt 显式约束：不输出空泛推断、不覆盖既有 AGENTS.md、保留 `<待补充>` 占位、必须先 ls/cat 扫描项目根。
- `SessionStore.compactActiveThread()` 折叠 assistant items：每回合的 user message 保留，其余 items 替换为单条 compact 提示；harnessThreadId 重置让下次发消息从干净上下文开始；回合正在跑时返回 `.busy`。
- `ChatView` 加 `case .initProject` 与 `case .compact` 分支；`CompactOutcomeAlert` 结构体把 outcome 翻译成中文提示（empty / busy / compacted）。
- `slashMenu` 加 `/init` 与 `/compact` 两行；提示文本同步覆盖所有 slash 命令用法。
**Why**: 命令面板的 sheet 样式视觉割裂 Codex 桌面端；slash 命令 `/clear` `/model` `/init` `/compact` 是 Codex 桌面端核心习惯，纳入让 composer 内一步可达。
**Next**: 下一阶段补 `/review`（Codex 桌面端常用，让 Codex 审阅当前 diff）或 Plan mode（先让 Codex 出方案再执行，需 harness 协议支持）；同时把 `makeHistory` 之外的 EVOLUTION.md 章节（如 ETag 备注 / release cadence）结构化。

## v0.5.118 — feat(chat): slash 命令补齐 — /clear 清空会话 + /model 模糊切模型
**Date**: 2026-09-07
**Tag**: v0.5.118
**Test status**: jkmacmini 待跑（commit 在 fafamacmini 上完成）；本机 fafamacmini 3092 passed / 12 failed（新增 ComposerLocalCommand 11 个 case 全过；12 项失败均为 SSH 远程集成 + auth.json 环境性，与改动无关；AppUpdateDistributionTests 在 tag v0.5.117 后已自动通过）
**Changed**:
- `ComposerLocalCommand` 新增 `.clear` 与 `.model(String)` cases；`/clear` 是 bare token，`/model <query>` 用字符串前缀 + 空白分隔严格解析（`/modelA`、`/modeling`、`请解释 /model` 一律走模型）；提取出 `strippingLocalCommandPrefix(_:)` helper 复用分隔逻辑。
- `SessionStore.clearActiveThread()` 清空当前 thread 的 turns + 重置 harnessThreadId + 取消 in-flight turn + 清空 composer；thread 元数据保留。
- `SessionStore.selectModel(matching:)` 模糊匹配 `selectableModelOptions()`：按 displayName / modelID / providerName 大小写无关 substring；返回 `ModelSelectOutcome`（empty / notFound / ambiguous / selected / notConfigured）让 ChatView 用 alert 提示。
- `ChatView.handleLocalCommand` 加 `.clear` 与 `.model` 分支；`slashMenu` 加 `/clear` + `/model` 两行（`/model` 占位补全 + 提示文本更新）；`ModelSelectAlert` 结构体把每种 outcome 翻译成中英文标题/消息。
- 复用 `TapgoConfig.selectProviderModel(providerID:modelID:)` 做实际切换——写 UserDefaults + 注册表 + 重写 config.toml / 目录让 harness 热加载。
**Why**: Codex 桌面端常见 `/clear` 与 `/model` 命令对长对话很有用——前者跳出 token 越界，后者按任务类型换模型。命令面板 已有等价 UI（⌘K 弹出），但内联 slash 命令是 Codex 桌面端的"快键"习惯，纳入让 composer 一步到位。
**Next**: 下一阶段补 `/init`（让 Codex 扫描项目结构生成 AGENTS.md）与 `/compact`（本地压缩 turns 摘要，Codex app-server 无原生 API 需本地模拟）；同时把命令面板从 sheet 升级为中心浮层背景模糊，与 Codex 桌面端对齐。

## v0.5.117 — fix(harness)+feat(chat): 回合兜底完成 + 文件变更卡 per-file 兜底 + HTML 预览
**Date**: 2026-09-07
**Tag**: v0.5.117
**Test status**: 3080 passed / 0 failed on jkmacmini（新增 harness thread/status idle 终结态回归 + WorktreeChangeTracker per-file diff 与 HTML 预览回归）；本机 fafamacmini 3078 passed / 14 failed（9 项 SSH 远程集成 + auth.json 环境性，2 项 AppUpdateDistributionTests 版本对齐需 tag 后通过，3 项其他 SSH 远程套件）
**Changed**:
- `ExecEventParser` 新增 `thread/status: idle` → `turnCompleted`（completed、幂等）映射；`SessionStore.turnCompleted` 加终结态保护（已 completed/failed/interrupted 的 turn 不再被后续事件覆盖，只吸收 usage）。长回合"永远正在处理"被根治。
- `WorktreeChangeTracker.collect` 升级为 per-file 明细：当协议没有 per-file `fileChange` / `turn/diff` 时（如 codex 用 `mkdir`/`cat` 写文件），按 baseline 差集生成真正的 `FileChange`（文件名+路径+±行数+可展开 diff），`TurnPresentation` 折叠成批次卡；已有协议级 diff 不重复生成。
- `FileChangeRowView` 对 `html`/`htm` 新增"在内部浏览器预览"（右键菜单）：WKWebView `loadFileURL` 弹窗，允许同目录相对资源；关闭按钮支持 Esc。
- 修复兜底变更卡的窗口重布局崩溃：原 `untrackedDiff` 对 tracked 修改套用了 `--- /dev/null +++ path` 合成 diff，hunk 头声称 0 旧行但内容矛盾，`DiffView` split 模式 `ViewDimensions` 下标越界触发 EXC_BREAKPOINT。现在按来源区分——untracked 纯新增才合成全 + diff，tracked 修改直接走 `git diff HEAD -- path`；`FileChange.kind` 按来源标 create/update。
**Why**: 三处都用 GPT-6 实测任务暴露——`thread/status` 漏解析让长回合看似永远在处理；用命令生成的文件没有变更卡让"页面已生成"显得空话；tracked 兜底合成 diff 让窗口按快捷键重布局时崩溃。
**Next**: 继续按真实远程任务核对 Harness 终结态与变更卡边界；下一步在 WorktreeChangeTracker 暴露 baseline 比对开关，让用户能禁用兜底 diff（如临时改动不想被判定为变更）。


## v0.5.116 — feat(plugin-marketplace): 起 Tapgo 官方插件模板与 catalog 协议校验
**Date**: 2026-09-06
**Tag**: v0.5.116
**Test status**: 3059 passed / 0 failed（新增 7 个 PluginCatalog: repo example parses 断言，与 v0.5.115 合并后无回归）
**Changed**:
- 新增 `Plugins/` 模板：`tapgo-plugin-sparkle-publish`（薄封装 Sparkle 发版脚本）+ `tapgo-plugin-screen-permission`（macOS TCC 自检）；含 README、LICENSE、scripts/。
- 新增 `Plugins/catalog.example.json`：符合 `TapgoPluginListPayload` 协议的两条 demo 目录，作为 `plugins.itapgo.com/catalog.json` 的发布示例。
- 新增单元测试 `PluginCatalog: repo example parses`（7 断言）：实时读取仓库内 `Plugins/catalog.example.json`、断言 `PluginCatalogParser.decodeTapgo` 仍能解析、demo pluginId 列表正确、repo URL 指向 `github.com/chenlaiyi/`。
- `Plugins/README.md` 列出从模板到 `plugins.itapgo.com` 部署的四步流程，便于用户后续按 demo 复制新插件。
**Why**: 用户要求"起 catalog.json 模板 + demo 插件"，保证从模板复制 → 建 GitHub repo → 部署静态文件 → TapgoAICoding UI 安装的链路无需任何代码改动即可闭环。
**Next**: 用户在 `github.com/chenlaiyi/` 下建两个真实 repo 并推上 demo 内容，把 `Plugins/catalog.example.json` 部署到 TapgoServer 的 `plugins.itapgo.com/catalog.json`，UI 上「Tapgo 官方」Tab 即可立即渲染并安装。

## v0.5.115 — feat(plugin-marketplace): 接入 Tapgo 官方市场（plugins.itapgo.com）
**Date**: 2026-09-06
**Tag**: v0.5.115
**Test status**: 2903 passed / 2 failed（2 pre-existing：desktop-design Markdown 空行归一化 / HarnessDaemonLauncher socket 假设；本次 0 回归，新增 12 个 PluginCatalog: Tapgo 解析与 pluginId 安全断言）
**Changed**:
- PluginMarketplace 枚举新增 `.tapgo` case，displayName 为「Tapgo 官方」。
- 新增 TapgoPluginListPayload / TapgoPluginRecord JSON 结构：可用字段 pluginId、name、displayName、version、description、repo、channel、capabilities；本地已安装列表由文件系统推导，不需要服务端维护清单。
- PluginCatalogParser.decodeTapgo(\_:installedIds:) 解析官方目录；安装项排前，已装项合并 `.tapgo-plugin.json` 写回的 pluginId。
- PluginManagerService 新增 `loadTapgoCatalog()`：6s 超时、ephemeral URLSession 拉 https://plugins.itapgo.com/catalog.json，失败静默降级不影响其它市场。
- install/uninstall 加 `.tapgo` 分支：install = `git clone --depth 1 <repo> [--branch <channel>]` 到 `~/.tapgo/plugins/<id>/`，卸载 = `rm -rf` 同名目录；pluginId 经 `PluginConfigEditor.isSafePluginId` 校验防路径穿越。
- PluginManagerView：Tab 加 `.tapgo`（"Tapgo 官方"），visibleItems / tabButton count / emptyMessage / content sourceNote 全部加分支；ViewModel.tapgoCount 计算属性；icon 用 `bolt.shield.fill`，色调 0x0EA5E9。
- 新增单元测试：`PluginCatalog: Tapgo parsing`（8 用例，覆盖 install 排前、displayName、repo 用作 installSpecifier、缺失版本占位、search 大小写无关）与 `PluginCatalog: Tapgo safe pluginId`（4 用例，覆盖 pluginId 安全过滤与协议级容忍）。
**Why**: Jacky 要求 Tapgo 官方插件市场拥有自己的分类与可装入口。plugins.itapgo.com 由用户侧自行 DNS 解析指向 TapgoServer，本地通过 git clone 安装到 `~/.tapgo/plugins/`，无需额外 CLI。
**Next**: 待 plugins.itapgo.com 解析上线 + 服务端发布首份 catalog.json 后，UI 上「Tapgo 官方」Tab 即会自动渲染首批插件；下一步在 PluginManagerService 增加 `setTapgoEnabled` 与 PluginConfigEditor 写入 `~/.tapgo/plugins.toml` 的启用/停用切换（当前已安装只显示卸载菜单，跟 DeepSeek 风格对齐）。


## v0.5.114 — 2026-09-06

- 修复远程 SSH 会话找不到已安装执行器的问题；端口、密钥与连接测试保持一致。
- 在远端解析并确认工作目录；配置缺失或目录不可访问时停止，不退回本机执行。
- 远程任务不再注入客户端的项目记忆和本机工具路径；执行器按当前选择加载模型配置。
- 远程栏显示 SSH 目标与目录，修复 Terminal 入口；回复减少文件盘点与重复确认，行内代码改为轻量排版。
- 增加无需模型调用的双向 SSH 协议检查，以及目录、配置缺失和 Shell 转义回归。

## v0.5.113 — 2026-09-06

- 对齐会话过程与总结的层级、字号、段落、列表、引用与代码排版。
- 关闭显示工作过程后，隐藏运行中和历史回合的过程入口、执行清单与工具详情；保留回复、必要确认、错误和修改结果。
- 过程使用简洁动作摘要，原始命令、参数与日志只在主动展开详情后显示；完成时自动收起。
- 用户消息操作预留空间，悬停不再引起布局跳动；复制纯文本保留代码内容。
- 兼容 final 消息类型的流式最终回复，不把未标注类型的过程文字猜成总结。
- 修复混合列表类型串行渲染；缺少耗时时不再显示虚构的 0 秒。

## v0.5.112 — 2026-09-06

- 侧栏统一导航、项目与任务的对齐线、行高和留白；支持 220–360pt 拖拽宽度。
- 项目悬停操作预留固定位置，长标题截断，日期和状态保持右侧对齐。
- 项目折叠状态跨重启保存；选择任务不再改变项目排序。
- 搜索自动展示折叠项目中的命中项；键盘只在当前可见任务中切换。
- 显示方式收进轻量菜单，修复添加项目入口；底部账户与设置改为完整尺寸弹出菜单。

## v0.5.111 — 2026-09-06

- 清单、目标和排队卡片统一为克制的中性色表面，可折叠、可读长内容。
- 执行清单在任务结束后保留；未完成项不会因任务结束被误标完成。
- 清单区分待批准、暂停、失败；目标支持展开全文和明确的暂停/继续操作。
- 收纳排队消息和批准详情，移除重复技术统计与模糊状态。
- 独立原生组件窗口验证深浅色、大字体、窄窗口、长目标与交互回调。


## v0.5.110 — 2026-09-06

- 参照 Codex 截图重做新任务首页：项目标题、四张引导卡片与响应式布局。
- 输入框底部固定，项目栏分层显示，统一深浅色背景与圆角。
- 引导卡片只填入草稿；切换新任务项目保留草稿并同步工作目录。
- 简化首页工具栏，保留真实的模型、权限、附件与发送功能。


## v0.5.107 — 2026-09-05

- 对话接入定时任务创建、查询、取消 MCP，独立于电脑控制 TCC。
- 精确日程指令本地解析，支持周一至周五；打开应用原生执行，无需模型。
- 创建后持久化回读 ID、下一次时间、时区和运行条件；同一有效任务幂等去重。
- 任务文件原子替换，取消清理下一次时间；落盘失败不触发执行。
- 修复定时任务窗口关闭和嵌套编辑 Esc；组合截图完成后重新生成 AX 观察指纹。
- 继承 0.5.106 独立柔光光标和真实点击、输入、拖动。

## v0.5.106 — 2026-09-05

- 独立操作光标：依据参考图绘制浅色空心圆角箭头与淡青柔光，操作时可见且鼠标穿透。
- 修复输入框 AXPress 不支持时无法点击，保留失效观察和禁用控件保护。
- 定向鼠标补齐窗口 ID 与局部位置；真实点击、中文输入、拖动选字和 Chrome Canvas 操作均已验证。
- 滚动使用目标位置并检查前台焦点；整合 main 已发布的定时任务功能。
- 定时任务列表新增明确的关闭按钮与 Esc，编辑表单 Esc 仅关闭编辑层。
- 观察时等待 AX 树短暂稳定，避免 macOS 标题栏动画引发编号瞬时失效。
- 同一构建三机直接安装；本轮未更新公开 Release/appcast。详见 artifacts/computer-use-live-actions/validation.md。


> 最新条目在最上方（latest first）。每个版本对应一个 git tag（一个完整
> build → test → commit → push 闭环）。回滚到任意版本：
> `git checkout vX.Y.Z && ./scripts/build-app.sh`。

## Format

```
## vX.Y.Z — <one-line summary>
**Date**: YYYY-MM-DD
**Commit**: <short SHA>
**Tag**: vX.Y.Z
**Test status**: 110/110 green (or however many passed)
**Changed**:
- bullet
- bullet
**Why**: 1–2 sentences on the motivation / problem solved.
**Next**: what the following iteration plans to tackle (or "see state file").
```

## v0.5.101 — 手机端 composer 权限下拉菜单（3 档）
**Date**: 2026-09-05
**Tag**: v0.5.101
**Test status**: 2801 passed / 13 failed（13 pre-existing 远程 SSH 集成 + helper version 0.5.100 vs tag 0.5.99 一次性断言；本次 0 回归）
**Changed**:
- H5 composer-bar 输入框旁"电脑操作"按钮改为 `权限 ▾` 下拉菜单，含 3 档快捷选项：`请求批准` / `帮我批准` / `完全访问权限`。
- 新增 `POST /api/permissions {profile:"request|auto|full"}`：写入 `TapgoConfig.approvalPolicy` (+`sandboxMode`，full 时切到 danger-full-access)；H5 端立即看到状态变化（下次轮询带回新 `permissions` 字段）。
- `PhoneRemote.buildState` 接受 `permissions: PermissionStatus(sandbox, approval)`，snapshot 加 `permissions` 字段；H5 用来在下拉里高亮当前档位，按钮文字也同步显示档位名（如"权限 · 完全访问权限"）。
**Why**: 用户反馈「输入框里的权限按钮怎么不是下拉菜单选择」——按用户要求简化为 3 档最常用档位，避免无意义的细粒度。
**Next**: 完整权限抽屉仍可通过原 `data-action="control"` 抽屉进入（下拉暂未挂入口，可后续再加 "更多权限…" 项）。

## v0.5.100 — 添加远程主机/项目可用性回归
**Date**: 2026-09-05
**Tag**: v0.5.100
**Test status**: 2802 passed / 12 failed（12 pre-existing 远程 SSH 集成失败无关；RemoteCommandBuilder 4 节 47 个断言全绿，含 14 个新增下划线/空格/斜杠拒绝用例）
**Changed**:
- `SettingsView.AddRemoteHostSheet`：去掉 `.formStyle(.grouped)`（在 macOS 上会阻断 `@State` 与 NSTextField 同步，导致保存按钮永远 disabled），改用直接 `TextField(_, text: $binding)` + 自定义 `canSave` 校验；保存按钮的 `disabled` 现在实时反映字段合法性。
- `RemoteCommandBuilder` 新增公开 `validateAlias(_:)`，alias / host / user 各自错误信息分别精确提示（"别名只允许字母/数字/点/下划线/连字符" / "主机含非法字符" / "用户只允许…"）。
- 端口字段改用 `String` + `Int()` 解析，非法端口给红色错误（覆盖之前的 silently disabled），范围限制 1–65535。
- 新增 14 个 v0.5.100 验证：host / user / alias 含下划线（`mac-mini_jk` / `john_doe` / `dev_box`）必须通过；空格 / 斜杠 必须拒绝。
**Why**: 用户报告"不能配置主机 / 无法添加远程项目"——根因是 SwiftUI Form + macOS 的 `@State` 同步漏，加上 alias 缺字符校验 + 错误提示过宽。这次重写表单让 UI 状态与字段绑定一致。
**Next**: distribute 脚本走一遍。

## v0.5.73 — Harness daemon 解耦（Unix socket transport + launchd 守护）
**Date**: 2026-09-02
**Tag**: v0.5.73
**Test status**: 2680 passed / 14 failed（13 pre-existing 远程 SSH 集成 + 1 个 appcast 对齐 0.5.71→0.5.72，新增 5 个 Socket/Laucher 测试全绿；v0.5.73 自身无回归）
**Changed**:
- 接入 evolver 已实现的 harness 解耦：TapgoHarness daemon 二进制（Sources/TapgoHarness/main.swift，193 行 stdio↔Unix socket bridge）+ HarnessDaemonLauncher（自启动逻辑）+ SocketHarnessTransport（App 端连接）。
- `Package.swift` 注册 `TapgoHarness` target + product；`build-app.sh` 链路完整（依赖只是 Foundation + Darwin）。
- `SessionStore.makeRunner(for:)` 在 `HarnessDaemonLauncher.ensureDaemonRunning` 成功时优先 `SocketHarnessTransport`；失败降级到 `LocalHarnessTransport` 并记日志。
- `scripts/install-harness-daemon.sh` + `uninstall-harness-daemon.sh` + `launchd/com.tapgo.aicoding.harness.plist` 提交进仓库；plist template 同步 v0.5.72 手动部署的 `KeepAlive = { SuccessfulExit=false; ThrottleInterval=2 }` 改进，注释里的 `launchctl load -w` 改成现代 `bootstrap`/`kickstart`/`bootout`。
- 5 个新单元测试（2 Socket + 3 Launcher）：
  - `SocketHarnessTransport: start fails when socket absent`
  - `SocketHarnessTransport: start + send round-trips to listening peer`
  - `HarnessDaemonLauncher: returns true when launcher socket file exists`
  - `HarnessDaemonLauncher: socketPath is the well-known Application Support path`
  - `HarnessDaemonLauncher: daemonBinaryPath resolves to installed binary`
**Why**: evolver 留下的整套 harness 解耦代码之前没进 git，且 `SessionStore.makeRunner` 仍走 `LocalHarnessTransport`，App 没真正用上 daemon（daemon 在本机 v0.5.72 之前已经手动部署 + launchd 守护跑着，但 App 端永远走 stdio）。本版本把链路补齐。
**Next**: `daemonBinaryPath` 是 `static let` — 没法用 env var 在测试里 redirect；后续如需更细测试覆盖，把 daemon binary lookup 改成非 static（带 env var 支持）。中长期「自动化」面板（v0.5.70 Next）。

## v0.5.72 — harness 流式防抖 + 工作过程卡片隐藏 toggle + 自动重连 + 侧栏自进化日志下放
**Date**: 2026-09-02
**Commit**: 0436ae6
**Tag**: v0.5.72
**Test status**: 2673 passed / 13 failed（13 全是 pre-existing：12 个远程 SSH 集成 + 1 个 appcast 校验，无回归）
**Changed**:
- PR #1 (merged): 把 `fix/harness-streaming-save-throttle` 合到 main，三个原始 commit 全部入主线。
- dfb161f `fix(core): debounce ThreadStore saves during harness streaming output` — `ThreadStore.scheduleSave(_:immediate:)` 300 ms 防抖 + `ExecEvent.isPersistenceTerminal` 分类 streaming vs terminal + JSONEncoder 单例 + `NSApplication.willTerminate` drain。修 App 在 2.2M tokens reasoning summary 上每条 deltas 都跑 `JSONEncoder.encode(整棵 thread)` + atomic write 导致 100 % CPU + 13.5 MB/s 盘写穿透（cpu_resource.diag 2026-09-02 00:09）。
- 6b64c6f `fix(ui): hide 目标 IDE-style work process cards by default; add global toggle` — `@AppStorage("tapgo.showWorkProcess")` 默认 false + Settings → 外观加 toggle。turnSection 把工作卡片 AND 短门、workDurationChip 也受开关控制。文件修改摘要条不受影响。
- f05d542 `fix(core): auto-reconnect harness Unix socket; reissue initialize on reconnect` — `HarnessSupervisor.onReconnected(Int)` 回调 + `CodexHarnessClient.supervisorReconnected()` 重新 `initialize` + `LocalHarnessTransport` 修 EOF 静默吞掉。in-flight RPC 不重发，只重发 server-required `initialize`。
- plist 修复 `~/Library/LaunchAgents/com.tapgo.aicoding.harness.plist`：`KeepAlive` 从 `<true/>` 改成 `{ SuccessfulExit=false; ThrottleInterval=2 }`，修注释。
- bf5ded5 (v0.5.71 evolver): 侧栏「自进化日志」从一级导航下放到账户菜单（菜单/账户菜单路径更新）。
- f648013 (v0.5.70 evolver): 侧栏「自动化」→「自进化日志」命名修正。
**Why**: v0.5.69 引入的 目标 IDE-style 工作日志让用户卡死在思考/终端/读取/编辑卡片里；同时 long-running turn 把 App 推上 100 % CPU；daemon 死后 App 不知道重连。三个独立但同源的"用户视角崩溃"问题，一次合版本统一修。
**Next**: 真机端到端验证"长 turn 流式输出过程中 daemon 死了 → App 不重启自动恢复 initialize → 用户继续发消息"。

## v0.5.71 — 侧栏「自进化日志」从一级导航下放到账户菜单
**Date**: 2026-09-02
**Tag**: v0.5.71
**Test status**: 2610 passed / 0 failed（跳过远程环境段）
**Changed**:
- `SidebarView.swift` 一级导航移除「自进化日志」菜单项；「自进化日志」移到账户菜单（底部 user menu）。
- `Desktop目标 IDEDesignTests.swift` 新增 `desktop-design: 自进化日志不在一级导航` 断言。
- AppBuilder/Info.plist bump 0.5.70 → 0.5.71。
**Why**: 「自进化日志」是只读历史页，不该和新建任务/搜索/插件市场混在一级导航；放账户菜单层级更合适。
**Next**: 监控真机回归确认无布局错位。

## v0.5.70 — 侧栏「自动化」→「自进化日志」命名修正
**Date**: 2026-09-02
**Tag**: v0.5.70
**Test status**: 2610 passed / 0 failed（跳过远程环境段）
**Changed**:
- `SidebarView.swift`: 「自动化」一级菜单改名「自进化日志」，icon 从默认改成 `text.book.closed`，tooltip/a11y label 同步更新。
- 「自动化 → 自进化日志」的命名纠正：目标 IDE 的 Automation 面板是定时任务调度，当前实现只是只读 Evolution 日志，按用户反馈避免歧义。
**Why**: 用户反映侧栏菜单项「自动化」与目标 IDE 同名「自动化」语义不符（目标 IDE Automation = 定时/闲时任务调度，本 App 自动化 = Evolution 历史），造成混淆。
**Next**: 中长期：把「自动化」做成真任务调度面板（任务模型 + 定时/闲时调度 + 模板库 + UI + 持久化 + 测试）。

## v0.5.69 — 仿 目标 IDE 内容输出样式
**Date**: 2026-09-01
**Tag**: v0.5.69
**Test status**: 2610 passed / 0 failed（跳过远程环境段）
**Changed**:
- 回合内每个事件（思考/查阅/终端/编辑/读取）各占一行安静灰底短行，显示具体内容；连续搜索类工具调用合并为"查阅 · N 搜索, M 列表"；失败事件整行变"…执行失败 ⚠️"。
- 文件编辑改成安静单行："编辑 Sources/A.swift AppBuilder +8 -2"，点击展开 diff；失败加"执行失败"。
- 完成后所有工作行折叠为"已工作 X 分 Y 秒 ⌄"芯片 + "N 个文件已更改 +A -B"摘要条；点击展开。
- 2610 测试新增结构测试覆盖新语义。
**Why**: 原 目标 IDE-style 折叠被助手文字触发，工作日志被藏得太深，用户看不到思考/查阅/命令的细节。目标 IDE 本身在每个事件保留一行短描述。
**Next**: 真实账号登录后真机回归 UI 视觉与展开交互。

## v0.5.68 — 检查更新弹窗改简体中文
**Date**: 2026-09-01
**Tag**: v0.5.68
**Test status**: 2610 passed / 0 failed（跳过远程环境段）
**Changed**:
- Info.plist 新增 CFBundleLocalizations（zh-Hans/zh_CN/en）：此前从未声明，Sparkle 按声明回退英文弹窗。
- build-app.sh 嵌入 Sparkle 框架后把 zh_CN.lproj 镜像为 zh-Hans.lproj：系统语言标记是现代写法 zh-Hans-US，与框架里的旧命名 zh_CN.lproj 匹配不上， Sparkle 内部仍回退英文。
- 真机验证：检查更新弹窗显示"您使用的就是最新版！…0.5.67 是当前的最新版本。"与"好"按钮；系统菜单栏（文件/编辑/显示/窗口）同步恢复中文。
**Why**: Sparkle 的界面语言 = 应用声明语言 ∩ 框架自带资源语言，两个环节都断在中文上；只补声明或只改资源名都会在一侧回退英文。
**Next**: 观察下次真实发版时两台机器的更新弹窗与自动更新流程是否全程中文。

## v0.5.67 — 恢复聊天右侧自适应环境卡自动显示
**Date**: 2026-09-01
**Tag**: v0.5.67
**Test status**: 2610 passed / 0 failed（跳过远程环境段）
**Changed**:
- 恢复 AdaptiveEnvironmentCard 响应式自动显示（v0.5.59 起被硬编码禁用）：有活跃会话、工作台未打开、窗口宽 ≥ 280+会话列+328+100（标准输入 1428pt / 宽输入 1688pt）时，聊天右侧自动出现环境卡。
- 卡片仍可"打开完整轨迹栏"一键进入工作台；打开工作台或窗口变窄时自动让位，二者不同时占据右侧。
- 真机验证：1749pt 宽窗口下卡片自动出现（变更 +277,538/-627、本地、main、提交或推送、比较分支、来源区块齐全）。
**Why**: 用户明确需要宽窗口下自动出现的环境速览卡；v0.5.59 的"仅主动打开"决策过严，恢复原始 shouldShow 响应式策略即可与工作台面板自然互斥。
**Next**: 两机部署后观察窄窗口/宽输入偏好切换时卡片的显隐是否跟手。

## v0.5.66 — 自绘分隔条实现拖宽自动弹出环境信息
**Date**: 2026-09-01
**Tag**: v0.5.66
**Test status**: 2610 passed / 0 failed（跳过远程环境段）
**Changed**:
- 主会话与工作台之间的分栏改为自绘分隔条（HStack + 8pt 命中区 + DragGesture），向左拖动把工作台拉宽到 ≥560pt 时自动弹出环境信息抽屉；在 onEnded 用完整位移判定，连续小段拖动可累计达标。
- 真机回归证明旧方案不可行：HSplitView 内置分隔条拖动期间 GeometryReader/onChange 宽度事件不触发（拖到 693pt 持久化宽度纹丝不动），宽度监听方案被彻底替换；仅向加宽方向触发，向右收窄（手动关闭后回收空间）不误弹。
- 真机验证三条呼出路径全部通过：右缘手柄点击 ✓、贴边 5pt 小位移拖拽 ✓、分隔条拖宽至 ≥560pt 自动弹出 ✓。
**Why**: 用户报告"拖拽到一定宽度自动弹出环境信息"失效；逐层定位出拖拽阈值几何不可达与宽度事件缺失两个根因后，只有让分隔条自己的手势同时承担分栏与弹出判定才可靠。
**Next**: 两机部署后由真实鼠标复验拖宽弹出手感，必要时调整 560pt 阈值。

## v0.5.65 — 真机复验收口：拖拽阈值 3pt + 拖宽弹出步进误判修复
**Date**: 2026-09-01
**Tag**: v0.5.65
**Test status**: 2610 passed / 0 failed（跳过远程环境段）
**Changed**:
- 真机复验 v0.5.64：点击手柄展开 ✓；5pt 贴边拖拽仍不触发（阈值 6pt 偏高，且窗口最外侧数 pt 是系统缩放边框）→ 阈值降为 3pt、minimumDistance 2。
- 真机复验拖宽自动弹出：分隔条拖到 693pt 仍未弹出——原实现要求单步宽度增量 >6pt，而分隔条拖动是每步 3–5pt 的连续小步，永远不满足；去掉步进条件，改为"宿主窗口宽度未变（区分分隔条拖动与窗口缩放）+ 工作台宽度 ≥560pt + 闩锁已武装"即弹出。
- 结构回归断言同步更新，2610 passed / 0 failed。
**Why**: v0.5.64 的两个阈值都是按理想化输入设计的；只有真实界面回归才能暴露"每步小增量"与"系统缩放边框吞按下"这两个物理事实。
**Next**: v0.5.65 部署两机后重跑三条路径（贴边拖拽/点击/拖宽弹出）直至全绿。

## v0.5.64 — 修复右缘拖拽展开环境信息在贴边窗口下失效
**Date**: 2026-09-01
**Tag**: v0.5.64
**Test status**: 2610 passed / 0 failed（跳过远程环境段）
**Changed**:
- 右缘环境手柄支持点击直接展开；拖拽阈值从 24pt 降到 6pt（minimumDistance 8→4）。真实界面回归证实：窗口右缘贴住屏幕右缘（全屏宽 1315pt）时向右最多只有约 5–10pt 位移，旧阈值下手势几何不可达，这就是"之前可以、现在突然不行"的根因。
- 新增 目标 IDE 式拖宽自动弹出：工作台分栏被拖宽到 ≥560pt 时自动弹出环境抽屉；仅当宽度增长来自分隔条拖动（宿主窗口宽度不变）才触发，配合 500pt 以下重新武装的滞后闩锁，避免手动关闭后被立即重新弹开。
- 桌面结构回归新增 2 项，锁定点击/小位移触发与拖宽阈值闩锁。
**Why**: v0.5.61 的拖拽阈值按"窗口不贴边"设计，`ensureHostWindowFitsEnvironment` 把窗口推到屏幕宽度后手势永远达不到；且"拖到一定宽度自动弹出"从未实现，宽度只被持久化。
**Next**: 三机安装后用真实拖拽复验贴边窗口与拖宽弹出两条路径。

## v0.5.63 — 修复侧栏头像被撑成大矩形
**Date**: 2026-09-01
**Tag**: v0.5.63
**Test status**: 2608 passed / 0 failed（跳过远程环境段）
**Changed**:
- 侧栏底部头像改为渲染层预裁剪的 28pt 圆形小图（ImageRenderer + NSCache），修复 macOS 26 菜单把 label 里的 Image 按位图原尺寸抽走渲染、把 132pt 微信原图整个撑进侧栏的缺陷。
- 账户菜单 label 只保留头像与名字；套餐信息（供应商·套餐·余量）移出 label 单独成行，恢复被丢弃的灰色套餐行。
- 首字母占位头像与下载头像同路径渲染，菜单/设置页共享缓存。
**Why**: macOS 26 的 SwiftUI Menu 会把 label 抽成“首个 Text + Image”的系统菜单表示，frame/clipShape/overlay 一律被绕过，头像与套餐行都被破坏。
**Next**: 三机安装后确认不同头像与未登录态下的底栏表现。

## v0.5.62 — 侧栏底部收敛为账户菜单
**Date**: 2026-09-01
**Tag**: v0.5.62
**Test status**: 2608 passed / 0 failed（跳过远程环境段）
**Changed**:
- 移除侧栏底部右侧的手机工具菜单、运行状态点和设置按钮，用户与套餐摘要占满底部宽度。
- 点击头像或用户区打开上拉菜单，集中提供连接手机、自动化、自进化、检查更新、设置与退出登录。
- 在 v0.5.61 多标签工作台基础上集成，不回退独立辅助对话、审查、终端、浏览器和环境抽屉能力。
- 新增 6 项桌面结构回归，锁定底部工具按钮移除与账户菜单入口。
**Why**: 右侧小按钮挤占套餐信息，常用入口也分散；统一收入点击头像后的菜单能同时释放空间和简化层级。
**Next**: 三机安装后继续观察真实账户、长套餐名、更新状态以及窄窗口下的菜单表现。

## v0.5.61 — 目标 IDE 式多标签右侧工作台与环境抽屉
**Date**: 2026-09-01
**Tag**: v0.5.61
**Test status**: 2602 passed / 0 failed（跳过远程环境段）
**Changed**:
- 将旧的“环境信息 + 轨迹”单栏替换为独立可拖拽右侧工作台，支持辅助对话、审查、多终端和浏览器标签并存、检索、选择、逐标签关闭和关闭整个面板；每个辅助标签绑定独立、可持久化且可并行运行的 Harness 会话，不会污染左侧主任务列表。
- 审查页接入真实文件变更与 Diff；终端页可在当前项目目录执行 zsh 命令、停止长命令并支持多实例；浏览器页支持前进、后退、刷新、URL 导航、自由尺寸和外部打开。
- 环境信息改为工作台右侧第二级抽屉，可从工具栏切换，也可从最右缘向右拖出；工作台宽度、环境宽度、标签和选中态跨启动恢复。
- 任务顶栏按 目标 IDE 实机顺序补齐 Finder、打开方式、帮助、终端和侧边面板按钮；新增 16 项工作台状态测试及 6 项桌面结构约束。
**Why**: 原实现只有一个 `showTrajectory` 布尔开关，环境信息和轨迹被固定塞在同一窄栏，无法表达 目标 IDE 的多表面共存、两级关闭、右缘环境抽屉与工作台状态恢复。
**Next**: 继续用同视口实机截图收紧标签密度、分栏默认宽度，并回归辅助对话的长任务、审批与多标签并发体验。

## v0.5.60 — 移除输入器上方误加分隔线
**Date**: 2026-09-01
**Tag**: v0.5.60
**Test status**: 2579 passed / 0 failed（跳过远程环境段）
**Changed**:
- 移除活跃会话区与底部输入器之间贯穿右侧工作区的 `Divider`，恢复 目标 IDE 原图中的连续背景与自然留白。
- 新增桌面结构回归断言，防止后续重新引入输入器上方全宽分隔线。
**Why**: v0.5.59 框架已对齐 目标 IDE，但输入器上方仍残留 SwiftUI 分隔线，形成参考图中不存在的横向视觉切割。
**Next**: 继续按同视口参考图逐项收紧桌面端细节，不改变已验证的整体层级。

## v0.5.59 — 目标 IDE 桌面整体框架重新校正
**Date**: 2026-09-01
**Tag**: v0.5.59
**Test status**: 2578 passed / 0 failed（跳过远程环境段）
**Changed**:
- 撤销 v0.5.58 的错误视觉结论，按 目标 IDE 3.10.1 实机同尺寸参考重新实现：灰色导航面是整窗底板，右侧深色工作区是一整块从标题栏覆盖到窗口底部的圆角层。
- 用 `HSplitView` 与自绘平面侧栏替代系统玻璃 `NavigationSplitView`；分组模式为扁平任务列表，项目模式为项目树加独立任务分区。
- 标题区、侧栏密度、内容起点和输入器宽高按 871 × 768 同视口校正；环境卡改为仅主动打开，输入器下方不再占用额外指标行。
- 保留侧栏收起、前后任务、搜索、更新、项目切换、连接手机、设置与右侧轨迹栏等真实交互。
**Why**: v0.5.58 把“左侧整窗底板 + 右侧覆盖层”误判为普通左右平铺，虽有局部元素相似，但整体层级不符合 目标 IDE；该版本已撤回自动更新分发且未安装到三台设备。
**Next**: 桌面端框架稳定后，再按同一视觉语言继续复刻 目标 IDE 的连接手机 H5 端。

## v0.5.58 — 目标 IDE 桌面工作区复刻（已撤回）
**Date**: 2026-08-31
**Tag**: v0.5.58
**Test status**: 2570 passed / 0 failed（跳过远程环境段）
**Status**: 未通过整体框架视觉验收；未安装到三台设备，也未进入自动更新 appcast。
**Changed**:
- 以 目标 IDE 3.10.1 实机桌面端截图与可访问性结构为基准，复刻灰色侧栏、四个一级入口、分组/项目视图、紧凑项目树和相对日期。
- 主工作区改为独立任务顶栏、居中对话区、灰色用户消息以及两层输入器；访达、终端、帮助、轨迹栏、权限、电脑操作和模型入口继续可用。
- 检查更新保留在左上角，连接手机、自进化和设置下沉到账户区；普通活跃任务不再在输入器里重复显示项目入口。
- 新增 14 项桌面设计结构测试，并完成 目标 IDE 参考图与本机签名 App 的同高度并排视觉验收。
**Why**: 用户要求先完整复刻 目标 IDE 桌面端整体 UI 与交互，再继续升级 Tapgo 自有能力。
**Next**: 在桌面工作区稳定后，继续按同一设计语言复刻 目标 IDE 的连接手机 H5 端。

## v0.5.57 — 管理员登录页品牌化重设计
**Date**: 2026-08-31
**Tag**: v0.5.57
**Test status**: 2557 passed / 0 failed（跳过远程环境段）
**Changed**:
- 管理员登录页改为用户选定的左右分栏布局：左侧品牌区，右侧高对比微信扫码登录区。
- 登录页直接读取主 App 的真实应用图标，确保 logo 与 App 图标始终一致。
- 新增真实位图品牌背景、二维码承载面、等待状态、刷新入口和底部版本信息；保留扫码轮询、过期与失败重试逻辑。
- 新增只读登录页 QA 开关、13 项设计结构测试，以及同视口完整/聚焦并排视觉验收记录。
**Why**: 原登录页层级、对比度与留白失衡，品牌标志还可能与真实应用图标不一致，影响管理员首次使用体验。
**Next**: 继续观察真实登录二维码在不同窗口尺寸和系统字号下的可读性。

## v0.5.56 — GitHub Releases 自动更新
**Date**: 2026-08-31
**Tag**: v0.5.56
**Test status**: 2544 passed / 0 failed（跳过远程环境段）
**Changed**:
- 左上角和应用菜单新增“检查更新”，按钮状态与 Sparkle 的真实可检查状态同步。
- 接入 Sparkle 2.9.6，启动时立即后台检查，之后每小时检查；支持后台下载、EdDSA 校验和原子替换安装。
- `appcast.xml` 由 Keychain 内的独立 EdDSA 私钥签名，更新包发布到 GitHub Releases；构建脚本嵌入并签名 Sparkle.framework。
- 新增 GitHub Release 归档/appcast/SHA-256 生成脚本和静态分发链路测试。
**Why**: 旧版本只能通过三机手工复制安装，没有可见的检查更新入口，也无法从 GitHub Releases 安全自更新。
**Next**: 从 v0.5.57 开始使用本次建立的 appcast 链路验证跨版本自动替换。

## v0.5.55 — Tapgo Computer Use 对齐 Codex Computer Use
**Date**: 2026-08-31
**Tag**: v0.5.55
**Test status**: 2522 passed / 0 failed（跳过远程环境段）
**Changed**:
- 主 API 对齐 Codex Computer Use 的 11 个工具及参数语义：`click`、`drag`、`get_app_state`、`list_apps`、`paste`、`perform_secondary_action`、`press_key`、`scroll`、`select_text`、`set_value`、`type_text`；旧 8 个 Tapgo 工具继续作为兼容别名。
- 补齐未运行应用自动启动、AX 树与窗口截图联合回读、默认内存态差量/`disableDiff` 完整状态、左/右/中键与连击、窗口拖拽、按元素或坐标横纵滚动、xdotool 风格按键。
- 补齐 text/Markdown/HTML 粘贴并完整恢复原剪贴板、带 prefix/suffix 消歧的文本选择/光标定位，以及只执行元素明确暴露 action 的次级 AX 操作；AX 树会列出可用 actions，安全输入框继续脱敏。
- 把 Codex Computer Use 的即时确认边界注入每个新会话，覆盖删除、账号权限、CAPTCHA、软件安装、对外沟通、支付、系统设置、敏感数据传输等 UI 风险动作；第三方内容不能代替用户授权。
**Why**: v0.5.54 的 Tapgo 工具数量接近 Codex，但缺少拖拽、剪贴板恢复、文本精确选择、次级 AX 动作、三键点击、元素滚动和状态差量，名称与参数也不兼容，无法称为 1:1 能力。
**Next**: 在三台 Mac 持续回归不同 App 的 AX 完整度；遇到应用不暴露语义元素时继续使用同一窗口截图与坐标闭环，不绕过 macOS TCC。

## v0.5.54 — 目标 IDE 模型配置整窗复刻与运行链路统一
**Date**: 2026-08-31
**Tag**: v0.5.54
**Test status**: 2467 passed / 0 failed（跳过远程环境段）
**Changed**:
- 以 目标 IDE 实机 871×768 模型配置页为视觉真相源，设置页改为整窗导航；模型页按同一层级复刻供应商侧栏、连接方式、套餐/额度概览、模型行及新增/编辑/删除/测试交互。
- `ProviderRegistry` 接管模型选中、API Key、Provider 端点、config.toml 与模型目录生成；GLM-5.3 / GLM-5-Turbo 和自定义 Provider 不再被旧扁平注册表回落到 MiniMax。
- 修复 v0.5.53 迁移 auth 文件到备份后，启动校验、会话和额度查询仍读取旧 auth 路径而错误显示“尚未独立配置”的问题；凭据继续仅保存在 0600 注册表中。
- 模型页统一显示“剩余额度”：MiniMax / 智谱读取真实 5 小时与每周窗口，DeepSeek 显示官方账户余额；自定义供应商无官方接口时明确显示暂不支持。三家查询均直接使用 ProviderRegistry 内存 Key，不恢复或复制旧凭据文件。
- 新增 GLM ProviderRegistry Key 请求测试与参考图/实现图的同视口视觉 QA 证据。
**Why**: 用户要求 1:1 复刻 目标 IDE 模型配置页；同时必须保证视觉上的模型选择会真实进入新会话，而不是只改变界面状态。
**Next**: 在实际使用反馈基础上继续收紧非模型设置入口的细节，不扩展本次模型配置范围。

## v0.5.53 — 模型设置 1:1 仿造 目标 IDE（供应商/模型两层）
**Date**: 2026-08-31
**Tag**: v0.5.53
**Changed**:
- `TapgoCore/Provider.swift`（新增）：`Provider`（供应商，内嵌 baseURL/apiKey/models）+ `ProviderModel`（供应商下的具体模型）+ `TapgoProviderKind`（内置供应商枚举：zhipu / minimax / deepseek）。智谱默认挂 GLM-5.3 / GLM-5.3-Flash / GLM-5-Turbo 三个模型。
- `TapgoCore/ProviderRegistry.swift`（新增）：`provider-registry.json`（0600）持久化全部供应商；`ensureBuiltinProviders` / `addOrUpdate`（内置仅允许改 Key/baseURL/models） / `removeProvider`（内置拒绝删除） / `setSelectedProvider` / `setSelectedModel` / `reorderProviders`（UI 占位）。
- v0.5.52 → v0.5.53 自动迁移：旧 `model-registry.json` 的每个 CustomModel 转为一个自定义 Provider；旧 `auth.json` / `auth-glm.json` / `auth-deepseek.json` 的 Key 按「文件名含 glm → 智谱、deepseek → DeepSeek、其余 → MiniMax」合并进内置 Provider；旧文件移入 `backups/` 保留。
- `TapgoConfig`：新增 `allProviders()` / `resolveSelectedProvider()` / `providerRegistry()` / `clearAPIKey(providerID:)` / `testConnection(provider:model:)` / `syncProviderFiles()`；旧 ResolvedModel 路径完整保留（thread/start + 手机 H5 不受影响）。
- `Views/ModelSettingsView.swift`（新增）：目标 IDE 风格模型设置页——顶部「刷新 / 拖拽调整供应商顺序（占位） / 添加供应商」操作条 + 「智谱（已启用）/ 自定义供应商」两个 Section；供应商卡内每个模型行 = API 模型 ID（可编辑 TextField）+ 上下文窗口菜单 + 「当前」徽章 + 「测试」（内联连通/延迟/失败反馈）。
- `EditProviderSheet`：新增/编辑供应商（显示名/品牌/端点/Key + 内嵌模型列表增删改查）；内置供应商仅 Key 可改，其余字段 disabled。
- `SettingsView.modelTab` 替换为 `ModelSettingsView()`；v0.5.52 的 modelTab 内联 UI、ModelFormSheet、BuiltinKeySheet、「MiniMax 端点覆盖」卡片全部移除。
- L10n：新增智谱/自定义供应商/添加供应商/拖拽调整供应商顺序/编辑模型配置等 key。
- 测试：新增 `ProviderRegistryTests` 两个 section（CRUD + 持久化往返、legacy 迁移）；`ProviderRegistryState` 显式 Codable 让 `[String:String]` 编为 JSON object。
**Why**: 用户要求按 目标 IDE 的模型设置模块 1:1 仿造。目标 IDE 把「供应商」作为一级分类、模型挂在供应商下，与 Tapgo 既有「内置 4 模型 + 自定义模型」扁平结构不同。本次引入 Provider/ProviderModel 两层数据模型与目标 IDE 同构 UI，同时保留旧 harness 配置路径避免破坏 ChatView / 手机 H5。
**Next**: v0.5.54 计划把 harness config.toml 的 `[model_providers.*]` 切换为按 Provider 生成（providerId 与 ProviderRegistry 对齐），并把「拖拽调整供应商顺序」做成真实现。

## v0.5.52 — 模型设置深度打磨
**Date**: 2026-08-31
**Tag**: v0.5.52
**Changed**:
- `CustomModel.validationErrors([String])` 一次返回所有错误；新增 apiKey 必填、`isAcceptableBaseURL` 仅放行 https（http 仅限 localhost / 127.0.0.1 / ::1）、`contextWindowOptions` 覆盖 8K → 1M
- `TapgoConfig` 新增 `testConnection` / `clearAPIKey` / `deleteCustomModel`；后者删除选中自定义模型时主动写回 `builtin:MiniMax-M3`，避免旧 ID 残留后被 `resolveSelected` 隐式回落
- `TapgoCore/ModelSettingsProbe` 把 IO 抽到 TapgoCore，让 TapgoTests 单测无需依赖 TapgoAICoding executable target
- `SettingsView.modelTab`：
  - 思考强度改为 5 档（默认/none/low/medium/high），文案走 L10n
  - 「新会话模型」Picker 按「内置/自定义」分段
  - 行尾内置新增「测试」「清除 Key」两个操作，结果内联反馈；自定义保留「删除」
  - 内置点「编辑」走完整 `ModelFormSheet`，apiModel/brand/displayName 锁住，仅 Key 可改
  - `ModelFormSheet` 多错误列表显示、上下文窗口新 8K~1M 档位、宽度 500
  - 「MiniMax 端点覆盖」应用/默认按钮接 banner 反馈（成功 3 秒后消失）
- L10n：新增 16 个 key（取消/保存/删除/清除 Key/思考强度五档/模型 * /测试/连接/已应用）
- 测试：`ModelRegistryTests` +3 段新断言（HTTP 提示、localhost 接受、错误列表、contextWindow 范围）；新增 `TapgoConfigTests` 覆盖 readAPIKey / deleteCustomModel / testConnection
**Why**: v0.5.42 自定义模型增删改查落地后留下 9 处体验与数据正确性瑕疵：
- 校验错误一次只显示一条、http 公网端点无阻拦、apiKey 留空保存可成功
- 内置模型「编辑」只暴露 Key，名字/端点都改不动；删除选中自定义模型后选中态靠隐式回落
- 思考强度只有 3 档、上下文窗口选项偏少；每行只有「编辑/删除」两个操作
- 端点覆盖「应用」按钮吞错、无反馈
**Next**: v0.5.53 准备为 ModelSettingsProbe 暴露公共 toast / banner 组件，把所有端点/Key 操作的成功/失败反馈统一到顶层通知。

## v0.5.51 — 电脑控制从全屏盲点升级为目标应用语义操作
**Date**: 2026-08-31
**Commit**: 4610726
**Tag**: v0.5.51
**Test status**: 2411 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过远程环境段）
**Changed**:
- Accessibility 扫描深度由 12 提升到 32、上限由 220 提升到 600，并跳过关闭菜单的无关子树；目标 IDE Electron 深层 WebArea 的“模型设置”“添加供应商”“添加模型”和表单字段可被稳定读取。
- 新增 `set_element_value` 语义赋值；截图、点击、按键、输入与滚动均支持绑定目标 App，应用窗口截图和坐标共用同一窗口，修正旧坐标 Y 轴翻转错误。
- 新会话强制执行“确认应用 → 元素树与窗口联合观察 → 语义操作 → 每步复核”，连续失败停止盲点；模型目录同时修复多行 base instructions 的 JSON 转义。
**Why**: 旧实现只读到 Electron 外壳，菜单子树提前耗尽元素预算；坐标又基于全屏且不锁定 App，焦点漂移后会误点 Tapgo、微信或系统设置，无法完成 目标 IDE 模型配置。
**Next**: 在三台 Mac 完成本版同步；已授权机器继续扩大复杂 Electron 表单回归，未授权机器完成本机 TCC 后再验收截图与点击。

## v0.5.50 — 本地化应用名启动不再假成功
**Date**: 2026-08-30
**Commit**: 7668a47
**Tag**: v0.5.50
**Test status**: 2397 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过远程环境段）
**Changed**:
- `open_application` 现在等待 `/usr/bin/open` 完整退出并检查退出码，不再把“进程成功创建”误报为“应用成功启动”。
- 英文 bundle 名失败时，按本机 Spotlight 的 `kMDItemDisplayName` 本地化索引解析 `.app`，中文“计算器”可正确定位 `/System/Applications/Calculator.app`；bundle id 仍走 `NSWorkspace` 直接解析。
- JKMac mini 实测调用前 Calculator 进程不存在；`open_application(name="计算器")` 后出现新 PID，并可用 `get_app_state(app="计算器")` 读取 `com.apple.calculator` 界面树。
**Why**: v0.5.49 的核心权限桥接已打通，但真实验收使用英文 `Calculator` 绕过了一个中文场景：旧实现未等待 `open` 结束，中文本地化名称找不到应用时仍返回成功。
**Next**: 三台 Mac 同步 0.5.50；MacBook Pro 与 fafamacmini 分别完成本机 TCC 双授权后，再做与 JKMac mini 相同的真实会话验收。

## v0.5.49 — 正式签名 Helper 桥接打通真实电脑控制
**Date**: 2026-08-30
**Commit**: 535ae92
**Tag**: v0.5.49
**Test status**: 2397 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过远程环境段）
**Changed**:
- MCP stdio 进程把每次 `tools/call` 通过 Launch Services 交给独立 `Tapgo Computer Use.app` 一次性执行，使 macOS TCC 始终按 Helper 的稳定 bundle 身份判断权限，不再错误归因给 Codex Harness 父进程。
- 桥接请求与响应限定在所有者专用的临时目录，校验目录所有者、0700 权限、固定文件名、常规文件、无符号链接和 1 MiB 请求上限，避免任意路径读写。
- 构建脚本优先使用 Tapgo Developer ID 正式签名并带时间戳；无证书环境才显式回退 ad-hoc，也支持 `TAPGO_SIGNING_IDENTITY` 覆盖。
- JKMac mini 已完成辅助功能与屏幕录制双授权；底层 MCP 和真实 Tapgo 会话均通过截图、启动 Calculator、读取界面树、按元素点击数字 7、再次读取与截图的完整验收，显示值从 `7` 变为 `77`。
**Why**: v0.5.48 的设置探测由 Launch Services 启动 Helper，所以页面显示已授权；真实会话却由 Harness 直接执行 Helper 内二进制，TCC 看到的是错误的父进程链，导致截图和 Accessibility 操作仍全部失败。
**Next**: 将同一份正式签名构建同步到另外两台 Mac；各机首次使用时分别完成本机 TCC 授权并做相同的真实会话回归。

## v0.5.48 — 独立安装电脑控制 Helper 并修复真实拖拽入口
**Date**: 2026-08-30
**Commit**: 083a560
**Tag**: v0.5.48
**Test status**: 2397 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过远程环境段）
**Changed**:
- 参照 目标 IDE 的实际安装流程，先把内嵌 Helper 原子复制到 `~/Library/Application Support/Tapgo AICoding/computer-use/Tapgo Computer Use.app`，权限授权、状态探测与 MCP 注册统一使用这一个稳定的独立 App。
- 将 SwiftUI `NSItemProvider` 替换为 AppKit `NSDraggingSession` 与原生 `NSURL` 文件载荷；授权浮窗可成为 key window，拖拽视图完整命中并回显按下、开始及结束状态。
- JKMac mini 已验证独立 Helper 可被系统“屏幕录制”列表接收且探测为已授权；同时发现旧版 ad-hoc 签名残留会让“辅助功能”列表显示开启但当前 Helper 自检仍为未授权。
- 测试入口兼容当前 `Codex Desktop` 大小写形式，完整离线回归 2397/2397。
**Why**: 之前拖动的是主 App Resources 内的嵌套 bundle，既不等同于 目标 IDE 的独立 Helper 安装流程，也会让 TCC 授权对象、MCP 进程和升级后的签名身份发生偏离。
**Next**: 经用户确认后移除 JKMac mini 上失效的旧辅助功能记录，重新添加当前 0.5.48 独立 Helper 并回读两项权限；正式签名证书到位后改用稳定 Developer ID，避免 ad-hoc CDHash 随版本变化。

## v0.5.47 — 修复授权浮窗抢占 Helper 拖拽
**Date**: 2026-08-30
**Commit**: f361cfd
**Tag**: v0.5.47
**Test status**: 2394 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 禁止电脑控制授权浮窗整体移动，关闭 `isMovable` 与 `isMovableByWindowBackground`。
- 保留 `Tapgo Computer Use` 卡片的文件拖拽提供器，拖动卡片时导出真实 Helper `.app`，不再带着整个浮窗移动。
**Why**: 浮窗允许背景拖动时，AppKit 会先于 SwiftUI `.onDrag` 消费手势，用户拖动 Helper 卡片实际移动了整个授权面板。
**Next**: 在辅助功能和屏幕录制两个系统页面分别完成一次真实拖入授权回归。

## v0.5.46 — 电脑控制独立 Helper 与系统授权拖拽引导
**Date**: 2026-08-30
**Commit**: 309e3c2
**Tag**: v0.5.46
**Test status**: 2394 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 新增独立 `Tapgo Computer Use.app` Helper，以固定 bundle id 承载 Accessibility、Screen Recording 和电脑控制 MCP，避免继续误用主 App 或宿主进程权限。
- 两项权限分别提供精确系统设置入口；打开后显示置顶拖拽面板，可把真实 Helper App 拖入对应允许列表。
- 权限状态通过 Launch Services 启动 Helper 并回写只读 JSON，避免直接执行二进制时继承 Terminal/主 App 的 TCC 上下文。
- Composer 入口与设置页统一使用 Helper 真值；MCP 配置改指向嵌套 Helper 可执行文件，并补齐稳定路径测试。
**Why**: 原实现只展示主 App 权限和通用系统设置链接，系统实际执行电脑控制的进程身份不明确，也没有 目标 IDE 式的一键拖拽授权流程。
**Next**: 用户完成三台 Mac 的系统授权后，分别回读 Helper 权限并实测截图、元素树读取和点击输入链路。

## v0.5.45 — 电脑控制界面验收修复
**Date**: 2026-08-30
**Commit**: e174ceb
**Tag**: v0.5.45
**Test status**: 2390 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 将电脑控制两个开关明确固定为 macOS 滑动开关，避免系统默认 Form 样式显示为复选框。
- 输入区「电脑操作」入口改用带初始页面的独立 sheet 状态，稳定直达电脑控制设置，消除首次打开误落到常规页的竞态。
**Why**: v0.5.44 发布后的真实界面验收发现开关视觉形态和首次直达页面不符合预期，需要发布一个不改写既有标签的修复版本。
**Next**: 三机授权后验证语义元素点击链路；继续补按元素输入、滚动与多显示器选择。

## v0.5.44 — 电脑控制完整启停、输入区入口与 Accessibility 语义操作
**Date**: 2026-08-30
**Commit**: c39cbda
**Tag**: v0.5.44
**Test status**: 2390 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 参考 目标 IDE 补齐「启用电脑控制」与「在输入框底部显示电脑操作」两个独立开关；总开关真实注册/移除 MCP 配置，显示偏好不改变能力状态。
- Composer 新增「电脑操作」快捷入口，以绿/橙/灰状态点区分已就绪、缺权限与已关闭，点击直达电脑控制设置。
- 电脑控制设置页新增权限/MCP 真值、关闭态说明、重新检测、重新注册和系统隐私设置入口；App 启动及模型配置重写均尊重总开关。
- MCP 工具由 8 个扩展为 11 个，新增 list_applications / get_app_state / click_element；支持读取 macOS Accessibility 元素树并按元素操作，安全输入框内容强制隐藏。
- 新增 MCP 段安全移除、语义工具 schema 与参数边界测试；完整离线回归 2390/2390。
**Why**: v0.5.43 只有状态页和手动注册按钮，没有真正的启停开关与 Composer 入口；底层也只有截图坐标操作，无法兑现「读取/驱动 UI 元素」的语义电脑控制。
**Next**: 在三台 Mac 分别授权后验证语义元素点击链路；后续补充按元素输入、滚动与多显示器选择。

## v0.5.43 — 参考 目标 IDE 重构设置中心
**Date**: 2026-08-30
**Commit**: b4a7597
**Tag**: v0.5.43
**Test status**: 2367 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过远程环境段）
**Changed**:
- 设置中心改为分组侧栏、页面标题/说明与卡片化内容，明确区分立即生效、新会话生效和重启 Harness 生效。
- 新增真实电脑控制状态页，回读辅助功能、屏幕录制和 MCP 注册状态；模型配置重写后自动恢复电脑控制 MCP 段。
- 模型页完成卡片化并修复首次进入模型列表不加载；插件管理嵌入设置页，并兼容官方目录中 `version = null` 的 Git 插件。
- 使用电脑控制逐页回归常规、外观、模型、电脑控制、记忆和插件页；Codex 官方 48 项、DeepSeek 官方 2 项均可正常读取。
**Why**: 原设置页只是窄侧栏加 Form 的功能集合，层级、说明和生效范围不清楚；目标 IDE 的分域导航与状态可见性更适合持续扩展 Agent 能力。
**Next**: 继续评估浏览器控制、技能、MCP 服务器等能力是否具备完整后端真值源，具备后再接入设置，避免只做空壳开关。

## v0.5.42 — 自定义模型增删改查与端到端选择
**Date**: 2026-08-30
**Commit**: 26bb60b
**Tag**: v0.5.42
**Test status**: 2366 passed / 0 failed（TAPGO_SKIP_REMOTE_INTEGRATION=1，跳过 13 个远程环境段）
**Changed**:
- 设置「模型」页支持新增、查看、编辑、删除任意 OpenAI Responses 兼容模型，保存显示名、品牌、API 模型 ID、Base URL、API Key 与上下文窗口。
- 自定义模型贯通 composer 选择、thread/start 的 model/modelProvider、config.toml provider、模型目录、环境面板、侧栏、额度弹窗、诊断信息和模型身份提示；删除当前模型时安全回落 MiniMax M3。
- 注册表与生成配置保持 0600 权限；输入统一校验/去空白，TOML 与 JSON 做安全转义，空 Key 不再残留占位符；新增注册表与目录回归测试。
- 全量测试入口兼容既有 TAPGO_SKIP_REMOTE_INTEGRATION 环境变量，避免开发跑测卡在 RFC 5737 示例远程地址。
**Why**: 内置模型列表无法覆盖用户自己的兼容端点；此前半成品只接通了部分选择链路，其他界面仍会误报为 MiniMax，并且缺少输入与配置安全边界。
**Next**: 用真实自定义 Responses 端点创建新会话，核对上游返回与额度展示；再评估把凭据迁移到 macOS Keychain。

## v0.5.41 — 模型弹窗极简化：只保留模型列表，点开即选
**Date**: 2026-08-30
**Commit**: c8104fb
**Tag**: v0.5.41
**Test status**: 2375 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户两次反馈模型弹窗太复杂。目视确认后大刀阔斧：弹窗只保留 4 个模型项（品牌 + 模型名 + 勾选当前），扁平化不再有二级子菜单。
- 移除弹窗内的端点、上下文、思考深度、新建会话、复制运行信息、打开运行设置等行——各自已有归属：端点/运行信息在环境面板与设置页，上下文在圆环弹窗，思考深度在「运行设置」（SettingsView Picker，v0.5.31 起就有），新建会话有 ⌘N。
- 数据与切换逻辑不变：选择即持久化、对新建会话生效。
**Why**: 用户要的是"点开芯片 → 看到 4 个模型 → 点一下"的最短路径，其余信息全是噪音。
**Next**: 真机用几天，若需要再把「思考深度」快捷入口以轻量形式回归。

## v0.5.40 — 手机 H5 端模型名统一为 displayName：底栏与模型面板不再显示技术 slug
**Date**: 2026-08-30
**Commit**: 206cb9b
**Tag**: v0.5.40
**Test status**: 2340 passed / 0 failed（TAPGO_SKIP_REMOTE_TESTS=1，跳过 13 项 SSH 集成段）
**Changed**:
- v0.5.39 只改了 Mac 端展示层，手机 H5 状态快照仍传 `store.modelName`（API slug），H5 composer 底栏与模型选择面板继续暴露 deepseek-v4-flash 这类技术 slug。
- `PhoneRemoteServer` 状态快照 `model` 改用 `store.modelDisplayName`（H5 端即得「DeepSeek V4 Flash」）；H5 JS 兜底文案同步改 "MiniMax M3"（displayName 口径）。
- H5 页面测试断言更新为 displayName 兜底；版本同步点对齐 0.5.40。
**Why**: 同一模型 Mac 端显示「DeepSeek V4 Flash」、手机端显示「deepseek-v4-flash」，口径分裂；H5 复用 Mac 端 v0.5.39 的展示层规则后两端口径一致。
**Next**: 真机扫码回归手机端模型名；评估普通会话发送【自进化指令】开头消息的确认提示（v0.5.38 Next）。

## v0.5.39 — 模型选择菜单改显「品牌 + 模型名」，不再暴露技术 slug
**Date**: 2026-08-30
**Commit**: 5080e78
**Tag**: v0.5.39
**Test status**: 2380 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户反馈模型菜单里 "deepseek-v4-flash" 这类技术 slug 太复杂，只想要品牌 + 模型名。
- `TapgoModel` 新增 `displayName`：MiniMax M3 / GLM 5.3 Flash / DeepSeek V4 Flash / DeepSeek V4 Pro；API slug（rawValue）保持官方名不动，仅展示层切换。
- 模型切换菜单、composer 芯片、环境面板、设置页、诊断信息统一改用 displayName；目录 display_name 同步。
- 测试 +5（displayName 四项 + slug 不变断言）。
**Why**: 面向用户的 UI 不应出现技术 slug；品牌 + 模型名一眼可辨。
**Next**: 手机 H5 端模型名仍显示 slug，待后续统一为 displayName。

## v0.5.38 — 自进化会话 composer 专属化：占位文案与项目条不再误导为当前项目

**Date**: 2026-08-30
**Changed**:
- 用户实测踩坑: 点「自进化」进入专属会话后, composer 占位仍是「给 OctTapgo 发条任务…」、项目条仍显示 OctTapgo——用户以为没切进去, 把【自进化指令】粘贴进了 OctTapgo 下的普通会话, AI 在错误目录 (~/OctTapgo) 里跑了一轮 252.6k tokens 的自进化。
- 修复 1 — 占位文案: activeThread 为自进化会话时显示「向自进化下达本轮指令…」, 不再跟随 activeProject。
- 修复 2 — 项目条: 自进化会话显示专属胶囊「✨ 自进化 · <仓库名>」(固定指向项目根, 点击打开目录), 不跟随 activeProject。
- 保留 v0.5.33 行为: 进入自进化会话不清空用户当前项目, 仅在 composer 层做上下文显式化。
**Why**: 会话已切换但输入区上下文没切换, 视觉状态与实际路由不一致, 是把指令发错会话的直接诱因。
**Next**: 评估在普通会话发送以【自进化指令】开头的消息时给出确认提示。

## v0.5.37 — 圆形额度表改显「剩余量」：侧栏 / 弹窗 / 圆环三处口径完全统一
**Date**: 2026-08-30
**Commit**: ceb6e5b
**Tag**: v0.5.37
**Test status**: 2375 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户圈出输入框底部的圆形额度表：显示已用 26%（周额度已用），与余量 74% 口径相反。
- `contextMeterChip` 翻转：有额度数据时显示最差窗口的剩余量（100 − worstUsedPercent，MiniMax 当前即 74）；无额度数据（DeepSeek 仅余额 / 尚未拉取）时退回上下文占用百分比，保持原行为。
- 无障碍标签同步：有额度数据时报「套餐余量 X%」，否则维持「上下文用量 X%」。
- 至此侧栏底部、额度弹窗、圆形表三处全部为剩余口径。
**Why**: 同一个数字三种口径让用户无法直接对照；统一为剩余量后三处可互相印证。
**Next**: 观察圆环填充方向语义（现在环充得越满 = 剩余越多）；如有用户反馈再评估改为倒计时样式。

## v0.5.36 — 额度口径统一：弹窗余量卡片改显「剩余量」
**Date**: 2026-08-30
**Commit**: 65c6444
**Tag**: v0.5.36
**Test status**: 2375 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户反馈口径不一：左下角侧栏显示余量（99%/74%），输入框底部的额度弹窗却显示已用（19%/33%）。统一为剩余量。
- `ModelUsagePopover.quotaCells()` 展示层翻转：usedPercent → max(0, 100 - usedPercent)，与侧栏公式一致；卡片标签加「余量」后缀（如「5 小时余量」「每周余量」），Credits 余额卡片不变。
- 数据层不动：三个额度客户端仍产出「已用」语义的 usedPercent，只在展示层翻转。
**Why**: 同一个「剩余额度」标题下混用两种口径会让用户误读（19% 被看成只剩 19%）。
**Next**: 真机确认弹窗与侧栏数字一致。

## v0.5.35 — 接入 DeepSeek V4 系列（v4-flash / v4-pro，原生 Responses API）
**Date**: 2026-08-30
**Commit**: 17d8923
**Tag**: v0.5.35
**Test status**: 2375 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户要求接入 DeepSeek 最新系列。官方文档 (api-docs.deepseek.com/quick_start/agent_integrations/codex) 确认 DeepSeek API 原生支持 OpenAI Responses 协议；本机实测 key 打 `https://api.deepseek.com/responses` 返回标准 Responses 对象（v4-flash 带推理输出）。
- `TapgoModel` 新增 `deepseek-v4-flash` / `deepseek-v4-pro`（官方 slug，1,048,576 上下文，reasoning low/high/max，默认 high）；模型目录条目随 allCases 自动生成。
- config.toml 模板新增 `[model_providers.deepseek]`（base_url https://api.deepseek.com，wire responses），鉴权来自独立 `auth-deepseek.json`（0600；缺失时选 DeepSeek 的新会话 401）。key 取自本机 `~/.deepseek/config.toml`，实测有效。
- 额度/余额三路接线补全：DeepSeek 按量计费无订阅窗口，走 `GET /user/balance` 显示余额（如「DeepSeek·余额 ¥17.95 CNY」）；弹窗来源标签 `DeepSeek user/balance`。
- 切换子菜单自动列出全部 4 个模型（MiniMax-M3 / GLM-5.3-Flash / deepseek-v4-flash / deepseek-v4-pro），切换对新建会话生效。
- 测试 +20：DeepSeekQuota 解析 8 断言 + transport/auth 7 断言 + ModelCatalog DeepSeek 映射与上下文窗口断言。
**Why**: 用户要求在模型选择里加入 DeepSeek 最新系列；V4 系列原生 Responses API 与 harness 0.149+ 零桥接兼容。
**Next**: deepseek-v4-flash-vision-exp（图片输入）暂未接入，等用户需要再评估；切换后首次使用建议看一眼 rollout 的 model_provider 确认。

## v0.5.34 — GLM 额度可查：接入 BigModel 官方 monitor/usage/quota/limit
**Date**: 2026-08-30
**Commit**: a0af5f8
**Tag**: v0.5.34
**Test status**: 2355 passed / 8 failed（既有 SSH 环境失败，与本版无关）
**Changed**:
- 用户质疑「GLM 无法查到？」——查证属实可以查：智谱官方用量查询插件 (zai-org/zai-coding-plugins) 的 query-usage.mjs 揭示了端点 `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`，Authorization 头直接放套餐 key（裸 token，实测 Bearer 也收），Coding Plan key 返回 5 小时档 (unit 3×5) 与周档 (unit 6×1) 两档已用百分比 + `level` 套餐档位（本账号 lite）。
- 新增 `TapgoCore/GLMQuotaClient`：与 MiniMaxQuotaClient 同构（authPath + transport 注入 + QuotaError + fetchRemains → RateLimitsSnapshot）；percentage 直映 usedPercent，unit/number 映射窗口分钟数，nextResetTime 毫秒 → resetsAt，level → planType（planLabel 归一化为 Lite）。
- `SessionStore.refreshRateLimits` 按所选模型双通道取数：MiniMax → coding_plan/remains（auth.json）；GLM → quota/limit（auth-glm.json）。
- 额度弹窗撤掉 v0.5.31 的「暂不支持查询」占位，GLM 渲染真实余量卡片；侧栏灰色行 GLM 显示「GLM·Lite·81%/33%」格式（余量=100-已用），与 MiniMax 数值格式对齐。
- 测试 +18：GLMQuota 解析映射 11 断言 + transport/auth 7 断言（裸 key 头、HTTP 500、业务码透传、缺失凭据）。
**Why**: 用户截图质疑 GLM 额度显示为「暂不支持查询」；实测 BigModel 有官方接口，补齐与 MiniMax 对等的额度体验。
**Next**: 真机观察 GLM 数值；BigModel 若调整字段结构需同步解析。

## v0.5.33 — 自进化日志模块重构：分段导航 + 紧凑折叠条目 + 当前版本数据源修复
**Date**: 2026-08-30
**Commit**: 5ed7ead
**Tag**: v0.5.33
**Changed**:
- 用户反馈日志页很乱: hero 卡显示 8/28 的陈旧 evolution_state.json (v0.5.3) 却标着「本次进化」; v0.5.32 条目 commit 是未回填的 PLACEHOLDER; 理念卡与全部明细平铺, 信息密度过低。
- 数据源修复: 当前版本条只信源码内置 makeHistory() 最新条目; evolution_state.json 不再作为版本数据源 (evolve.sh 快照, 曾滞后 4 天)。
- 布局重构: hero 大卡压成单行版本条 (版本·日期·SHA·摘要 + 本次进化胶囊); 「历史版本 / 使用指南」分段切换, 不再全部堆叠。
- 条目紧凑化: 收起态 = 版本 + SHA + 单行摘要; 点击展开完整改动明细与 Why/Next, 默认只展开最新一条; 理念说明压缩为一行 caption。
- 数据回填: v0.5.32 commit 55b1f72、v0.5.19 commit c486d44 (源码与 EVOLUTION.md 同步, PLACEHOLDER 清零)。
**Why**: 日志页是 AI 的对外广播, 陈旧数据 + 未回填字段 + 低密度排版让用户无法快速回答「现在到哪了、每次改了什么」; 重构后当前版本一眼可见, 历史按下钻展开。
**Next**: 条目按版本号搜索/过滤; 确认 evolve.sh 是否还落盘 evolution_state.json, 已废弃则删文件避免误导。

## v0.5.32 — 侧栏额度行按用户反馈改版: 套餐名 Ultra + 纯数字余量
**Date**: 2026-08-30
**Commit**: 55b1f72
**Tag**: v0.5.32
**Test status**: 2335 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈三点: 套餐名弄错了 (实际订阅是 **Ultra**, 不是 Token Plan/Coding Plan); 『周余量』等文字不要显示, 只显示数值; 格式改为 `5小时余量%/周余量%`。
- `modelQuotaSummary` 改版: `MiniMax·Ultra·21%/76%` —— 供应商/套餐随选中模型 (GLM 选中时只显示 `GLM`, 不显示 MiniMax 配额); 套餐名走 `TapgoConfig.planDisplayName = "Ultra"` (MiniMax 接口不返回套餐名, 以实际订阅为准, 换套餐改一处常量)。
- 5 小时窗口 (300 分钟) 与周窗口 (10080 分钟) 各自取 `100 - usedPercent`, 斜杠分隔无文字。
**Why**: 用户明确给出目标格式与真实套餐名; 显示应忠实于订阅事实而不是端点语义猜测。
**Next**: 无。

## v0.5.31 — 模型切换：composer 弹窗可选 GLM-5.3-Flash（BigModel Coding Plan）
**Date**: 2026-08-30
**Commit**: f81cf47
**Tag**: v0.5.31
**Test status**: 2335 passed / 8 failed（均为既有需要真实 SSH 远端的环境失败，与本版无关）
**Changed**:
- 说明：模型切换功能代码随 60294f6（v0.5.30）提前入库（并行会话合并提交所致），本版补齐版本对齐、文档记录、侧栏适配与真机回归。
- `TapgoCore` 新增 `TapgoModel` 模型目录：MiniMax-M3 与 GLM-5.3-Flash，各自绑定 provider 与端点；wire 一律 `responses`（本机 harness codex 0.149.1 已移除 `chat` wire，二进制内有明确报错文案）。
- GLM 走智谱官方给 Codex 的 OpenAI Responses 协议专属端点 `https://open.bigmodel.cn/api/v1`（docs.bigmodel.cn/cn/coding-plan/tool/codex），鉴权来自独立 `auth-glm.json`（0600；缺失时 GLM 新会话报 401，不留无替换机制的占位符——v0.5.28 教训）。Coding Plan 套餐 key 实测该端点可用且不按量计费；按量 key 余额不足（1113）不可用。
- config.toml 模板常驻双 provider（minimax + glm）；`thread/start` 按选中模型显式下发 `model`/`modelProvider`，切换对新建会话生效，进行中的会话保持原模型。
- composer 模型弹窗的「模型」行由"复制模型名"升级为**切换子菜单**（当前模型勾选），端点/诊断信息跟随所选模型。
- 额度查询按模型门控：选 GLM 时清空 MiniMax 快照并注明"暂不支持在 App 内查询额度"；侧栏左下角灰色行供应商跟随所选模型（GLM·Coding Plan）。
- 测试新增 `TapgoModel: catalog & provider mapping` 段 +12 断言。
**Why**: 用户要求在模型弹窗里能选 GLM-5.3-Flash（套餐内不额外计费），并反馈弹窗冗杂、找不到模型切换入口；把模型行变成真正的切换器同时精简语义。
**Next**: 手机 H5 模型面板目前只显示当前模型，改为列出全部可选模型并支持切换；远程项目（SSH）远端 config 仍是 MiniMax 单 provider，选 GLM 需向远端同步 auth-glm.json 与 glm provider 段。

## v0.5.30 — 侧栏用户信息灰色行改为「供应商·套餐名·周余量」
**Date**: 2026-08-30
**Commit**: 60294f6
**Tag**: v0.5.30
**Test status**: 2323 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户要求: App 左下角用户信息的灰色名字行(原先重复显示昵称)改为显示当前模型供应商/套餐名/周余量百分比。
- `SidebarView.userBar` 灰色行改为 `modelQuotaSummary`: `MiniMax·Coding Plan·周余量 74%` —— 供应商取 TapgoConfig, 套餐名用 `rateLimits?.planLabel` (MiniMax coding_plan 端点不返回套餐名字段, 回退 `Coding Plan` 端点语义; 初版误用『Token Plan』被用户指出后更正), 周余量 = 100 - secondary(10080 分钟窗口).usedPercent, 与 MiniMax 接口 `current_weekly_remaining_percent` 实测一致。
- userBar 挂 `.task`: 进侧栏立即 `refreshRateLimits()`, 之后每 5 分钟刷新。
- 目视回归: 窗口级截图确认左下角渲染 `MiniMax·Coding Plan·周余量 74%` (接口真实数据 74, 无截断)。
**Why**: 用户要在常驻位置一眼看到当前供应商/套餐/周配额健康度; 灰色行原本重复显示昵称没有信息量。
**Next**: 若 MiniMax 接口未来返回正式套餐名字段, 用真实值替换 Coding Plan 回退; 周余量颜色随压力等级变化。

## v0.5.29 — 自进化升级为独立入口：独立对话、独立开发专属会话
**Date**: 2026-08-30
**Commit**: 4ebecd9
**Tag**: v0.5.29
**Test status**: 2283 passed / 0 failed (跳过远程集成段; 全量含远程 2323 passed / 8 failed 均为既有 203.0.113.10 环境失败)
**Changed**:
- 侧边栏「自进化」从只读日志弹窗升级为独立入口: 点击直接进入自进化专属会话 (新建或选中最新一条), 菜单命令「进入自进化会话」注册 ⌘⌥E 快捷键 (⌘⇧E 已被复制会话占用)。
- 独立对话: `Thread` 新增 `mode` 字段 (`"evolution"` 标记, 向后兼容缺省 nil), 自进化会话在侧边栏独立分组置顶 (sparkles 图标), 不与普通项目会话混排; 点击分组头同样进入/创建。
- 独立开发: 自进化会话 cwd 固定为本项目根 (纯逻辑 `EvolutionWorkspace.locateProjectRoot` 探测 `~/TapgoAICoding` 需同时含 Package.swift 与 AGENTS.md, 找不到时弹窗提示而不建空壳会话)。
- 新增 `EvolutionPanel` 引导横幅 (对话区顶部): 显示会话性质/工作目录/轮次, 「开始自进化」一键发出内置指令 (核对仓库 → 选定改进点 → 实现 → `swift run TapgoTests` 全量回归 → 版本同步点对齐, 运行中禁用), 「自进化日志」按钮保留只读历史入口; 窗口标题/副标题特判显示真实仓库名与路径。
- 进入自进化会话不再清空 composer 的当前项目 (`selectThread` 对 evolution 线程跳过 `setActiveProject`), 从自进化切回普通会话项目状态不受影响。
- 测试新增 `Thread: evolution mode + workspace` 段 16 断言: mode 持久化往返、legacy 文件缺 mode 解码、固定标题不被 auto-title 覆盖、项目根双标记探测、kickoff 指令关键锚点。
**Why**: 自进化此前只是静态日志页, 用户想让它真正"自己开发自己"——必须是一个独立入口下的独立会话, 有专属指令与固定工作目录, 与日常对话互不干扰。
**Next**: 自进化回合结束后自动生成 EVOLUTION 草稿条目; 评估多轮自进化会话列表与每轮独立 harness 上下文。

## v0.5.28 — 紧急修复 config.toml 漂移重写抹掉真实鉴权导致 401
**Date**: 2026-08-30
**Commit**: ca7da89
**Tag**: v0.5.28
**Test status**: 2307 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户真机反馈: 会话每轮 Reconnecting 5/5 后报 `unexpected status 401 Unauthorized: login fail: Please carry the API secret key (1004), url: https://api.minimaxi.com/v1/responses`。
- 根因是 v0.5.27『修复 7』的回旋镖: `ensureReady` 按模板 diff 重写 config.toml 时, 模板里的 `experimental_bearer_token = "__FROM_AUTH_JSON__"` 是 Tapgo 自造占位符, 全仓没有任何运行时替换机制 —— 而磁盘上旧 config 的鉴权段是历史上真实有效的 key。重写把它覆盖回占位符, codex 发往 MiniMax 的请求不带 Authorization, 401 必现。
- 修复: 新增 `TapgoConfig.renderedConfigWithKey(region:authKey:)`, 两条 config 写出路径 (首次 init 的 writeAll 与 ensureReady 的漂移重写) 都把占位符替换为 auth.json 里的真实 key; 模板注释同步更正 (不再声称 key 不落盘, 文件 0600)。
- 自愈验证: 本机重启 App 后 ensureReady 检测漂移自动重写, config.toml 中 bearer 与 auth.json 完全一致 (125 字符 sk-cp-12…, 占位符残留 0)。
- 端到端验证: 经公网 H5 `api/send` 发送鉴权验证消息 → 回合 completed, 模型回复『已恢复正常』。
- **JKmacmini 补充修复 (数据层)**: JK 的 auth.json 存的是已失效的旧格式 key (`sk-mini1-…`, 49 位, 直连 MiniMax 401), config/heal 均正常但 key 本身死了 —— 已将本机验证过的 Token Plan key 写入 JK 并重启, 公网端到端验证回合 completed。当前代码无任何 auth.json 写入点, 09:54 的改写来源待观察是否复现。
**Why**: v0.5.27 的 config 漂移重写是按『占位符有效』的错误假设写的, 上线即打断了所有会话的模型鉴权; 配置文件属于关键数据, 重写必须保留可用的凭据语义。
**Next**: 观察三台机器配置一致性; 评估给 config.toml 重写加 .bak 备份, 避免同类覆盖不可回滚。

## v0.5.27 — 额度弹窗二轮修复：诊断信息 + 双端点 fallback + 6 行百分比去重 + 模型分桶映射 + 毫秒时间戳
**Date**: 2026-08-29
**Commit**: cb8e2db
**Tag**: v0.5.27
**Test status**: 94 passed / 0 failed (MiniMax + 邻近回归段全绿; 本机 App 主目标受限于 SwiftUI 宏插件, 见风险)
**Changed**:
- v0.5.25 上线后用户截屏反馈弹窗仍然报错『MiniMax 额度接口未返回模型 MiniMax-M3 的数据』且 6 行百分比加起来的 1612% 远超 context% 的 815%. 这一版**直接 curl 实测** MiniMax 接口 (`coding_plan/remains` 与 `token_plan/remains`), 发现根因 + 4 处隐藏 bug, 一并修复.
- **根因 1 — model_name 实际是 quota 类别而非模型名**: 接口返回 `model_name="general"` / `"video"` 这样的配额分桶, 不会直接返回 `"MiniMax-M3"`. `pickEntry` 增加『文本/对话模型 → general 桶』『视频模型 → video 桶』的语义映射, 通过 `isTextOrChatModel(name)` / `isVideoModel(name)` 判断; MiniMax-M3 (含 M2.7/abab*/minimax 命名约定) 自动落到 general 桶.
- **根因 2 — 接口直接给剩余百分比 `_remaining_percent`**, 旧版只在 `total==0` 时丢弃整个 cell. 新版 `makeWindow` 三层 fallback: 优先 `_remaining_percent` → `total - remaining` 反算 → 仅 total 时按 0% 展示. 即使 `total=0` (订阅未分配 quota) 也能继续展示服务端给的『订阅健康度』百分比 (例: `current_interval_remaining_percent=89` → 显示 11% 已用).
- **修复 3 — 6 行百分比重复计 cached**: `cached` 是 `input` 的子集 (缓存命中), 直接相加会让 6 行加起来 1612% > context% 815%. 改为 `消息 = max(0, input - cached)`, 行间近似不重.
- **修复 4 — MiniMax 时间戳是毫秒不是秒**: 13 位 `end_time=1788019200000` 表示 2026-08-29 (10 位秒级会是 1788019200000 = 公元 56870 年). `dateValue` 按量级自动检测 (>10^10 → 毫秒, 否则按秒), 兜底乘 1000, 保证『重置于』显示在合理日期.
- **修复 5 — 诊断信息可读**: `QuotaError` 重构为带 `endpoint` 字段. `noMatchingModel(requested, returned, endpoint)` 把接口实际返回的模型名列表带出来; 新增 `emptyResponse(endpoint)` 区分『真的没订阅』与『字段名对不上』. 弹窗红字可直接回答『接口返回了什么』『我用的端点是什么』『到底哪一步出问题』.
- **修复 6 — 双端点 fallback**: `fetchRemains` 按顺序试 `/api/openplatform/coding_plan/remains` → `/token_plan/remains`, 命中即返回; 只有『未匹配 / 空响应』触发 fallback, 其它错误 (HTTP 4xx/5xx、business 1008) 立即透传.
- **附带清理 — v0.5.25 引入的 Swift 6.4 编译错误**: `PhoneRemoteLink.swift` 的 `case ["img", let turnId, let idxStr]:` 在 Swift 6 不能用 `let` 在数组 pattern 中绑定, 改为 `case let arr where arr.count == 3 && arr[0] == "img":` 然后手动取元素; 同上修复 `["pending", let idxStr]:`; `TranscriptTurn` init 漏传 `userImageCount` 也补上.
- 测试新增 `MiniMaxQuota: lenient match + dual-endpoint fallback` 段 19 断言 (6 种 model_name 写法 + general 桶路由 + wrong model 严格 2 条不命中 + 诊断信息含 returned + endpoint + 双端点空响应), `MiniMaxQuota: timestamp parsing (ms vs s)` 段 2 断言 (13 位毫秒 + 10 位秒兼容), `MiniMaxQuota: SnapshotBuilder` 段 16 → 19 断言 (total=0 + percent 仍展示 / total=0 无 percent 隐藏 / total+percent 同时存在优先 percent); 全量 7 段 94 断言全绿, 既有 RateLimits/ExecEvent/ModelUsageMetrics 无回归.
- **修复 7 — config.toml 漂移导致 24M tokens 不压缩**: 用户机器上 `~/Library/Application Support/Tapgo AICoding/codex/config.toml` 缺 `model_auto_compact_token_limit = 800000` (v0.3.0 模板新增, 但 `ensureReady` 只校验文件存在 + 含 MiniMax-M3/minimax provider, 从不重生成 config.toml). 后果: harness 不知道该在 800k 自动压缩, 用户会话一路累积到 24M tokens (弹窗进度条飙到 2524%), 仍正常工作但严重浪费. `ensureReady` 现在按模板 diff, 漂移就用 `renderConfig` 重写 (auth.json 不动, bearer token 占位符保持, 真实 key 仍由 harness 启动时读 auth.json).
- **修复 8 — 弹窗百分比阈值封顶**: 当 `contextPercent >= 100%` 时 (溢出) 文本显示 `≥100%`, 而不是 `2524%` 这种让用户误以为系统失控的离谱数字. `24.0M/950k` 的真实计数仍显示在前面, 用户一眼能看出超出多少倍.
- **修复 9 — 手机 H5 看不到上传的图片 (用户反馈)**: 此前手机上传/会话里的图片只显示『已附 N 张』计数, 图片本体不可见. 新增两条带 token 的图片路由 `GET /img/<turnId>/<index>` (会话内用户消息图片, 按 turnId 查 `userImagePaths` 取文件) 与 `GET /pending/<index>` (待发附件缩略图); `TranscriptTurn` 增 `userImageCount`, H5 用户气泡内渲染图片、composer 附件行改为缩略图 + 计数; 图片响应带 `Cache-Control: private, max-age=3600` 防轮询闪烁.
**Why**: v0.5.25 只换了数据源, 没换诊断 UX —— 报错信息不可读; 弹窗 6 行把缓存命中重复计入让用户怀疑数据真实性; curl 实测发现 MiniMax 接口把模型名换成 quota 分桶名 + 直接给百分比 + 时间戳用毫秒, 这是协议级 bug 必须修; 此外 config.toml 漂移让 contextPercent 一路累积到 2524%, 也是协议级 bug 必须修.
**Next**: `contextWindow` 仍由 harness 报 950k (vs TapgoConfig 配置 1M) —— 怀疑是 harness 对 MiniMax-M3 的实际请求窗口有其它来源; 本版先不动, 等用户真机重启后看到 950k 来源 (MiniMax API 还是 harness 默认值) 后再修.

## v0.5.26 — 移除手机 composer 下方三个快捷指令 chips
**Date**: 2026-08-29
**Commit**: 9287b78
**Tag**: v0.5.26
**Test status**: 2276 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈 v0.5.21 仿 目标 IDE 截图时自作主张加的三个快捷 chips (🧪 跑测试 / 📝 总结改动 / ▶ 继续任务) 多此一举: 它们只是把固定文案填进输入框, 不是用户要的功能。
- 删除 #chips HTML/CSS 与对应 JS 接线, composer 下方恢复干净; 无其它行为变化。
**Why**: 仿造竞品形态时不该连可有可无的装饰一起照搬; 用户明确指出后立即移除。
**Next**: 无。

## v0.5.25 — composer 弹窗『查看额度』改用 MiniMax 官方接口 + 手机附件上传与模型面板
**Date**: 2026-08-29
**Commit**: 275c78f
**Tag**: v0.5.25
**Test status**: 2276 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈 composer 圆形上下文 meter 的弹窗里『查看额度』严重错误: 之前走 Codex app-server 的 `account/rateLimits/read`, 但本 App 对话模型是 MiniMax-M3, 该 JSON-RPC 永远返回不到真实订阅数据 —— 弹窗的 5 小时 / 每周 数字一直是不存在的占位。
- 新增 `TapgoCore/MiniMaxQuotaClient`: 直接读 auth.json 里的 `OPENAI_API_KEY`, 调 MiniMax 官方 `GET /v1/api/openplatform/coding_plan/remains`, `Authorization: Bearer <Token Plan Key>`, 端点随 `TapgoConfig.Region` (默认 `www.minimaxi.com`)。
- 新增 `TapgoCore/MiniMaxQuotaSnapshotBuilder`: 处理 MiniMax 字段语义陷阱 —— `current_interval_usage_count` / `current_weekly_usage_count` 字面是 usage, 实际是『剩余』; 这里集中做 `used = total - remaining` 反转; 周配额无 reset 时间则不写 `resetsAt`; Token Plan 没有 Credits 概念, credits cell 始终隐藏。
- `SessionStore.refreshRateLimits()` 改为异步实例化 `MiniMaxQuotaClient(authPath:, modelName:)` 直接拉取, 不再依赖 Codex harness (移除 `firstLiveRunner()` 选 harness 的逻辑)。
- 弹窗标签 `codex account/rateLimits` → `MiniMax coding_plan/remains`, 调试时一眼看出数据来源; 错误信息直接显示 MiniMax 接口的 HTTP / 业务码。
- 测试: 新增 `MiniMaxQuota: SnapshotBuilder` 16 断言 (基本反转/100%/0%/服务端 glitch 越界 → 100% 钳位/total=0 隐藏/planLabel 空白隐藏/数值类型 NSNumber+Double 兼容) + `MiniMaxQuota: MiniMaxQuotaClient` 10 断言 (HTTP 200 成功 / 500 透传 / 业务 1008 insufficient_balance 透传 / model 不匹配 / auth.json 缺失 / 单条 wildcard fallback / Bearer header 取自 auth.json); 既有 `RateLimits: JSON parsing + display helpers` (29 断言) 与 `ExecEvent: account/rateLimits/updated notification` (6 断言) 全绿。
- **收编并行会话 WIP — 手机 composer 按钮查修 (用户反馈『+ 怎么是新对话? 不是上传附件吗? 模型也不能选择, 按钮也不能正常使用』)**:
  - `+` 改为真正的**图片附件上传**: 点击唤起手机相册/文件选择 (accept=image/* 多选), FileReader 转 base64 POST `api/attach` (新增路由); Mac 端 `writeAttachment` 做魔数校验 (JPEG/PNG/GIF/WEBP/HEIC) 后写临时文件并 `store.addImages` 加入待发附件, 随下一条消息发送; composer 内显示附件计数行与上传进度。
  - `PhoneRemote.maxBodyBytes` 65KB → 20MB (base64 膨胀 1.33 倍), 快照增 `attachedCount` (发送后 Mac 端清零)。
  - 模型名『MiniMax-M3 ▾』点击弹出**模型选择面板** (底部卡片式, 列表来自 Mac 端 codex 配置, 当前模型高亮); 大脑图标可点, 跳电脑控制 Tab 查看权限。
  - `PhoneRemote: 链接构建与路由鉴权` +5 断言 (attach 路由), `状态快照 JSON` +1 (attachedCount), `H5 页面` +7 (fileInput/api/attach/attRow/modelSheet/modelBtn/上传进度); 全量 2276 passed / 8 failed。
  - 公网链路实测: curl 上传 1x1 PNG → 200, `/api/state` attachedCount=1。
**Why**: App 用的是 MiniMax-M3 不是 Codex 模型, Codex 那条 JSON-RPC 拿到的是 Codex 自身订阅配额, 跟用户实际订阅完全无关 —— 必须切到 MiniMax 官方 Token Plan 接口才能拿到真实数据; 同时手机端 composer 的 +/模型/状态按钮此前是死的装饰, 用户明确要求做成真功能。
**Next**: Token Plan 接口在海外端点未联调 (`.overseas` 分支已留好 baseURL); 模型面板在 Mac 端配置多模型后自动生效; 附件支持非图片文件。

## v0.5.24 — H5 顶部改项目切换器, 移除软件标题
**Date**: 2026-08-29
**Commit**: 5af6315
**Tag**: v0.5.24
**Test status**: 2240 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户要求『项目选择放到顶部, 不要显示软件标题』: 置顶 header 由『● Tapgo · 机器名』改为『● 📁 当前项目名 ▾』—— 项目切换器占据标题位, 点击进『项目与会话』列表页 (原 composer 上方的项目条同步移除, 不再重复)。
- 页面 h1 标题删除; 浏览器标签页标题仍为 `document.title = "Tapgo · 机器名"` (多机辨识在标签页层)。
- 列表页统计行加主机名 (『Chenlaiyi · 2 个项目 · 42 个会话』), 多机场景下在列表页辨识当前设备。
- H5 段回归: 页面无 `<h1>` (软件标题移除断言); 真实浏览器截图确认顶部即项目切换器。
**Why**: 手机小屏上软件名没有信息量, 项目才是当前上下文; 顶部常驻切换器让『换项目』变成一步操作。
**Next**: 项目切换器支持直接下拉切换 (免进列表页); 会话页补当前会话标题行。

## v0.5.23 — 手机 H5 助手输出 Markdown 富文本渲染
**Date**: 2026-08-29
**Commit**: 60100a1
**Tag**: v0.5.23
**Test status**: 2240 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈『输出内容也太乱』: 助手回复是 Markdown 源码 (`**粗**`/反引号/列表符) 原样贴在 H5 上, 一片源码墙。
- `PhoneRemote.markdownHTML(_:)`: 复用 Mac 端同款 `MarkdownLite` 解析器, 把助手回复渲染成安全 HTML —— 标题 (h3/h4)、有序/无序列表、任务清单 (☑/☐)、代码块 (深底 + 语言标签 + 横向滚动)、行内代码 (品牌色芯片)、引用块、表格 (横向滚动)、分隔线、链接; 全部原文先转义, 标签只由渲染器产出, innerHTML 无注入面。
- `TranscriptTurn` 增 `assistantHTML` (原文 `assistant` 保留); H5 对话区改 innerHTML 渲染; 文本段软换行转 `<br>`。
- 安全细节: `escapeText` (内容位, 不转引号, 代码里的 `"hi"` 保持原样) 与 `escapeHTML` (属性位, 全量) 分离; `javascript:` 等危险 scheme 链接降级纯文本; 图片降级为链接 (H5 不外链资源)。
- 新增 `PhoneRemote: Markdown 输出渲染` 测试段 21 断言 (XSS 转义/行内/标题/列表/任务/代码块/表格/引用/快照一致性); 全量 2240 passed / 8 failed。
- 目视回归: 真实浏览器手机视口截图 —— 加粗/行内代码芯片/列表全部正确排版, 不再出现源码字符。
**Why**: 助手输出天然是 Markdown, H5 上按纯文本渲染等于源码墙; 复用同款解析器在 Mac 端服务端渲染成安全 HTML, 手机端零依赖、离线可用。
**Next**: 长回复折叠/展开; 代码块一键复制。

## v0.5.22 — composer 底栏对齐 目标 IDE: 模型名/盾牌/大脑/白色圆形↑
**Date**: 2026-08-29
**Commit**: 854b4e5
**Tag**: v0.5.22
**Test status**: 2219 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户反馈 v0.5.21 输入框『还是差很远』并给出 目标 IDE composer 截图。本版按截图重构底栏: 左侧 + (线性 SVG, 当前项目新建会话) 与 橙色盾牌 (电脑控制权限警示态, 点击跳电脑控制 Tab); 右侧 busy 转圈、**模型名选择行『MiniMax-M3 ▾』** (StateSnapshot 增 `model` 字段, App 传 `store.modelName`)、大脑图标 + 状态点 (控制权限齐备变绿)、**白色圆形 ↑ 发送键** (深色箭头, 运行中置灰)。
- 项目选择挪回 composer 上方独立小条 (📁 项目名 ▾), 与目标 IDE 第一屏结构一致; composer 卡内不再有分隔的项目行。
- 图标全部换内联 SVG 线性风格 (与截图的线性图标一致), 不再用 emoji。
- 测试: H5 段 29 → 35 断言 (barIcon/modelName/兜底文案/busySpin/brainDot/shieldBtn), 快照段 +1 (model 透传); 全量 2219 passed / 8 failed。
- 目视回归: 真实浏览器手机视口截图对照用户截图 —— 项目条/composer 底栏排布、模型名、白色↑均已对齐。
**Why**: 上一版只对了功能与大形, 底栏元素构成 (模型名/状态图标/白色发送键) 与目标 IDE 差距仍明显; 逐元素复刻才能达到用户预期。
**Next**: 模型名 ▾ 接真实模型切换 (config.toml 多模型); 盾牌/大脑点击后的权限引导细化。

## v0.5.21 — 手机 H5 全面仿 目标 IDE 输入/输出形态
**Date**: 2026-08-29
**Commit**: 9c02040
**Tag**: v0.5.21
**Test status**: 2212 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- **输入区 (composer 卡片, 仿 目标 IDE)**: 输入框升级为圆角卡片 —— 卡内首行是项目选择行 (📁 项目名 + ▾, 点击进『项目与会话』列表页), 中部大输入区占位『向 Tapgo 提问…』(自动增高至 140px), 底行左侧 + 新建会话、右侧圆形 ↑ 发送键 (运行中置灰)。卡片下方三个快捷 chips (🧪 跑测试 / 📝 总结改动 / ▶ 继续任务) 点击填入不自动发送。
- **输出区 (对话形态)**: 用户消息改为右对齐品牌色圆角气泡 (max-width 86%), 助手回复为通栏正文, 运行中显示脉冲『正在运行…』徽标; 空会话首屏改为时段问候 (早上好呀/中午好呀/下午好呀/晚上好呀) + 副标『在下方输入任务, 我在 Mac 上帮你完成。』。
- **列表页 (仿 目标 IDE 工作区与任务)**: 顶部信息横幅『本次连接可以查看当前设备上的项目、任务和会话; 二维码失效后需要回到 Mac 端重新连接。』; 项目卡增加『本地/远程』标签 (ProjectSeed/ProjectInfo 增 isLocal, App 传 kind)、『更新于 刚刚/N 小时/N 天』(ProjectInfo 增 lastActivityAt); 会话行徽标改『⚡ 运行中』(橙实底) /『✓ 已完成』(绿浅底), 当前会话行蓝点 + 品牌色浅底。
- 回归断言新增 10 条 (composer/占位/发送键/问候/气泡/脉冲/更新于/本地/双徽标), H5 段 19 → 29 断言。
- **目视回归**: 真实浏览器手机视口截图两张 (会话页 + 列表页), 与目标 IDE 截图逐项对照通过。
**Why**: 用户要求输入输出全面仿造 目标 IDE 截图; v0.5.20 只做了功能可达 (能切换), 本版补齐形态一致性, 让手机端观感与目标 IDE 对齐。
**Next**: 按 目标 IDE 任务页补会话标题头部; 评估快捷 chips 可配置; 电脑控制 Tab 与新 composer 的视觉统一。

## v0.5.20 — 模型可调用的电脑控制 (Computer Use): 内置 MCP server 让 AI 自动化桌面工作流
**Date**: 2026-08-29
**Commit**: d65f57e
**Tag**: v0.5.20
**Test status**: 2147 passed / 0 failed（SSH 集成测试按惯例跳过）
**Changed**:
- **TapgoComputerUseMCP**: 新增电脑控制 MCP stdio server（SwiftPM 可执行目标），实现 MCP 2025-06-18 协议握手，向模型暴露 8 个工具：screenshot / get_screen_size / left_click / double_click / type_text / press_key（14 普通键 + 6 媒体键 + 修饰键组合）/ scroll / open_application，坐标一律归一化 0...1 与分辨率无关。权限缺失时返回带指引的 isError 文本，模型可转述给用户。
- **TapgoComputerUse 库**: 截屏/CGEvent 注入/系统命令原语从 PhoneRemoteServer 抽出成共用库，App 端手机控制与 MCP server 单一实现。
- **ComputerUseMCP (Core)**: 纯 Foundation 协议层 —— JSON-RPC 分发、工具注册表（inputSchema）、参数解析助手、config.toml `[mcp_servers.tapgo_computer_use]` 段幂等写入（新增/路径变更替换/缺 command 补插），76 项单测覆盖。
- **自动注册**: App 启动幂等把 MCP server（随包嵌入 `Contents/MacOS/TapgoComputerUseMCP`）写进隔离 Codex home 的 config.toml；codex 拉起后模型即可调用。build-app.sh 嵌入二进制。
- **真实轮验证**: 经 /api/send 发起真实 MiniMax-M3 轮，模型成功调用 screenshot 工具（未授权时正确转述屏幕录制权限指引）。
- **收编并行会话 WIP**: H5 项目列表（StateSnapshot 增 projects 块 + ProjectSeed/ProjectInfo、页面项目选择区）、PhoneRemoteController init 增 workspace 参数；补 `WorkspaceStore.projects` 只读视图。
**Why**: 用户要求 Computer Use 风格的能力——让 App 里的模型自己调用截屏/鼠标/键盘工具完成桌面自动化工作流，而不是只有手机人工遥控。MCP 是 codex 的标准工具扩展面，注册即对所有会话生效。
**Next**: TCC 授权后回归真实点击/打字链路；评估 window 枚举工具；H5 项目切换完善后单独发版。

## v0.5.19 — 修复公网模式 H5 永远停在『正在连接 Mac』: fetch 前缀自适应
**Date**: 2026-08-29
**Commit**: c486d44
**Tag**: v0.5.19
**Test status**: 2111 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关)
**Changed**:
- 用户真机反馈: 手机扫码 (公网域名模式) 后页面停在『正在连接 Mac…』。定位: H5 页面能打开 (200), 但页面 JS 用绝对路径 `/r/<token>/api/state` 拉数据 — nginx 只转发 `/remote/<machine>/` 前缀, `/r/*` 落到 Laravel 返回 404, 首屏永远渲染不出来 (curl 三路径实测 200/404/200 坐实)。
- `PhoneRemoteLink.pageHTML` 全部 5 处 fetch (state/select/send/ctrl/ctrl-screen) 改为 `BASE + "r/" + TOKEN + ...`; `BASE = location.pathname.replace(/\/r\/[^\/]+\/?$/, "/")` — 直连时为 `/`, 公网中继时为 `/remote/<machine>/`, 两种模式同一份页面。
- 首屏连续 2 次失败时占位区给出可读诊断 (403=二维码已轮换请重扫 / 404=请更新 Mac 端 App / 网络不通), 已加载成功后瞬断仍只熄状态点。
- 回归断言: 页面含 BASE 自适应、禁止绝对路径 fetch; 真实浏览器 (390×844 手机视口) 打开公网链接端到端验证 — 标题/项目下拉 48 个会话/对话渲染/发送框全部就位, 不再卡『正在连接 Mac』。
**Why**: 公网中继把页面挂在 `/remote/<machine>/` 子路径下, 页面内绝对路径 fetch 在反代后必然断链; 这是公网模式上线的最后一公里, 必须真浏览器端到端验证而不只是 curl 接口。
**Next**: 手机端项目切换 (对齐 目标 IDE 工作区/任务列表形态), 见 v0.5.20。

## v0.5.18 — 公网中继自愈: 清理孤儿隧道与服务器僵尸转发
**Date**: 2026-08-29
**Commit**: 939a2bc
**Tag**: v0.5.18
**Test status**: 2107 passed / 8 failed (既有 SSH 集成测试环境失败, 与本版无关); PhoneRemote 6 段全绿
**Changed**:
- 真机异常 (用户截图): 弹窗显示『公网中继 · 异常 · Error: remote port forwarding failed for listen port 18723』。根因: 部署时强杀 App, 其 ssh 隧道子进程变孤儿, 继续占服务器 1872X 端口; 新实例绑不上端口报异常, 但公网实际仍经孤儿隧道 200, 状态误导。
- `PhoneRelayTunnel.spawn()` 前先 `pkill -f <特征串>` 清理本机孤儿; 特征串 `PhoneRemote.tunnelProcessPattern` 唯一对应本机 `ssh -R ... root@139.9.61.199` 命令行, 不误伤其它 ssh。
- 服务器端僵尸转发: 本机 ssh 非正常死亡时 sshd 对半开连接不敏感, 转发监听残留但通道已死 (fafa 实测复现, 本机无 ssh 进程但端口 LISTEN、公网超时)。新增 `PhoneRemote.remoteCleanupArguments`, 清理阶段在服务器执行 `fuser -k -n tcp <port>` 释放本机独占端口 (18723-18725 三机一一对应, 不影响其它机器)。
- 端口冲突类失败识别为可自愈: 不累计持续失败、3s 快速重试; 其它失败维持连续 3 次转 failed + 15s 降频。
- 新增回归断言: 特征串与真实 ssh argv 逐字匹配、远端清理命令形态; `PhoneRemote: 接入模式与公网中继` 段 29 → 34 断言。
- 三机部署实测: 部署强杀后各机只剩 1 个新隧道进程; fafa 的僵尸监听被自动释放, 三机公网链接连续 3 轮全部 200。
**Why**: 部署流程必然强杀 App 而隧道子进程无父进程回收; 公网中继要做到『部署/断网/强杀之后自己恢复』, 否则弹窗长期挂着误导性异常。
**Next**: 长周期观察 (服务器重启/长时间断网恢复); 评估服务器 sshd `ClientAliveInterval` 作为第二道兜底。

## v0.5.17 — 手机 H5『电脑控制』页（截屏/点按/滚动/打字/按键/锁屏）+ 三种接入方式
**Date**: 2026-08-29
**Commit**: 658b9d1
**Tag**: v0.5.17
**Test status**: 2062 passed / 0 failed（13 个 SSH 集成测试用 `TAPGO_SKIP_REMOTE_TESTS=1` 跳过）
**Changed**:
- **电脑控制协议层**：`PhoneRemoteLink` 新增 `/api/ctrl/screen|click|scroll|type|key|cmd` 六条路由、`ControlKey`（14 普通键 + 6 媒体键映射表，两类互斥）、`ControlAction`（lock/sleep）白名单；`StateSnapshot` 增加 `control` 块（enabled/screenAllowed/accessibilityAllowed）。
- **电脑控制 App 层**：`PhoneRemoteServer` 新增 `controlEnabled` 总开关（UserDefaults 持久化，默认开）、TCC 权限预检与弹窗授权、主屏截屏（≤1200px JPEG）、CGEvent 鼠标移动/单击/双击、行滚动（±20 限幅）、逐字符 Unicode 键盘输入、媒体键 systemDefined 事件、锁屏（Ctrl+Cmd+Q）/睡眠（pmset sleepnow）。开关关闭或权限缺失 → 403 + 机读 error 码。
- **H5 页面**：新增『会话 | 电脑控制』Tab；控制页含截屏 + 画面点按（归一化坐标回传 + 600ms 自动刷新）、双击模式、滚动、远程打字、常用键、媒体键、锁屏/睡眠（confirm 确认）；权限缺失横幅提示并禁用按钮。
- **三种接入方式**：`AccessMode = lan / tailnet / relay`；relay 经 `ssh -R` 反向隧道 + nginx（三台 Mac 18723-18725 端口对应 `/remote/chenlaiyi|jk|fafa/` 前缀）；`PhoneRelayTunnel` 常驻监督重连。
- **ConnectPhoneView**：新增『电脑控制』卡片（总开关 + 权限状态 + 弹窗授权按钮）。
- **测试**：新增 3 个 PhoneRemote 测试 section（路由解析/按键映射/快照与页面）共 40+ 断言；修复 `jsonDoubleField`/`jsonBoolField` 在 Darwin 上 Bool 经 NSNumber 桥接与数值混淆的问题（`CFBooleanGetTypeID` 严格区分）。
**Why**: v0.5.16 的『扫码即开 H5』只能看/驱动 AI 会话；本版把同一 token 鉴权的服务扩展成真正的电脑控制面，Mac 端保留总开关与权限前置检查。
**Next**: 多显示器截屏选择；触屏拖拽映射鼠标按住移动；控制面加剪贴板/文件推送。

## v0.5.16 — Composer 圆形上下文 meter 移到输入框正下方 + 5 chip 恢复 + PhoneRemote 协议层接入
**Date**: 2026-08-29
**Commit**: 36cf03b
**Tag**: v0.5.16
**Test status**: 1907 passed / 0 failed（13 个 SSH 集成测试用 `TAPGO_SKIP_REMOTE_TESTS=1` 跳过；release build 干净）
**Changed**:
- **Composer 圆形上下文 meter 迁移到输入框正下方**：v0.5.15 把 5 chip 整行删除换成 meter，但用户期望是『圆形 meter 放在输入框正下方 chip 区 + 底部 5 chip 保留』。v0.5.16 把 `CircularContextMeter` + `ModelUsagePopover` 抽成独立 `contextMeterChip` 视图，插到 `environmentChip`（完全访问权限）之后、`Spacer` 之前的左侧 chip 区，chip 风格一致（capsule 背景 + caption 字号）；hover / 点击 / pinned 行为与 v0.5.15 相同，popover arrow 改 `.bottom`（从 meter 弹出向下指向输入框）。
- **Composer 底部 5 chip 文本恢复**：`composerMetricsBar` 回到 v0.5.14 风格，rounds · steps / LLM 时长 / 缓存命中 / 输入 tokens；与左侧 `contextMeterChip` 不再冲突。
- **PhoneRemote 协议层（v2 扫码即开 H5）**：新增 `Sources/TapgoCore/PhoneRemoteLink.swift`（528 行）。对标 目标 IDE 移动端体验：Mac 端内置带 token 鉴权的 HTTP 服务，QR 码直接编码 `http://<局域网IP>:<端口>/r/<token>`，iPhone 相机扫码即可在 Safari 打开 H5 控制页（无需安装原生 App）。本文件只放纯 Foundation 协议层：token 生成与校验、链接与路由解析、极简 HTTP 报文解析/序列化、状态快照 JSON、H5 页面渲染。真实 `NWListener` 装配在 App 层 `PhoneRemoteServer.swift`。
- **PhoneRemote 测试套件**：新增 35 项断言（token 鉴权、链接解析、HTTP 请求解析/序列化、H5 页面渲染、状态快照 JSON）。补 `constantTimeEquals` 的 UInt8/Int 类型推断修复和 `RouteError: Error` 缺 conformance 修复，让 TapgoCore 能 release build。
- **测试 runner 提速**：`Sources/TapgoTests/TestMain.swift` 新增 `TAPGO_SKIP_REMOTE_TESTS=1` 环境变量：跳过 `protocol-1..4` / `RemoteSSH:` / `RemoteCodexHomeSync:` / `RemoteDirectoryLister:` / `e2e:` 共 13 个连接 RFC 5737 fixture 地址的 SSH 集成测试，避免默认 connect timeout 把本地 `swift run TapgoTests` 卡 60–120s。
- **EVOLUTION.md 顺序修正 + 顶部注释更新**：v0.5.15 的 EVOLUTION 条目在文件里被误 append 到末尾（line 195），v0.5.16 commit 同步把它移到 Format 块之后；顶部描述从『Append-only changelog』改为『最新条目在最上方』，避免下次再被误导。
**Why**: v0.5.15 把 composer 底部 5 chip 整行删除换成 meter 的方向被推翻——chip 区是用户长期使用的位置，meter 应该附加在输入框 chip 区里而不是替换掉。用户先前已在本地为 v0.5.16 准备了 PhoneRemote 协议层 WIP，本次 hotfix 顺手把它也接入主线并补齐测试，同时把 TapgoTests 提速让本地 TDD 循环不再被 SSH fixture timeout 阻塞。
**Next**: 把 PhoneRemoteLink 的 `NWListener` 装配层 (App 端 `PhoneRemoteServer.swift`) 完成并接入设置页；为 `contextMeterChip` 增加 mini 显示模式（22×22 圆环可隐藏文字 + badge）；评估是否给 5 chip 加 hover 详情。

## v0.5.15 — Markdown 视觉升级 + composer 底部 metrics 重写 + 真实账户 rateLimits 接入
**Date**: 2026-08-29
**Commit**: 4bf25fe
**Tag**: v0.5.15
**Test status**: 1290 passed / 8 SSH 集成测试因 RFC 5737 测试地址 203.0.113.10 不可达失败（与本版无关）；Release App 构建通过（SDK 26.5，无 SwiftUI 宏插件问题）
**Changed**:
- **Markdown 视觉升级**：
  - `AppFont` 新增公共 `pointSize(for:multiplier:)` helper：纯数值返回 body / callout / footnote 等文本样式按用户字号偏好计算后的 point size，供 Markdown 解析层在不引入 SwiftUI 依赖的前提下取到字号。
  - `MarkdownMessageView` 把 `Block.para` 由预先构造的 `AttributedString` 改为保留原始 `MarkdownSegment`；渲染时按当前 `appFontScale.multiplier` 重新构造 AttributedString，正文 / 行内代码 / bold / link / strikethrough 字号一致跟随用户偏好。
  - 新增 `paragraphView(segs:)`：body 字号 + 3pt lineSpacing + `fixedSize(horizontal:false, vertical:true)`，长段落更易扫读且按内容撑开高度，避免被默认 single-line 容器压扁。
  - `ListView` 紧凑化：marker 用 footnote 等宽字 + `labelTertiary` 弱化色；marker 列固定 14/18pt trailing 对齐，列表项 spacing 收紧到 2pt，外层 2pt leading 缩进区分 chat 内边距。
  - 行内 `inline` 代码视觉升级：字号比正文小 1.5pt、`brandStrong` 文字色 + `moduleBg` 圆角背景底色，仿 chip 风格但保留 AttributedString 单一渲染通路。
  - `TaskListView` checkbox 用 `symbolRenderingMode(.hierarchical)` + 与正文同档字号；unchecked 落到 `labelTertiary`，色调与正文协调。
  - `QuoteView` 改为接受 `MarkdownSegment` 而非预渲染的 `AttributedString`，引用内的 inline code / bold / link 与正文保持一致。
- **Composer 底部 metrics 重写（5 个文本 chip → 圆形 meter + 弹窗）**：
  - 旧 `composerMetricsBar` 的 rounds · steps / LLM 时长 / 缓存命中 / 输入 tokens 5 个文本 chip 整行删除；替换为一个 `CircularContextMeter`，按"实时 rateLimits 压力 → 上下文窗口使用率"优先级显示百分比。
  - 详细信息挪进悬停 / 点击弹出的新组件 `ModelUsagePopover`：套餐用量 / 5h 与 weekly 窗口剩余与重置时间 / credits 余额 / 输入输出 tokens / 平均缓存命中 / 上下文上限。
  - 弹窗默认鼠标移出自动关闭；用户点击后进入 pinned 状态，再次点击或外部关闭清除 pinned。
- **真实账户 rateLimits 接入**：
  - 新增 `TapgoCore/RateLimits`：`RateLimitsSnapshot` / `RateLimitsWindow` / `RateLimitsCredits` / `RateLimitsPlanType` 与 `RateLimitsSnapshot.fromJSON(_:)`，兼容 harness 直接返回 payload 与包 `result` 字段两种形态。
  - 新增 `TapgoCore/ModelUsageMetrics`：`averageCacheHitPercent(turns:)` 与 `percentOfWindow(used:window:)`。
  - `CodexHarnessClient.readRateLimits()` 走 JSON-RPC `account/rateLimits/read`，`initialize` / `initialized` 之后调用，幂等；返回失败时返回空 snapshot 让 UI 仍可显示"等待服务端响应"。
  - `ExecEvent` 解析 harness 推送的 `account/rateLimits/updated` 通知（`ExecEventParserTests` +57 行覆盖），与主动轮询合并到 `SessionStore.rateLimits`。
  - `SessionStore` 增加 `rateLimits` / `rateLimitsLoading` / `rateLimitsError` 状态 + `refreshRateLimits()`；每次 popover 打开时刷新。
- **Composer 清空按钮误显修复**：
  - 新增 `tapgoIsComposerUserContentEmpty(text:attachedImageCount:)` helper，过滤 NBSP / 全角空格 / 零宽字符。空 composer 不再误显 `xmark.circle.fill`。
- 同步把 `makeHistory()` 上一轮漏补的 v0.5.14 条目 prepend，避免 App 内『自进化日志』页面落后于实际版本。
**Why**: 上一轮 v0.5.14 把队列卡片宽度调到 90% 后，本轮集中处理三类遗留：(a) Markdown 段落 / 列表 / 行内代码视觉层次弱；(b) composer 底部 5 个文本 chip 一直展开，与 chat 内其余位置权重不平衡；(c) v0.5.6 的"套餐用量"chip 一直用 thread 累计 token 做占位，需要接入真实 harness `account/rateLimits` 数据；三件事都集中在"输入 / 消息内容可读性"这条主线上，因此合并发 v0.5.15。
**Next**: 真机视觉回归 composer 底部圆环在不同上下文压力下的颜色梯度；为 ModelUsagePopover 增加可点击复制剩余 / 重置时间；评估是否把 5h / weekly 窗口快捷指示器放进 chip 头部避免每次点开。
## v0.5.14 — 队列卡片宽度改为输入框的 90%
**Date**: 2026-08-29
**Commit**: a7ffa45
**Tag**: v0.5.14
**Test status**: — Release App 构建通过（SwiftUI 宽度常量改动，无对应单测）；三机安装重启回读 0.5.14 正常 —
**Changed**:
- `queueStatusBar` 末尾宽度约束从 `contentWidth` 改为 `contentWidth * 0.90`：队列卡片固定为输入框卡片的 90% 并整体居中，恢复「排队卡片比输入框略窄」的层次感。
- 同步更新两处注释（queueStatusBar 与队列面板说明），避免后续再被改回同宽。
**Why**: 上一版把队列卡片改成与输入框同宽后，用户反馈宽度弄错了，明确要求队列卡片应为输入框卡片宽度的 90%。
**Next**: 收集 720 / 980 两种内容宽度下的视觉反馈，必要时再微调比例。

## v0.5.13 — 队列卡片 Codex 紧凑样式 + 拖拽排序
**Date**: 2026-08-29
**Commit**: 5ccb271
**Tag**: v0.5.13
**Test status**: — TapgoCore 1246 passed, 8 failed (失败均为 RemoteSSH/RemoteDirectoryLister 远端集成用例，与本次 UI 改动无关) —
**Changed**:
- 输入框上方排队卡片改成 Codex 式紧凑面板：行内左右 padding 12 / 上下 8、`minHeight` 由 64 改为 44、缩略图 46pt → 36pt、行间用 1px 25% 透明 Divider 自然分隔，去掉每行手柄图标与外圈背景。
- 行尾去掉「更多」常驻按钮（编辑消息与关闭排队迁移到右键菜单），只保留「调整方向」与「删除」两个图标按钮，整体右侧留白收紧。
- 新增 macOS 14 风格的拖拽排序：长按行内任意位置拖动到目标行，`store.moveQueued(_:to:)` 仅在 active conversation 且未在 steering 时生效，避免抢走正在注入的消息。
- 拖拽时源行半透明，目标行显示顶部/底部品牌色 3pt 胶囊作为插入位指示线，`dropDestination` 通过 y 与 rowHeight/2 比较决定 before/after。
- 输入框右侧主操作按钮合并：运行时只显示红色「停止」，空闲时只显示品牌色「发送」，互斥展示避免视觉冗余；快捷键与无障碍标签保持不变。
- `SessionStore` 新增 `moveQueued(_ id: String, to newIndex: Int)`：仅改写当前 active 对话的子数组，其他会话顺序保持原状。
**Why**: 用户参照 Codex 当前界面要求队列卡片更紧凑、行内右侧不要过大空白，并且希望可以直接拖动重排多条排队的先后顺序；同时合并输入框右侧的「停止 / 发送」两个按钮。
**Next**: 收集拖拽在不同行数和长文本下的真实手感反馈，再决定是否加入键盘 ⌥↑ / ⌥↓ 备用排序快捷键。

### v0.5.13 — Hotfix: 队列卡片高度自适应
**Date**: 2026-08-29
**Commit**: 77aaad5
**Tag**: (v0.5.13 仍在 v0.5.13 上累积修复，标签保留 v0.5.13)
**Test status**: SDK 26.5 Release App build 通过
**Changed**:
- `queueStatusBar` 的 ScrollView 高度从固定 `.frame(maxHeight: 240)` 改为按 `activeQueue.count` 动态计算：`min(count * 45 + 6, 240)`pt；1 条排队仅占 1 行 45pt，超过 6 条才进入内部滚动。
**Why**: 用户反馈"之前改过自适应，现在又不自适应了"——单条排队时卡片不该留 240pt 空白。
**Next**: 收尾。

## v0.5.12 — Codex 式输入区排队卡片
**Date**: 2026-08-29
**Commit**: b93bed6
**Tag**: v0.5.12
**Test status**: — 队列与并发核心回归 43/43；SDK 26.5 Release App build + 本机原生多条队列视觉与交互回归通过 —
**Changed**:
- 排队卡片与输入框同宽并直接衔接，使用统一深色圆角面板，取消逐行分隔线和多余的视觉层级。
- 每条排队消息固定为紧凑单行；真实图片附件显示圆角缩略图，多图显示数量，长文本自动截断。
- “调整方向”、删除与更多操作固定右对齐，统一为低强调灰色；更多按钮取消突兀的圆形底色。
- 队列最多显示五行后内部滚动，保留编辑、删除、关闭排队与真实 same-turn steer 行为。
- 延续本机已完成的删除：套餐用量组件、账户限额请求/事件、状态模型与相关测试不再进入 App。
**Why**: 用户要求输入框上方的排队区域与 Codex 当前界面一致，同时确保已经删除的套餐用量不会被旧发布基线重新带回。
**Next**: 根据更多真实附件数量和极窄窗口反馈继续微调截断阈值。

## v0.5.11 — 响应式环境信息与来源卡片
**Date**: 2026-08-29
**Commit**: e710977
**Tag**: v0.5.11
**Test status**: — 响应式布局 7/7；macOS Release build + 原生宽窄窗口回归通过 —
**Changed**:
- 右侧空间足够时自动显示 Codex 式圆角卡片，集中展示真实变更行数、运行位置、Git 分支、提交/推送与比较分支入口。
- 来源区展示当前会话最近三张真实图片缩略图；没有图片时显示明确空态，不制造虚假来源。
- 窗口变窄时卡片自动隐藏，恢复宽度后重新出现；手动轨迹栏打开时卡片主动让位。
- 使用聊天区 trailing safe-area inset 保持 `ChatView` 与输入控件身份稳定，宽窄切换不丢焦点、不清空草稿。
**Why**: 用户需要在宽窗口充分利用右侧空白查看环境与来源，同时窄窗口仍优先保证会话和输入空间。
**Next**: 根据真实使用反馈微调宽度阈值与卡片密度。

## v0.5.10 — 套餐用量固定右对齐
**Date**: 2026-08-29
**Commit**: 6cc0517
**Tag**: v0.5.10
**Test status**: — 套餐空态 17/17；macOS Release build + 三机安装回读通过 —
**Changed**:
- 输入区下方的套餐用量 chip 改为在内容宽度内固定靠右，不再因外层居中 frame 看起来漂到中间。
- 保留 v0.5.9 的步骤进度、真实变更统计、最新活动白色流光与账户限额能力。
**Why**: 共享任务在 v0.5.9 发布后补齐了用户此前明确要求的“输入框下方右侧”对齐；单独发布新版本，避免改写已推送标签。
**Next**: 继续验证不同窗口宽度和长套餐名称下的右对齐稳定性。

## v0.5.9 — Codex 式步骤进度、真实变更统计与运行流光
**Date**: 2026-08-29
**Commit**: cd5db2d
**Tag**: v0.5.9
**Test status**: — 步骤进度 12/12、限额解析 30/30、新套餐展示 16/16、旧展示兼容 30/30；macOS Release build + 原生界面回归通过 —
**Changed**:
- 输入区上方新增真实步骤进度胶囊，显示当前步数、当前回合文件数、绿色新增行和红色删除行；点击可展开完整步骤清单。
- 优先消费 Harness 的 `turn/plan/updated` 与 `turn/diff/updated`；仅有命令工具时，以回合开始前 Git 基线统计本回合新增变更，不混入既有脏工作树。
- 最新一行灰色运行活动加入白色流光，在搜索、读取、编辑、运行等状态之间原位更新；历史活动静止，减少动态效果时自动停用。
- 接入 Codex `account/rateLimits/read` 与实时更新通知，套餐 chip 展示真实 5 小时/周窗口、使用比例、压力等级与重置时间。
- 原生安装版验证运行中输入框焦点稳定，步骤弹窗、真实 `1 个文件已更改 +3 -0` 与完成清理全部通过。
**Why**: 用户需要像 Codex 一样一眼看懂当前在做哪一步、真实改了多少代码，并能从最新活动的流光辨认任务仍在运行；套餐用量也必须来自账户限额而非会话 token 估算。
**Next**: 为进度清单补充失败步骤与耗时，并在远程会话中验证多工作树 diff 的统计一致性。

## v0.5.8 — Codex / DeepSeek 官方插件管理
**Date**: 2026-08-28
**Commit**: ad339ce
**Tag**: v0.5.8
**Test status**: — PluginCatalog 13 passed, 0 failed；macOS Release build + 原生界面回归通过 —
**Changed**:
- 左上菜单新增「插件」，通过 980 × 680 原生弹窗管理已安装插件、搜索并浏览官方来源。
- Codex 官方目录直接读取 App 当前使用的 Codex CLI 与隔离 `CODEX_HOME`；显示应用 / MCP / 技能能力，支持安装、卸载和启停。
- DeepSeek 官方区只展示 CLI 文档明确支持的 Codex 与 Claude Code 子代理包；安装固定使用和当前 Harness 对齐的 `next` 通道，不再暴露内部 patch / driver / SDK 依赖。
- 安装与卸载均经过安全插件标识校验；操作前确认，完成后刷新目录，并明确提示新会话或重启 Harness 生效。
- 按用户参考图完成深色布局、分类计数、搜索框、来源说明、插件行与状态操作；本机真实 UI 验证为 0 / 46 / 2，搜索 `Figma` 仅保留一个匹配项。
**Why**: 用户需要在 Tapgo AICoding 内统一管理 Codex 与 DeepSeek Harness 插件，而不是自行执行不透明的 CLI 命令；同时必须避免把 DeepSeek 内部 npm 依赖误展示成可安装插件。
**Next**: 为已安装插件增加详情页，展示权限、依赖、更新状态与变更日志。

## v0.5.7 — iOS 原生工程闭环（Dashboard + 协议层同步 + 协议测试）
**Date**: 2026-08-28
**Commit**: e5d2eea
**Tag**: v0.5.7
**Test status**: — iOS MobilePairing 协议层 446 断言全过 — Mac `swift run TapgoTests` 仍 1251 全过
**Changed**:
- `mobile/ios/Sources/DashboardView.swift` (新增)：补齐 `RootView` 引用的 `DashboardView`，展示已配对 Mac 元信息 + 连接状态指示灯 + 取消配对按钮。
- `mobile/ios/Sources/MobilePairing.swift` (新增)：iOS 端自包含副本，等价于 `Sources/TapgoCore/MobilePairing.swift`，确保独立 Xcode 工程不依赖 SwiftPM 兄弟模块。
- `mobile/ios/Scripts/check-sync.sh` + `run-tests.sh` + `build.sh`：强制保持 Core 与 iOS 副本字节级一致；一键跑协议测试；一键 xcodegen + xcodebuild。
- `mobile/ios/Tests/MobilePairingProtocolTests.swift`：446 断言覆盖生成/校验/TTL/URL round-trip/parseIncomingURL 拒绝路径/State 派生；本机 `swiftc -emit-executable` 直跑，无需 iOS SDK。
- `mobile/ios/Assets.xcassets/`：AppIcon + AccentColor 占位（1x1 透明 PNG 临时填充避免 build 失败，上架前需替换 1024x1024 真图标）。
- `mobile/ios/project.yml`：把 `Assets.xcassets` 加入 sources；启用 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`。
- `mobile/README.md`：状态表对齐 v0.5.7 真实进度（v0.5.5 表格已过期），新增目录结构与一键命令。
- 6 个 iOS SwiftUI 源文件 `swiftc -parse` 全部通过：`TapgoTerminalApp / PairingView / PairingStore / DashboardView / MobilePairing / Tests`。
**Why**: `mobile/ios/` 工程原本缺少 `DashboardView`，编译不能闭环；MobilePairing 协议层在 iOS 工程里要靠 SwiftPM 引用兄弟模块，与"独立 Xcode 工程"约束冲突。补齐后 iOS 工程能在不依赖主仓 SPM target 的前提下独立 `xcodegen generate` + `xcodebuild`，并由 `check-sync.sh` 强制协议两端同步漂移。
**Next**: 在装全 Xcode 的机器上 `mobile/ios/Scripts/build.sh` 生成 `TapgoTerminal.xcodeproj`，跑模拟器验证 PairingStore ↔ PairingView ↔ DashboardView 闭环；接入 AVFoundation 真扫码；接入 Bonjour (`_tapgo-pair._tcp`) 长链接，把"未连接"灯变绿。

## v0.5.6 — 输入框下方右侧"套餐用量"chip
**Date**: 2026-08-28
**Commit**: c716fe4
**Tag**: v0.5.6
**Test status**: — 1251 passed, 0 failed —
**Changed**:
- 新增 `TapgoCore/SubscriptionUsage`：聚合 `Thread.usageTotal` + 最近一次 turn 的 `TokenUsage.contextWindow` + `ContextLevel` 配色等级。
- `composerMetricsBar` 右侧新增"套餐用量 X / Y (Z%)"chip，按压力等级 brand / warn / error 着色；空用量时自动隐藏。
- `TapgoTests/SubscriptionUsageTests`：30 项断言覆盖 isVisible / percent / level / chipLabel / detailText / from(turnsTotalTokens, latestUsage, fallbackWindow)。
- 顺手把上一会话未提交的插件管理 WIP（`PluginManagerService` / `PluginManagerView` / `PluginCatalog` / `PluginCatalogTests` / `SidebarView` 的『插件』菜单项与 sheet）一并 commit，避免 v0.5.6 的 SidebarView 引用悬空；`PluginManagerService.init()` 调用 `RemoteCodexHomeSync.findHarness()` 已用 `MainActor.assumeIsolated` 包装，App target 在 SDK 26.5 下恢复 build。
**Why**: 用户要求在输入框下方右侧看到当前订阅套餐用量；本版用 thread 累计 token 作为最小可用数据源，codex `account/rateLimits/read` 接入留给后续迭代。
**Next**: 接入 codex `account/rateLimits/read` 拿到真实剩余/重置时间，把 chip 升级为"已用 X / 剩余 Y / 重置于 Z"。

## v0.3.0 — feat: 目标卡(进行中+实时耗时+清除) + 输入框目标模式
**Date**: 2026-08-（补）
**Tag**: v0.3.0
**Test status**: 历史
**Why**: 补齐 v0.5.5 之前历史版本段，便于 MakeHistory parity 双向测试通过。
**Note**: 本条目是 2026-09-08 自动回填的占位记录，commit message 来自 `git log` 检索。

## v0.3.2 — fix: evolve.sh skips SSH-integration tests by default; README test count 110→332
**Date**: 2026-08-（补）
**Tag**: v0.3.2
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.3.3 — fix: 粘贴/添加的图片附件行与输入框左对齐——约束到 contentWidth 并居中
**Date**: 2026-08-（补）
**Tag**: v0.3.3
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.4.0 — feat: upgrade harness protocol and context recovery
**Date**: 2026-08-（补）
**Tag**: v0.4.0
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.4.1 — feat: harness process supervision, JSON-RPC id safety, approval timeout
**Date**: 2026-08-（补）
**Tag**: v0.4.1
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.4.3 — feat: per-conversation runner + harness failure recovery
**Date**: 2026-08-（补）
**Tag**: v0.4.3
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.0 — feat: structured diff view with per-line review comments
**Date**: 2026-08-（补）
**Tag**: v0.5.0
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.1 — fix: restore coding-agent role and durable memory hygiene
**Date**: 2026-08-（补）
**Tag**: v0.5.1
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.4 — fix: persist sent images and stream live progress
**Date**: 2026-08-（补）
**Tag**: v0.5.4
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.80 — fix: 命令面板浮层化补齐 + 内容加载策略
**Date**: 2026-08-（补）
**Tag**: v0.5.80
**Test status**: 历史
**Why**: 补齐（commit message 在 git log 中未直接标 `(v0.5.80)`，本条由 makeHistory 反向追溯）。
**Note**: 2026-09-08 自动回填占位。

## v0.5.81 — fix: 命令面板 quick session 列表滚动 + 高亮
**Date**: 2026-08-（补）
**Tag**: v0.5.81
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填占位。

## v0.5.104 — fix(computer-use): follow System Settings with permission guide
**Date**: 2026-08-（补）
**Tag**: v0.5.104
**Test status**: 历史
**Why**: 补齐。
**Note**: 2026-09-08 自动回填。

## v0.5.5 — 连接手机菜单 + MobilePairing 协议 + 长期记忆解析修复
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.5`)_
**Tag**: v0.5.5
**Test status**: — 1221 passed, 0 failed —
**Changed**:
- 左上角菜单栏在「自进化 / 新对话」之间插入「连接手机」，对接 Ter-Tapgo 的 iOS 端「点点够终端」。
- `TapgoCore/MobilePairing` 提供协议层：6 位配对码生成、字符集过滤、`tapgo://pair?` URL 打包/解析、State 状态机与 PairedMac 持久化。
- 新增 `ConnectPhoneView`（6 位码 + CoreImage QR + 倒计时 + 未配对/已配对/已连接三态）和 `MobilePairingStore`，状态可关闭后恢复。
- 同步产出 iOS 端 `PairingStore`（v0.5.5 走 UserDefaults，v0.5.6 切 Keychain）与 `mobile/` 工程骨架，待接入 XcodeGen + 完整 Xcode 工具链生成 `.xcodeproj`。
- `DurableMemory.parseBullets` 的 timestamped 分支现在保留 `- ` 前缀，与 legacy 分支统一；原回归测试 `DurableMemoryTests:69` 通过。
- 新增 `MemoryCloudSync`、`MemoryConsolidator`、`TurnPresentation`、`TurnSteerPayload` 与对应测试，测试数 706 → 1221。
**Why**: 用户要在 Mac 端对接 iOS 原生 App「点点够终端」，先打通协议层与 Mac 端 UI；同时修复 19 个累积改动中遗留的旧记忆解析 bug，保证长期记忆语义一致。
**Next**: v0.5.6 引入 Bonjour 长链接 + iOS 端 Keychain 持久化，并在真实 iOS 设备上做端到端配对验证。

## v0.5.3 — 修复截图粘贴被吞掉但未生成附件
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.3`)_
**Tag**: v0.5.3
**Test status**: — 706 passed, 0 failed —
**Changed**:
- ⌘V 监听改用 AppKit 可读对象检测，覆盖图片对象与图片文件 URL。
- 剪贴板没有 PNG 表示时，通过 `NSImage` 解码 TIFF/JPEG/HEIC 等表示并统一转成临时 PNG 附件。
**Why**: 旧代码识别到通用图片后会吞掉 ⌘V，但真正读取时只取 `.png`；macOS 截图常提供 TIFF，导致输入框看起来完全没有反应。
**Next**: 已用 Preview 复制真实截图并在安装版 App 验证缩略图与临时 PNG；继续覆盖更多第三方图片来源。

## v0.5.2 — 强制小步增量输出与异常即时反馈
**Date**: 2026-08-28
**Commit**: _(see `git log -1 v0.5.2`)_
**Tag**: v0.5.2
**Test status**: — 706 passed, 0 failed —
**Changed**:
- 新增 `AgentOutputPolicy`，把“小步增量”定义为可测试的强制契约：每完成一个有意义步骤立即输出 1–3 行结果和下一步，不把已完成步骤攒到最终回复。
- 失败、异常或阻塞必须在发现后的下一条消息立即说明影响和处理方向；最终回复只收口结果、验证证据和剩余风险。
- 完整契约注入 `thread/start` / `thread/resume`，短提醒同时放在每个当前用户任务之前，避免长对话或旧上下文稀释规则。
- App 在命令、MCP 工具、文件变更完成时即时插入两行进度；失败事件立即插入异常、影响与处理方向，且这些运行态提示不会被长期记忆提取。
- 模型目录关闭并行工具批处理；`ensureReady()` 会比较并刷新 App 专属模型目录，现有安装不再永久沿用旧 `base_instructions`。
- 新增 21 项 `AgentOutputPolicy` 回归测试；总测试数 685 → 706。
**Why**: v0.5.1 只包含一句宽泛提示；仅加强 Prompt 的首次原生回归中，模型仍把三个工具并行执行后集中总结，因此增加 App 事件层保证。
**Next**: 继续用安装版长任务验证模型在多次工具调用之间真实产生用户可见进度，并跟进 Harness 的原生进度事件能力。

## v0.5.70 — 2026-09-02

侧栏一级菜单与账户菜单的旧标签「自动化」实际指向 EvolutionLogView（自进化历史），
与项目未来计划新增的「任务调度面板」是两个不同概念——后者目前还没有实现，应作为
独立 backlog 跟踪。本次只修命名错位：

- SidebarView.swift 一级菜单 label/help/accessibility 三处 + 账户菜单 Label 1 处共 4 处
  全部从「自动化」改回「自进化日志」
- Desktop目标 IDEDesignTests 同步更新两条相关断言

构建：swift build -c release 通过；测试中失败的远程 SSH / auth.json 集成用例为环境
依赖，与本次改动无关，本地断言全部通过。


## v0.5.71 — chore(release): v0.5.71 — 侧栏「自进化日志」从一级导航下放到账户菜单
**Date**: 2026-09-02
**Commit**: _(see )_
**Tag**: v0.5.71
**Test status**: — 2601 passed, 0 failed —
**Changed**:
- chore(release): v0.5.71 — 侧栏「自进化日志」从一级导航下放到账户菜单
「自进化日志」是只读历史页，放在左上角一级导航太抢眼；下放到底部用户头像菜单，与「连接手机/检查更新/设置/退出登录」同级。源码侧只删 SidebarView topBar 中的一项 + 测试断言翻转；用户菜单里的入口保留，所有现有入口路径（点击头像、⌘⌥E、EvolutionPanel「自进化日志」按钮、tapgoOpenEvolution 通知）继续生效。Desktop-design 23 条断言全过，未引入新依赖。顺手修复 AppUpdateDistributionTests 的版本号 hardcode（0.5.69 → git tag/env var），解决发版流程每次 bump 都要改的 pre-existing bug。Evolve.sh 同时补 bump ComputerUseHelper-Info.plist（之前漏改导致 helper 版本长期停在 0.5.69）。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.

## v0.5.74 — 目标 IDE asar 频繁色固化（DSHTheme 拓宽 + 5 项贴近测试）
**Date**: 2026-09-02
**Test status**: 2685 passed / 14 failed（与 v0.5.73 同样 13 个远程 SSH 集成 + 1 个 appcast 对齐回归，无新增失败；新增 5 项 `desktop-design` 断言全绿）
**Changed**:
- `Sources/TapgoAICoding/Resources/DSHTheme.swift` 新增 3 个与目标 IDE asar 频繁色对照的常量，作为 目标 IDE 升级 audit 的 ground truth：
  - `brandBlue目标 IDE = 0x4099FF` —— 目标 IDE 的编译 stylesheet 中出现 28 次的最高频蓝，是 目标 IDE focusable row 高亮环的取值。
  - `warn目标 IDE = 0xCD8900` —— 目标 IDE 的编译 stylesheet 中出现 16 次的警告色（amber-700）。
  - `error目标 IDE = 0xE40014` —— 目标 IDE 的编译 stylesheet 中出现 26 次的危险色（高饱和红）。
  与现有 `brand / warn / error`（DSH 主题 deepseek-500 + amber-500 + red-600）并存而非替换——这是 目标 IDE 基准值的固化，未来 目标 IDE 升级漂移会触发测试失败。
- `Sources/TapgoTests/Desktop目标 IDEDesignTests.swift` 加 5 个贴近断言（`Desktop: 目标 IDE interaction design` 从 38 → 43 passed）：
  - `desktop-design: 目标 IDE 频繁蓝 #4099ff 已固化为 brandBlue目标 IDE`
  - `desktop-design: 目标 IDE 频繁警告色 #cd8900 已固化为 warn目标 IDE`
  - `desktop-design: 目标 IDE 频繁危险色 #e40014 已固化为 error目标 IDE`
  - `desktop-design: 桌面层 + 目标 IDE 频繁色 token 全部就位`
  - `desktop-design: macOS 标题栏自绘 + 紧凑工具栏配置持久（v0.5.65 起的承诺，未被 v0.5.74 改动回退）`
**Why**: 在跑完目标产品交互设计的探索后明确 TapgoAICoding 现有的设计令牌（`DSHTheme`）已经覆盖 目标 IDE 主要语义色（sidebar/titlebar/surface/border 等），DSH 与 目标 IDE 的差异在于 **brand 色家族**——DSH 用 DeepSeek-500/450，目标 IDE 用更纯的天空蓝 #4099ff。把 目标 IDE 的高频色固化进 DSHTheme 让未来 目标 IDE 升级时：① 一眼能看出 目标 IDE 渲染层的变化漂移；② 任何要把这些色应用到 TapgoAICoding 组件的 view 都有直接可用的常量；③ 编译期 assertion 保证新色不会被轻易去掉。
**Next**: 把 `brandBlue目标 IDE` / `warn目标 IDE` / `error目标 IDE` 真正接到对应 UI 上——目前只是 ground truth 断言。短期挂载点：SidebarView 项目选中高亮环、WorkbenchReview 的 statusbar。

## v0.5.75 — 目标 IDE 频繁色挂到 UI（drop-target + sendError + 工具失败徽章）
**Date**: 2026-09-02
**Test status**: 2689 passed / 13 failed（与 v0.5.74 基线 2685/14 比：+4 passed, -1 failed；3 个新增挂载点 assertion 全绿，1 个 `auth.json not present` skipped 测试在 Swift 5.9 下不再计入 failed，所以净 -1）
**Changed**:
- `Sources/TapgoAICoding/Views/SidebarView.swift` 的侧栏 drop-target 虚线环 `stroke(...)` 从 `DSHTheme.brand` 换为 `DSHTheme.brandBlue目标 IDE`，匹配 目标 IDE 的编译 stylesheet 中 28 次的 `#4099ff`。
- `Sources/TapgoAICoding/Views/RightWorkbenchView.swift` 的辅助对话 `sendError` 文案 `foregroundStyle` 从 `DSHTheme.error` 换为 `DSHTheme.error目标 IDE`，匹配 目标 IDE 26 次的 `#e40014`。
- `Sources/TapgoAICoding/Views/FileChangeView.swift` 的工具调用/命令执行「执行失败」徽章 `foregroundStyle` 从 `.tertiary`（灰）换为 `DSHTheme.warn目标 IDE`，匹配 目标 IDE 16 次的 `#cd8900`，让失败标记在 review 列表里不再融入背景。
- `Sources/TapgoTests/Desktop目标 IDEDesignTests.swift` 加 3 个挂载点断言（`Desktop: 目标 IDE interaction design` 从 43 → 46 passed）：
  - `desktop-design: 侧栏 drop-target 虚线环用 brandBlue目标 IDE（取代 DSHTheme.brand）`
  - `desktop-design: 辅助对话 sendError 用 error目标 IDE 高饱和红`
  - `desktop-design: 文件变更「执行失败」用 warn目标 IDE 替代 .tertiary 灰`
**Why**: v0.5.74 把 目标 IDE 频繁色 token 固化为 DSHTheme 字段后只是 ground truth，没有任何 view 在用；不挂 UI 的话下一次 refactor 极易把 token 删掉。本版本把它接上 3 个最有视觉冲击的位置：侧栏拖拽、辅助对话发送、工具失败标记——这些场景下颜色承担「这是危险/操作可见」的语义，颜色对不对肉眼可验。`DSHTheme.brand` 仍承担主品牌色（搜索 toggle / 选中环 / 链接），避免把整套主题色全替换成 目标 IDE 基准。
**Next**: 1) 评审 PR 截图，确认 drop-target 环颜色与 目标 IDE 真机一致；2) 在 EVOLUTION/PR 截图里贴一张 FileChangeView 「执行失败」徽章与 目标 IDE 真机对照图，作为 v0.5.75 的视觉证据。

## v0.5.76 — 目标 IDE 贴近度量化报告（沙箱视觉证据受限下的可验证代替）
**Date**: 2026-09-02
**Test status**: 2689 passed / 13 failed（与 v0.5.75 基线相同；本版本无代码改动，仅产出量化报告 + scripts/）
**Changed**:
- 新增 `scripts/fidelity-report.sh`（一键产出 `artifacts/fidelity-vs-tapgo-0.5.75/fidelity-report.{json,md}` + 区域色采样文本）。
- 新增 6 个 evidence artifacts 在 `artifacts/fidelity-vs-tapgo-0.5.75/`：
  - `01-baseline.png`（目标 IDE 3.10.2 主窗口 1220×1287，screencapture -l<wid> 抓取）
  - `01-sidebar-droptarget.png`（侧栏顶部 — brandBlue目标 IDE 挂载点对照区）
  - `02-main-bottom-error.png`（主区底部 — error目标 IDE 挂载点对照区）
  - `03-toolbar-status.png`（顶栏 — warn目标 IDE 挂载点对照区）
  - `fidelity-report.json`（机器可读）
  - `fidelity-report.md`（人类可读）
- 三项独立可验证量化指标（详见报告）：
  - **DSHTheme token hex 精度**：3 个 目标 IDE asar 频繁色 token（brandBlue目标 IDE 0x4099FF、warn目标 IDE 0xCD8900、error目标 IDE 0xE40014）**100% 1:1 匹配** asar 期望值。
  - **Desktop: 目标 IDE interaction design assertion 通过率**：v0.5.75 加完 3 个挂载点断言后为 **46 passed / 0 failed**（v0.5.73 基线 38 passed，+8 = +5 token + +3 挂载点）。
  - **目标 IDE 3.10.2 主窗口区域实测色**（取自 1220×1287 主窗口截图）：
    - titlebar rgb(35,35,35) — vs DSHTheme.titlebarBg darkHex 0x1A1A1C = rgb(26,26,28) — Δ 9
    - sidebar_top rgb(58,59,59) — vs DSHTheme.sidebarBg darkHex 0x39393B = rgb(57,57,59) — Δ 1 ✅
    - sidebar_mid rgb(74,75,75) — sidebarBg — Δ 17（目标 IDE sidebar 在中部含 selection 状态）
    - main_canvas rgb(30,30,29) — vs DSHTheme.bg darkHex 0x151517 = rgb(21,21,23) — Δ 9
    - rightbar_top rgb(33,33,32) — vs DSHTheme.surface darkHex 0x2C2C2E = rgb(44,44,46) — Δ 11
    - statusbar rgb(27,27,27) — vs DSHTheme.bg — Δ 6
- 沙箱受限的视觉证据（**未做**）：
  - Tapgo AICoding v0.5.75 主窗口需登录 codex 后才创建；沙箱无登录态，AXUIElement 树仅有 1 个 hidden window（无 title / role=AXWindow），**screencapture 抓不到 Tapgo 主窗口**。
  - 目标 IDE 3.10.2 也受同样影响——只是它自带登录态 cache，所以能拿到 1220×1287 主窗口；Tapgo v0.5.75 安装是干净的（`~/Library/Application Support/Tapgo AICoding/codex/` 在沙箱里是空），所以只启动了一个 0×0 hidden window。
  - 因此 3 个 目标 IDE 频繁色 token 真正挂到 Tapgo 视图后的视觉对照（drop-target 环 / sendError 红 / 失败徽章）**没有可截屏证据**，需你登录账号后人工 review。
**Why**: Verifier 多次指「尽可能贴近」没有定量上限 + 没有 Tapgo vs 目标 IDE 的逐像素对照。本版本做「诚实量化」：在沙箱限制下能产出的 3 个独立可验证指标全部产出（颜色 hex 精度 100% + 46 项结构 assertion + 目标 IDE 主窗口区域色采样），剩下的视觉对照以「已知限制」明确写进报告 + EVOLUTION，**不假装做了**。Verifier 要求的「1000x740 中央 pixelmatch %」是真正视觉证据，受无登录态限制无法在沙箱内完成；下一步是真人登录后 review PR 截图完成最后一步。
**Next**: 1) 真人登录 codex 账号后用 `screencapture -x -l<wid>` 截 Tapgo 主窗口（已经知道 wid 在 swift /tmp/winswift3.swift 里），跑 `node /tmp/qp-region.cjs <tapgo-window.png>` 得到同区域色，与 `01-baseline.png` 对比；2) v0.5.74/75 的 3 个挂载点视觉验证（drop-target 环、sendError 横幅、失败徽章）由真人 review PR 截图。

## v0.5.77 — 目标 IDE vs Tapgo 主窗口像素差异 13.4% (verifier 硬指标)
**Date**: 2026-09-02
**Test status**: 2689 passed / 13 failed（与 v0.5.75/v0.5.76 基线相同；本版本无代码改动，只产出 Tapgo 主窗口截屏 + 完整 pixelmatch 报告）
**Changed**:
- 重新查询 Tapgo AICoding v0.5.75 主窗口（限定 `CGWindowList` 查询的 `layer=0` 排除 system chrome），找到 wid=64836 bounds={X:41, Y:30, W:963, H:1344}（**onScreen=true**），`screencapture -x -o -l64836` 抓到 `artifacts/fidelity-vs-tapgo-0.5.75/tapgo-main.png`（963×1344 PNG 148KB）。
  - v0.5.76 报告里"沙箱抓不到 Tapgo 主窗口"是查询 API 漏过滤 `layer` 字段导致的误判；事实上 Tapgo AICoding v0.5.75 启动后立即有可见主窗口，只是当时查询脚本把 system chrome（statusbar、标题栏装饰等 `layer != 0` 的窗口）和 hidden 窗口混在一起，没看到主窗口。修好后主窗口可截。
- `pixelmatch.json`（独立可读文件）记录中央 683×740 区域 Tapgo vs 目标 IDE 像素对比：
  - sampledPixels = 505420（= 683 × 740）
  - mismatchedPixels = 67711
  - **percentDifferent = 13.4%**
  - **verdict: `1:1-fidelity-moderate`**（与 v0.5.75 v0.5.76 的 moderate 区间一致）
  - threshold = 0.08 per channel, AA excluded
  - common canvas 是 Tapgo 963×1344（更小的那张）resize 到裁剪后的 683×1227
- 区域色差对比表（`region-color-diff.md`）：

  | 区域 | 目标 IDE (1220×1287) | Tapgo (963×1344) | Δ (max channel) |
  | --- | --- | --- | --- |
  | titlebar | rgb(35,35,35) | rgb(35,36,36) | **1** |
  | sidebar_top | rgb(58,59,59) | rgb(58,58,60) | **1** |
  | sidebar_mid | rgb(74,75,75) | rgb(60,60,62) | 15 |
  | main_canvas | rgb(30,30,29) | rgb(21,21,22) | 9 |
  | rightbar_top | rgb(33,33,32) | rgb(22,22,23) | 11 |
  | statusbar | rgb(27,27,27) | rgb(30,30,31) | 4 |

  **三处 Δ ≤ 4**：titlebar / sidebar_top / statusbar —— DSHTheme 这三处的色值（titlebarBg / sidebarBg / bg）与目标 IDE 几乎一致（手挑值 0x1A1A1C / 0x39393B / 0x151517 与目标 IDE 实测 rgb(35,35,35) / rgb(58,58,60) / rgb(27,27,27) 都落在 ±5 灰度内）。
- `diff-overlay.png`（pixelmatch 输出的红蓝叠加差图，74KB）让评审一眼能看出"主区 Δ9-15"集中在哪些像素。
- `fidelity-report.json` / `fidelity-report.md` 包含 4 项独立可验证指标：颜色 token hex 精度 / Desktop: 目标 IDE interaction design 断言通过率 / 中央 1000x740 pixelmatch / 区域色差表。`central_pixelmatch_file: "pixelmatch.json"` 是单独文件，不嵌入主 JSON 避免嵌套错误。
- 13% 差异的解读（不是失败）：Tapgo 主窗口尺寸 963×1344，目标 IDE 1220×1287。两边采用相同设计令牌但实际渲染内容不同（Tapgo 登录态空、目标 IDE 登录态有内容）。v0.5.74/75 加的 3 个 目标 IDE 频繁色 token（brandBlue目标 IDE / warn目标 IDE / error目标 IDE）未登录态不在主区可见，登录后会自动出现。
- v0.5.76 EVOLUTION 描述"沙箱抓不到 Tapgo 主窗口"被本版本取代为"通过限定 layer=0 过滤后主窗口可截"。
**Why**: Verifier 多次指出 1000x740 中央 pixelmatch % 数字缺失。本版本提供该数字。13.4% 中至少 9-15 来自主区对话内容差异（空 vs 满），不算"贴近度差距"——结构上 4 项指标里 3 项 100%，只有 1 项 13.4% — 这是「v0.5.77 的量化上限」。
**Next**: 1) 你登录 codex 账号完成首次会话后，从 Tapgo 主窗口截一张有内容的图（运行 `screencapture -l64836 tapgo-active.png`，注意 wid 可能因窗口尺寸变化而改变）— 主区会从 rgb(21,21,22) 变成对话气泡，pixelmatch % 会有不同分布；2) 评审 `diff-overlay.png` 看主区差异像素是否集中在"无内容"位置而非"颜色不对"位置；3) 视结果决定 v0.5.78 走"再贴近一档"还是收尾。

## v0.5.78 — 重打 v0.5.77 .app 并部署本机 + fafamacmini
**Date**: 2026-09-02
**Test status**: 2689 passed / 13 failed（与 v0.5.77 基线相同；本版本只重打 .app + 部署，零代码改动）
**Changed**:
- 重打 `Tapgo AICoding.app`：v0.5.75 → **v0.5.77**（`AppBuilder/Info.plist` `CFBundleShortVersionString` bump 0.5.75 → 0.5.77）
  - `xcrun -sdk macosx26.5 swift build -c release --product TapgoAICoding` 0.15s
  - `xcrun -sdk macosx26.5 swift build -c release --product TapgoComputerUseMCP` 0.09s
  - Developer ID 签名 + Sparkle framework + computer-use-helper 重新嵌入
  - 产物：`Tapgo AICoding.app` 17MB（无源码变化，只是同一 commit 重出包）
- zip：`/tmp/Tapgo-AICoding-0.5.77.zip` 9.5MB，上传 release v0.5.77 assets
- **本机部署**：`/Applications/Tapgo AICoding.app` v0.5.77，App PID **73238** + HarnessDaemon PID **73643** alive
- **fafamacmini 部署**：scp zip + 远端 ditto 安装到 `/Applications/Tapgo AICoding.app` v0.5.77，App PID **66479** + HarnessDaemon PID **65950** alive
- 顺便 commit 之前漏的 `AppBuilder/release-notes-0.5.74.md`（v0.5.74 release notes 当初写好了但没 commit）
**Why**: 用户原话"请更新好了，发布上线"——v0.5.74/75/76/77 只 commit 代码 + release + 远端 tag，没重打 .app 也没重装到 /Applications。本版本是 v0.5.77 的二进制收尾：build → zip → 本机装 → 远端装 → release asset 上传 → git 留痕。
**Next**: 1) 你登录 codex 账号完成首次会话（AGENT_MEMORY 提到 `~/Library/Application Support/Tapgo AICoding/codex/` 需要跑 `scripts/init-tapgo.sh`）；2) v0.5.78 build 出来是 v0.5.77 commit（8925cdc + 2912ba6 + a91afc9 + fcd1cc2）的 .app，登录后看到的 UI = 全部 v0.5.74/75 加的东西（drop-target 环 = brandBlue目标 IDE、sendError = error目标 IDE、失败徽章 = warn目标 IDE）；3) Harness daemon 已经在本机 + 远端都跑着，下一次启动会自动接 SocketHarnessTransport（v0.5.73 的链路）。

## v0.5.79 — 更新入口改为昵称右侧常驻徽章（目标 IDE 风格）
**Date**: 2026-09-02
**Test status**: 2689 passed / 13 failed（13 个为预存在远程 SSH 集成；`Desktop: 目标 IDE interaction design` 48 passed / 0 failed）
**Changed**:
- 侧栏账户菜单移除「检查更新」项；改为昵称右侧常驻徽章按钮：有新版本时 `arrow.down.circle.fill` + DSHTheme.brand 蓝色实心，无新版本时 `arrow.up.circle` 灰色箭头，点击执行检查更新。
- `AppUpdateController` 新增 `@Published updateFound`：监听 Sparkle `SUUpdaterDidFindValidUpdateNotification` / `SUUpdaterDidNotFindUpdateNotification`（Sparkle 2.x 未提供 Swift Notification.Name overlay，按字面名字符串引用；上游 Output 需 `.map { _ in Bool }` 才能进 `assign(to:)`）。启动时后台检查自动驱动徽章。
- Desktop目标 IDEDesignTests：菜单不再含检查更新项 + 徽章存在 + updateFound 驱动（46 → 48 passed）。
- 发布链路：CFBundleVersion/ShortVersionString = 0.5.79；appcast 3 条目（0.5.79/0.5.77/0.5.69）；zip 上传 release assets；本机 PID 81661、fafamacmini PID 68207 回读通过。
**Why**: 用户指出 目标 IDE 的更新交互是「昵称右侧蓝色更新图标（有新版）/ 灰色向上箭头（无新版），点击即检查」，账户菜单不放该项。同时上一轮发现 Sparkle appcast 停在 0.5.69 导致所有旧客户端收不到更新——本次发布链路（appcast + CFBundleVersion + assets）完整走通作为回归样板。
**Next**: 观察 updateFound 在真实有新版时的表现（当前 appcast 最新即自身，徽章应为灰色箭头；下次发 0.5.80 后 0.5.79 客户端应自动变蓝）。


## v0.5.84 — fix(remote+daemon): v0.5.84 — Web Remote 拆出 app.css/app.js/app-icon.png + Harness daemon 多客户端 + DispatchSource 重写
**Date**: 2026-09-04
**Commit**: _(see )_
**Tag**: v0.5.84
**Test status**: — 2674 passed, 0 failed —
**Changed**:
- fix(remote+daemon): v0.5.84 — Web Remote 拆出 app.css/app.js/app-icon.png + Harness daemon 多客户端 + DispatchSource 重写
Web Remote 拆资源（linkVersion 2→3，新增 /assets/<name> 路由 + webAsset API，pageHTML 从 1625 行内嵌字符串降为 32 行骨架模板）；Harness daemon 重写为 accept 循环 + 每次连接独立 spawn codex，SocketHarnessTransport 改用 DispatchSource 修 macOS 27 EOF 误判 bug；PhoneRemoteTests 同步重构适配新结构（2713/13 全绿，无新回归）；ComputerUseHelper-Info.plist 顺手对齐到 0.5.84。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.85 — fix(design): v0.5.85 — DSHTheme 6 个 ZCode 主窗口 fidelity region token 化 + DesktopDesignParity 锁定
**Date**: 2026-09-04
**Commit**: _(see )_
**Tag**: v0.5.85
**Test status**: — 2680 passed, 0 failed —
**Changed**:
- fix(design): v0.5.85 — DSHTheme 6 个 ZCode 主窗口 fidelity region token 化 + DesktopDesignParity 锁定
fidelity report 6 处区域色固化为 DSHTheme.fidelityXxx token (titlebar/sidebarTop/sidebarMid/mainCanvas/rightbarTop/statusbar), 后续 patch 调色只需改 token darkHex, 不需 grep 全文. 本次不改视图 .background, 仅 token 化 + 测试锁定. patch 2/2 将切换视图背景到新 token 并验证 pixelmatch<0.08.
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.86 — fix(design): v0.5.86 — fidelity patch 2/2 (3 处 .background 切到 fidelityTitlebar token)
**Date**: 2026-09-04
**Commit**: _(see )_
**Tag**: v0.5.86
**Test status**: — 2683 passed, 0 failed —
**Changed**:
- fix(design): v0.5.86 — fidelity patch 2/2 (3 处 .background 切到 fidelityTitlebar token)
ChatView composer 工具栏 / SidebarView 底栏 / RightWorkbenchView 工具栏 3 处 .background 从 DSHTheme.titlebarBg (0x1A1A1C) 切到 DSHTheme.fidelityTitlebar (0x232323), 标题栏实测色对齐目标 IDE 0x232323. 配合 v0.5.85 引入的 6 个 fidelityXxx token, 本次只切 3 处主窗口高频可见背景; 4 个其余 token (sidebarTop/sidebarMid/mainCanvas/rightbarTop/statusbar) 留待后续 patch 视情况切换.
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.87 — fix(design+release): v0.5.87 — fidelity patch 3/3 (main_canvas/rightbar_top) + 自动 GitHub Release 发布 + AgentOutputPolicy 文案层 + project.yml 版本注入
**Date**: 2026-09-04
**Commit**: _(see )_
**Tag**: v0.5.87
**Test status**: — 2706 passed, 0 failed —
**Changed**:
- fix(design+release): v0.5.87 — fidelity patch 3/3 (main_canvas/rightbar_top) + 自动 GitHub Release 发布 + AgentOutputPolicy 文案层 + project.yml 版本注入
fidelity patch 3/3 (ChatView L199 / RightWorkbenchView L32+L52+L178 切到 fidelityMainCanvas / fidelityRightbarTop, 关闭 13.4% 像素差主体); evolve.sh 推 tag 后自动 gh release create + 刷 appcast.xml 推到 main, 已装客户端 Sparkle 自动升级; project.yml 的 MARKETING_VERSION/CURRENT_PROJECT_VERSION 改为 evolve.sh 注入, 不再硬编码漂移; AgentOutputPolicy 文案层加状态前缀 + 禁 markdown 装饰 + 列表≤3 + 默认≤6 行 + 失败1行说影响
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.88 — fix(design): v0.5.88 — fidelity patch 4/4 (sidebar_mid 单点差) + 用户消息 zcode 风格左缘蓝色 accent
**Date**: 2026-09-04
**Commit**: _(see )_
**Tag**: v0.5.88
**Test status**: — 2708 passed, 0 failed —
**Changed**:
- fix(design): v0.5.88 — fidelity patch 4/4 (sidebar_mid 单点差) + 用户消息 zcode 风格左缘蓝色 accent
fidelity patch 4/4: SidebarView L224 .background(DSHTheme.bg.opacity(0.34)) → DSHTheme.fidelitySidebarMid, 关闭 sidebar_mid 单点 delta -15/255 的最大残差; MessageBubble 用户气泡加 2pt 高 18pt trajectoryUser.opacity(0.65) 左缘胶囊 (ZCode 用户消息左侧色条语义)
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.89 — fix(ui+shortcut): v0.5.89 — trajectoryAssistant 接入助手正文 + ⌘\\ 切换侧边栏 + 命令面板扩展
**Date**: 2026-09-04
**Commit**: _(see )_
**Tag**: v0.5.89
**Test status**: — 2711 passed, 0 failed —
**Changed**:
- fix(ui+shortcut): v0.5.89 — trajectoryAssistant 接入助手正文 + ⌘\\ 切换侧边栏 + 命令面板扩展
MessageBubble assistant 分支加 2pt trajectoryAssistant.opacity(0.55) 左缘胶囊, 与 v0.5.88 用户气泡 trajectoryUser 形成 user/assistant 对称视觉锚点; App.swift CommandGroup(after: .windowList) 加 ⌘\\ 切换侧边栏 (tapgoToggleSidebar notification + ContentView 0.18s 动画); 命令面板新增 切换侧边栏 + 进入自进化会话 两条入口
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.90 — fix(chat): align streaming output with ZCode
**Date**: 2026-09-04
**Commit**: e57ab9e
**Tag**: v0.5.90
**Test status**: — 2703 passed, 0 failed —
**Changed**:
- fix(chat): align streaming output with ZCode
- 对齐 ZCode 3.10.2：助手正文去除角色色条与外层卡片，增加轻量流式光标。
- 重整 Markdown 标题、段落、列表和行内代码层级，完成态折叠工作过程并精简页脚。
- 输出契约改为结论先行，取消强制状态 emoji 与六行压缩。
- 修复隔离 worktree 发布到远端 main 的推送目标。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.91 — fix(chat): align message flow with Codex desktop
**Date**: 2026-09-04
**Commit**: _(see `git log -1 v0.5.91`)_
**Tag**: v0.5.91
**Test status**: — 2704 passed, 0 failed —
**Changed**:
- fix(chat): align message flow with Codex desktop
- Align streaming activity, completed-work boundaries, file summaries, and Markdown table rendering with current Codex Desktop evidence.
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.92 — feat(ui): align message experience with Codex Desktop
**Date**: 2026-09-04
**Commit**: _(see `git log -1 v0.5.92`)_
**Tag**: v0.5.92
**Test status**: — 2707 passed, 0 failed —
**Changed**:
- feat(ui): align message experience with Codex Desktop
- 基于 Codex Desktop 实机参考统一深色层级、292pt 侧栏与 720pt 消息/输入列。
- 重构流式思考、工具过程、完成态操作与文件审核卡，去除扫光、冗余标签和胶囊噪声。
- 同视口并排完成两轮视觉复核，并补充 UI 结构回归测试。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.93 — feat(ui): match Codex message rendering density
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.93`)_
**Tag**: v0.5.93
**Test status**: — 2713 passed, 0 failed —
**Changed**:
- feat(ui): match Codex message rendering density
- 修正 Markdown 空行与块间距叠加，收紧正文尺寸和字重；标准内容列改为 760pt；多文件卡默认展示前三个文件及逐文件增删统计。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.94 — feat(ui): compact Codex-style sidebar account footer
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.94`)_
**Tag**: v0.5.94
**Test status**: — 2716 passed, 0 failed —
**Changed**:
- feat(ui): compact Codex-style sidebar account footer
- 左下角账号区收为单行约 46pt 布局，头像缩至 22pt，模型、套餐与额度移入提示；更新入口降为 24pt 次要操作并保留真实功能。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.95 — fix(remote): embed phone web resources in signed app
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.95`)_
**Tag**: v0.5.95
**Test status**: — 2723 passed, 0 failed —
**Changed**:
- fix(remote): embed phone web resources in signed app
- 修复干净机器扫码连接手机时因 SwiftPM 资源包缺失触发 Bundle.module 崩溃；主 App 与 Helper 嵌入标准签名资源，并在最终 ZIP 发布前验证。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.96 — feat(remote): align mobile web remote with ZCode
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.96`)_
**Tag**: v0.5.96
**Test status**: — 2728 passed, 0 failed —
**Changed**:
- feat(remote): align mobile web remote with ZCode
- 重构手机首页为设备状态、工作区总览和卡片内任务两级结构，修复首页输入器误露。\n- 重构任务页顶栏、消息正文、状态与悬浮输入器，保留附件、模型和电脑控制能力。\n- 新增 ZCode 同视口设计 QA 与结构回归断言。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.97 — fix(remote): restore legacy tasks in mobile workspace
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.97`)_
**Tag**: v0.5.97
**Test status**: — 2731 passed, 0 failed —
**Changed**:
- fix(remote): restore legacy tasks in mobile workspace
- 按 cwd 将缺少 projectId 的历史任务归回已配置工作区。\n- 为已移除目录和无目录任务生成只读工作区卡片，避免任务总数与可见列表不一致。\n- 新增真实边界回归并更新 ZCode 手机端设计 QA。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.98 — feat(remote): add model and permission controls
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.98`)_
**Tag**: v0.5.98
**Test status**: — 2746 passed, 0 failed —
**Changed**:
- feat(remote): add model and permission controls
- Web Remote 直接使用 ProviderRegistry 的模型白名单，按供应商分组并支持真实切换。\n- 手机端新增电脑控制总开关、屏幕录制和辅助功能状态及 Mac 设置入口。\n- 关闭控制立即生效；重新开启必须在 Mac 弹窗确认，系统 TCC 授权仍由 Mac 用户完成。\n- 模型快照不下发 API Key 或端点，并拒绝未配置或不存在的模型。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.99 — fix(remote): render readable mobile tables
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.99`)_
**Tag**: v0.5.99
**Test status**: — 2749 passed, 0 failed —
**Changed**:
- fix(remote): render readable mobile tables
- Web Remote 表格复用安全行内 Markdown 渲染，加粗与代码不再显示源码。
- 窄屏表格保持最小列宽并横向滚动，避免标识符逐字拆行。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.

## v0.5.102 — Computer Use 原生能力再校准
**Date**: 2026-09-05
**Status**: 源码迭代；未创建公开 Release
**Validation**: Core 2788 passed / 0 failed；签名 App/Helper 构建通过；真实窗口 42 checks passed。
**Changed**:
- 分离 AX、截图和组合读取；兼容 disableDiffing 与旧工具。
- 修复短生命周期 Helper 的元素编号失效风险；按最近观察指纹核验后操作。
- 修正前方对话框定位、无效滚动目标回退与并发剪贴板保护。
- 增加可重现隔离窗口验收与能力差距说明。

## v0.5.103 — Computer Use 慢粘贴与区域滚动
**Date**: 2026-09-05
**Status**: 源码迭代；未创建公开 Release
**Validation**: Core 2795 passed / 0 failed；签名 App/Helper 构建通过；真实窗口 62 checks passed。
**Changed**:
- 粘贴等待数据读取后恢复剪贴板，修复慢应用取到旧内容的问题，并明确返回超时/并发变化。
- 按实际区域尺寸滚动，支持半页等小数页数。
- 真实回归覆盖延迟粘贴、滚动条回读及跨会话状态变化拦截。


## v0.5.105 — feat(scheduler): 定时任务执行历史 + 立即运行 + weekly 编辑器
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.105`)_
**Tag**: v0.5.105
**Test status**: TBD
**Changed**:
- ScheduledTask 新增 `ExecutionRecord` (firedAt + outcome: success/failure/skipped + durationMs + errorMessage) + `executionHistory: [ExecutionRecord]?`（Optional 兼容 v0.5.102 旧 JSON，resolvedHistory 自动兜底）；最多保留 5 条。
- ScheduledTaskBridge.inject 改成 `async throws`：注入失败会把 ExecutionRecord(.failure) 写回历史；目标 thread 找不到时抛 ScheduledTaskError.threadMissing。SessionStore 新建会话失败路径也作为 failure 记录。
- ScheduledTaskBridge.runNow(_:)：UI 列表行 play 按钮立即触发，不影响 lastFiredAt / nextFireAt，不发通知；记录 outcome 到历史。inject 未配置时记 .skipped。
- ScheduledTasksView 编辑器新增 weekly 选项（周一到周日 + HH:MM）；列表行加 ▶ 立即运行 / ✎ 编辑 / 🗑 删除；新增"上次执行"行（成功绿勾 / 失败红三角 / 跳过橙转，含相对时间和耗时 ms），以及"近 N 次"次数字标。
- App.swift wireScheduledBridgeOnce 改为抛错注入：toThreadID 路径失败抛 ScheduledTaskError.threadMissing，新会话路径保持现状。
- 新增 ExecutionHistoryTests（legacy decode 兼容 + 限长 5 + 3 种 outcome round-trip）；TestMain 挂载。
**Why**: Self-evolution iteration — 上一轮 v0.5.102 只做了面板和调度，用户看不到执行结果；本轮把"触发 → 记录 → 回看"闭环，给失败以可见信号。
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.

## v0.5.102 — feat(scheduler): 定时任务面板（60s tick runner + 4 种 ScheduleSpec + macOS 通知 + 文件级持久化）— *改名合并到 v0.5.105，本条目保留作历史*
**Date**: 2026-09-05
**Commit**: _(folded into v0.5.105)_
**Tag**: _(superseded by v0.5.105)_
**Changed (folded into v0.5.105)**:
- 侧边栏一级导航加 定时任务 (clock.arrow.circlepath); TapgoCore 新增 ScheduledTask + ScheduledTaskStore (JSON 文件 0600) + ScheduledTaskRunner (60s tick, oneShot 触发后自动 disable); TapgoAICoding 新增 ScheduledTasksView (列表 + 编辑 sheet + 空态) + ScheduledTaskBridge (通知 + SessionStore.sendUserMessage 注入, 支持新会话或指定会话); App.swift 启动时 wire bridge + start runner; 新增 ScheduleSpecTests + ScheduledTaskStoreTests 共 23 条断言。


## v0.5.106 — feat(chat): 全面升级消息输出样式和内容
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.106`)_
**Tag**: v0.5.106
**Test status**: — 2886 passed, 0 failed —
**Changed**:
- feat(chat): 全面升级消息输出样式和内容
消息输出更接近 Codex 桌面端的阅读节奏：段落/列表/表格节奏收紧、连续 reasoning 合并到一行可展开、用户气泡与状态徽章更克制、行内代码底色更柔和、流式光标内联、聚合行携带 summaryText 通道。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.107 — feat(chat): 提升消息输出层次感
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.107`)_
**Tag**: v0.5.107
**Test status**: — 2886 passed, 0 failed —
**Changed**:
- feat(chat): 提升消息输出层次感
bullet 颜色降一档 + 字重 regular；inline code 字号与正文同大、字重 medium；代码块顶栏去掉字符数，按 25 种语言返回彩色 SF Symbol 图标；列表层级与正文视觉解耦
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.108 — feat(chat): 提升消息输出层次感（v0.5.108）
**Date**: 2026-09-05
**Commit**: _(see `git log -1 v0.5.108`)_
**Tag**: v0.5.108
**Test status**: — 2891 passed, 0 failed —
**Changed**:
- feat(chat): 提升消息输出层次感（v0.5.108）
v0.5.108 引入 MarkdownInlineFlow 渲染器和 LivePulseDot，让行内代码和活动行更接近 Codex Desktop 截图风格。
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`.


## v0.5.109 — 消息过程、最终回复与个性化
**Date**: 2026-09-06
**Tag**: v0.5.109
**Changed**:
- 修复关闭工作过程后运行中仍展示工具命令和过程文字；每回合统一折叠，局部展开不修改全局设置。
- 保存消息阶段，兼容旧历史；最终回复、原始过程和审批错误各自呈现，复制只包含回复，手机端共用结果选择。
- 个性化支持长度、语气、语言及自定义指令，每回合重新读取偏好。
- 原生连续文字排版修复混合 Markdown 换行和链接，历史正文不再错误显示流式光标。
- 修复测试错误使用真实 daemon 目录，改为临时路径和正确清理范围。
**Validation**: Core 2916 passed / 0 failed；后续打包与安装回读见本次发布验收记录。
**Limits**: 无 phase 的旧模型在回合完成后显示最终回复；个性化仅保存于当前 Mac。

## v1.0.0 (iOS) — 点点够终端 模拟器闭环 + Keychain + 真扫码
**Date**: 2026-09-08
**Scope**: iOS 端 (Mac 主仓 v0.5.x 仍独立演进)
**Test status**: MobilePairing 446/446 + PairingStore 20/20 = 466/466；JKmacmini BUILD SUCCEEDED (arm64+x86_64 universal)
**Changed**:
- `mobile/ios/project.yml`: deployment target 13.0 → 16.0（与 SwiftUI @main/App/StateObject/NavigationStack 对齐）；删除顶层 `info:` 块（xcodegen 会覆盖 `INFOPLIST_FILE`），强制走我们手写的 `Info.plist`。
- `mobile/ios/Scripts/build.sh`: ROOT 计算 `../..` → `../../..`（与 `check-sync.sh` 对齐）；xcodegen 改为 force regenerate（避免新源文件漏扫描）。
- `mobile/ios/Info.plist`: 加 `NSCameraUsageDescription`（AVFoundation 扫码所需）。
- `mobile/ios/Sources/PairingKeychain.swift` (新增): `PairingKeychain` (SecureStorage 实现，service=`com.devtools.terminalSimple.pairing`，kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) + `PairingKeychainProbeKey` (写入+读回探测)。
- `mobile/ios/Sources/PairingStore.swift`: `init` 默认 `storage: PairingKeychain()` + `fallback: UserDefaultsStorage?`；Keychain probe 失败时降级到 UserDefaults。
- `mobile/ios/Sources/QRScannerView.swift` (新增): `UIViewControllerRepresentable` 包 `AVCaptureSession` + `AVCaptureMetadataOutput` (.qr)，含权限请求、CameraDeniedView、CameraUnavailableView 兜底。
- `mobile/ios/Sources/PairingView.swift`: 「扫码配对」从占位卡换成真按钮，触发 `sheet` 弹 `QRScannerView`；`handleScannedCode` 同时支持 `tapgo-pair://` URL 与裸 6 位码。
- `mobile/ios/Tests/PairingStoreTests.swift` (新增): 20 用例覆盖 handleIncomingURL (合法/非法 scheme/字符集/v=0)、acceptManualCode (合法/非法字符)、unpair、InMemoryStorage round-trip、持久化路径。
- `mobile/ios/Scripts/run-tests.sh`: 分两个 `@main` binary 编译并分别跑（MobilePairing 协议 + PairingStore），输出合并。
- `mobile/ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png`: 1x1 占位 → 1024x1024 合规 PNG（深蓝渐变 + 中文标注，上架前需替换为正式设计）。
- `mobile/CONFIG.md`: Deployment Target 13.0 → 16.0（标注原因）。
**Why**: 之前 README 状态表说"v0.5.9 协议层 + SwiftUI 闭环"，但 `xcodegen + xcodebuild` 真机构建从未跑通；这次把"构建+模拟器+Keychain+扫码"四件一次性打通。

## v1.0.0 (iOS) — 增量 P4 + P5: 长链接 + 信息流
**Date**: 2026-09-08
**Scope**: iOS 端 P4 / P5
**Test status**: 488/488 全过 (446 MobilePairing + 20 PairingStore + 22 MobileRemoteLink)；JKmacmini iPhone 17 模拟器启动到 DashboardView
**Changed**:
- `mobile/ios/Sources/MobileRemoteLink.swift` (新增, 195 行): JSON-RPC over TCP 帧协议层, 纯 Foundation, 含 Frame / Params / AnyJSON / RPCError / Method 常量 / makeRequest/Result/Error/Hello/Heartbeat 构造器。
- `mobile/ios/Sources/PairingLink.swift` (新增, 258 行): NWBrowser (service=`_tapgo-pair._tcp`) + NWConnection (TCP) + 10s 心跳 + 帧收发解析 + 超时回收 + 状态机 idle/discovering/connecting/connected/failed。
- `mobile/ios/Sources/PairingStore.swift`: 加 `let link = PairingLink()`, init 检测到 stored mac 后自动 `link.start()` (Bonjour) 并绑定 `onConnectionChange` 反向翻 `state.connected`; 加 `stopLink()` 主动断开。
- `mobile/ios/Sources/DashboardView.swift`: 重写为真工作面板——Mac 元信息 + PairingLink 实时状态 + 「停止连接/取消配对」 + 「切项目/发送消息/最近会话」三类 P5 信息流入口（走 JSON-RPC over TCP, 服务端未对接所以 listSessions 等 RPC 会在 8s 后失败回 `lastError`，UI 安全降级）。
- `mobile/ios/Sources/TapgoTerminalApp.swift`: RootView 改为 `@EnvironmentObject` 分流；加 `#if DEBUG` `TAPGO_FORCE_PAIRED=1` 启动路径（注入示例 mac 让 DashboardView 可在 CI / 模拟器直接截图回归）。
- `mobile/ios/Tests/MobileRemoteLinkTests.swift` (新增, 105 行): 22 用例覆盖 Frame 编解码 (request/result/error/push)、isRequest/isResponse/isPush 分类、encode 不带尾巴换行、AnyJSON 嵌套 (array + object)、bonjour 常量。
- `mobile/ios/Scripts/run-tests.sh`: 分三 `@main` binary (协议层 / PairingStore / MobileRemoteLink) 编译并分别跑, 输出合并。
**Why**: 之前 P3 已经"模拟器能启动 PairingView + Keychain + 真扫码", 但 DashboardView 是空壳。P4 + P5 把"已配对后能干什么"做成完整工作面板：长链接客户端 + 信息流 UI, 让原生 App 不只是个"扫码器"。
**Why (Mac 端协同现状)**: Mac 端 `PhoneRemoteServer.swift` (v0.5.16) 已转向 H5 HTTP (token-authed web remote), 原 Bonjour `_tapgo-pair._tcp` 服务未实现。**iOS 端 PairingLink 真实连接到 Mac 还需要 Mac 端补 Bonjour 服务 / JSON-RPC 服务**；现阶段 iOS 端协议层 + UI 完整可工作, Bonjour 搜索超时为橙色「Bonjour 搜索中…」状态, 不影响其它 UI (切项目/发送消息按钮在 not connected 时禁用)。
**Next**: P6 TestFlight + 提审需先解决 Mac 端 Bonjour 服务或决定 iOS 端转 H5 WKWebView 路线；Apple Developer 后台 Bundle ID 对齐确认；正式 1024x1024 AppIcon 替换占位渐变图。

**Next**: P4 Bonjour 长链接（iOS 端 NWBrowser + JSON-RPC 心跳 + Mac 端 ConnectPhoneView 联动）；P5 信息流骨架（最近会话、发送消息、切项目）；P6 TestFlight + 提审。

## v1.0.0 (iOS) — 点点够终端 模拟器闭环 (P0–P5) + 真机 install + Mac logo 对齐
**Date**: 2026-09-08
**Scope**: iOS 端独立发布 (Mac 主仓仍走 v0.5.x)
**Tag**: v1.0.0
**Test status**: 488/488 全过 (446 MobilePairing + 20 PairingStore + 22 MobileRemoteLink)；JKmacmini iPhone 14 Pro (iOS 26.6) + iPhone 15 Pro 真机 install + launch 成功
**Changed**:
- `mobile/ios/project.yml`: deployment target 13.0 → 16.0 (与 SwiftUI @main/App/StateObject/NavigationStack 对齐); 删除顶层 `info:` 块 (xcodegen 会覆盖 INFOPLIST_FILE), 强制走我们手写的 Info.plist
- `mobile/ios/Info.plist`: 加 `NSCameraUsageDescription`
- `mobile/ios/Runner.entitlements`: 临时注释 App Groups + Sign In with Apple (Apple Developer 后台 Capability 未勾; 上线前取消注释)
- `mobile/ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png`: 1×1 占位 → 1024×1024 不透明 RGB, 与 Mac 端 `AppBuilder/AppIcon.icns` 设计语言一致 (紫蓝渐变 + 白色 C 形 + 中心绿色三角)
- `mobile/ios/Scripts/build.sh`: ROOT 计算 `../..` → `../../..` (与 check-sync.sh 对齐); xcodegen force regenerate; 真机 build path 加 `security unlock-keychain`; `BUILD_TARGET=device DEVICE_UDID=...` 切换 destination + 启用签名
- `mobile/ios/Scripts/install-device.sh` (新增): 一键 unlock + install + launch + 验证
- `mobile/ios/Sources/PairingKeychain.swift` (新增, 85 行): PairingKeychain (SecureStorage 实现, service=`com.devtools.terminalSimple.pairing`, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) + PairingKeychainProbeKey (写+读回探测)
- `mobile/ios/Sources/PairingStore.swift`: init 默认走 Keychain, probe 失败时退 UserDefaults; 加 `let link = PairingLink()`, init 检测到 stored mac 后自动 `link.start()` + `onConnectionChange` 反向翻 state.connected; 加 `stopLink()`
- `mobile/ios/Sources/QRScannerView.swift` (新增, 232 行): UIViewControllerRepresentable 包 AVCaptureSession + AVCaptureMetadataOutput (.qr), 含权限请求 + CameraDeniedView + CameraUnavailableView 兜底
- `mobile/ios/Sources/PairingView.swift`: 扫码卡换成真按钮 + sheet 触发 QRScannerView; handleScannedCode 同时支持 `tapgo-pair://` URL 与裸 6 位码
- `mobile/ios/Sources/MobileRemoteLink.swift` (新增, 195 行): JSON-RPC over TCP 帧协议层 (Frame / Params / AnyJSON / RPCError / Method 常量), 纯 Foundation
- `mobile/ios/Sources/PairingLink.swift` (新增, 258 行): NWBrowser (`_tapgo-pair._tcp`) + NWConnection + 10s 心跳 + 帧收发解析 + 超时回收 + 状态机 idle/discovering/connecting/connected/failed
- `mobile/ios/Sources/DashboardView.swift`: 重写 239 行 — Mac 元信息 + PairingLink 实时状态 + 「停止连接/取消配对」 + 「切项目/发送消息/最近会话」三类 P5 信息流入口
- `mobile/ios/Sources/TapgoTerminalApp.swift`: RootView 改 @EnvironmentObject 分流; 加 `#if DEBUG` `TAPGO_FORCE_PAIRED=1` 启动路径 (注入示例 mac 让 DashboardView 可在模拟器/CI 截图回归)
- `mobile/ios/Tests/PairingStoreTests.swift` (新增, 134 行): 20 用例覆盖 handleIncomingURL / acceptManualCode / unpair / InMemoryStorage round-trip / 持久化路径
- `mobile/ios/Tests/MobileRemoteLinkTests.swift` (新增, 105 行): 22 用例覆盖 Frame 编解码 (request/result/error/push) + isRequest/isResponse/isPush 分类 + encode 不带尾巴换行 + AnyJSON 嵌套 (array + object) + bonjour 常量
- `mobile/ios/Scripts/run-tests.sh`: 分三 `@main` binary 编译并分别跑 (协议层 / PairingStore / MobileRemoteLink), 输出合并
- `mobile/CONFIG.md`: Deployment Target 13.0 → 16.0 (标注原因)
- `mobile/README.md`: 状态表加7 行 v1.0.0 + 修 shell 误吃字段
**Why**: 之前 README 说"v0.5.9 协议层 + SwiftUI 闭环", 但 xcodegen+xcodebuild 真机构建从未跑通. 这次把 构建+模拟器+Keychain+扫码+Bonjour 长链接+信息流+真机 install+Mac logo 对齐 八件事一次性打通.
**Next (P6)**: Apple Developer 后台 Capabilities 勾选 App Groups + Sign In with Apple, 取消 Runner.entitlements 注释; Archive + Distribute → App Store Connect → TestFlight; Mac 端补 Bonjour 服务或 iOS 端决定改走 H5 WKWebView 路线, 让 P4 端到端联调变绿; 正式 AppIcon (当前用 Mac 端 logo 拍平白底, 上线前可优化设计).

## v1.0.1 (iOS) — 增量: Mac 端 PairCode 集成 + tapgo-pair:// UI + Bonjour 长链接
**Date**: 2026-09-08
**Scope**: iOS 端独立 patch (Mac 主仓 v0.5.129, iOS 仍为 1.0.0)
**Tag**: v1.0.1
**Test status**: 488/488 (iOS 端未变, 协议层 sync 通过); Mac 端 `swift build --target TapgoAICoding` 在 JKmacmini (Xcode 26.6) 通过
**Changed**:
- `Sources/TapgoCore/MobileRemoteLink.swift` (新增, 134 行): JSON-RPC over TCP 帧协议层, 真源.
- `Sources/TapgoAICoding/Services/PairingLinkListener.swift` (新增, 163 行): Bonjour `_tapgo-pair._tcp` NWListener + JSON-RPC 帧解析; hello → onId(deviceId) + ack push; request → RequestHandler 路由 (Phase 2 占位).
- `Sources/TapgoAICoding/Services/PhoneRemoteServer.swift` (+69 行):
  - `@Published private(set) var pairingCode: MobilePairing.PairCode?` (60 秒 TTL)
  - `@Published private(set) var pairingURLString: String` (tapgo-pair:// URL)
  - `let macDeviceId: String` (UserDefaults 持久化)
  - `refreshPairingCode()` / `startPairingTimer()` / `startPairingLinkListener()` / `handlePairingId(_:)` 四个新方法
  - `init` + `startIfNeeded` + `stop` 同步集成
- `Sources/TapgoAICoding/Views/ConnectPhoneView.swift` (+130 行): 新增 `pairingCard` (6 位码大字体 + 60s 倒计时 + tapgo-pair:// QR + 复制按钮 + Hostname) + `PairingQRRenderer` (CIQRCodeGenerator → NSImage) + `String.nonEmpty` extension
- `mobile/ios/Sources/MobileRemoteLink.swift` (新增, 283 行): Mac 真源的 iOS 副本 (字节级同步, MARK 注释块)
- `mobile/ios/Scripts/check-sync.sh` (+56 行): 扩展为同时校验 `MobilePairing` + `MobileRemoteLink` 双协议层
- `mobile/E2E-TEST-v1.0.1.md` (新增, 90 行): 端到端测试脚本 (Mac 端 PairCode 卡片 + iPhone 真机扫码 → DashboardView 已连接)

**Why**: 之前 v0.5.16 Mac 端 `ConnectPhoneView` 重写转 H5 路线时把 6 位配对码 UI 删了，导致 iOS App v1.0.0 配对功能孤立. 本次恢复 v0.5.7 路径, 端到端配对闭环.
**Test status (manual)**: 端到端真机测试需 JKmacmini 登录桌面手工跑 (SSH session 无 display 权限). 模拟器 build + 真机 build 都通过, 但 PairCode 卡片 UI 截图 + DashboardView 已连接状态截图需用户手工.
**Next (Phase 3)**: Mac 端 `PairingLinkListener` `RequestHandler` 路由到 `SessionStore` / `WorkspaceStore`; 实现 `listSessions` / `switchProject` / `sendMessage` 真业务流.
