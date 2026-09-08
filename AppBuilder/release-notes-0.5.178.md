# Tapgo AICoding 0.5.178

## Sidebar project group header 的 + 和 more 按钮 opacity 0.25 → 0.6

之前 sidebar 项目 group header 的"+"按钮和 more menu 按钮在非 hover 时 opacity = 0.25（25%），用户不知道有这些按钮。改 0.6（60%）让按钮总是可见，hover 时变 1.0。

- `Sources/TapgoAICoding/Views/SidebarView.swift`:
  - project group header 的 + 按钮和 projectMoreMenu `.opacity(hoveredProjectId == p.id ? 1 : 0.25)` → `0.6`。

测试：3116 passed / 13 failed（baseline 一致）。开发者签名有效；尚未完成 Apple 公证。
