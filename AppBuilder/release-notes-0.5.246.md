# Tapgo AICoding 0.5.246

## 时间线组织视图(已置顶 / 最近任务分节)

- 侧栏模式菜单新增「**时间线**」选项，与「所有任务」「按项目分组」并列（菜单文本对应 `SidebarViewMode.timeline`）。
- 时间线视图把会话拆为两个分节：
  - **已置顶** —— `isPinned == true` 的会话单列一节（无项目缩进），默认按更新时间倒序。
  - **最近任务** —— 其余会话按 `updatedAt` 倒序排列。
- 复用既有 `sidebarSectionHeading` 与 `threadRow`：置顶/取消置顶、hover 操作按钮、双击重命名、右键菜单、搜索全部沿用，不引入新交互。
- 选择通过 `@AppStorage` 本地持久化，下次启动仍是时间线视图。

未做：ZCode 的分节拖拽重排与展开状态持久化（设计成本高于本轮范围），边界停在「可看、可切、可置顶/取消置顶」。

实据来源：ZCode.app 应用包源码（`workspaceSidebar.sectionOrder` / `projectsExpanded` / `conversationsExpanded`）。

## 测试

- 全量回归 3145 通过（12 个失败均为存量远端集成环境问题，与本改动无关）。