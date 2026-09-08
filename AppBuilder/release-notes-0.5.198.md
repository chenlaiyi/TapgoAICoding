# Tapgo AICoding 0.5.198

## FileChangeView / RowView statusBadge 对齐 Codex 桌面端：inFlight 状态用 3 跳动 dots

延续 v0.5.192/194/195 的"running 用 3 跳动 dots"统一风格，FileChangeView / FileChangeRowView 的 statusBadge 在 `change.status == .pending` 或 `.awaitingApproval` 时把静态 `clock` / `hand.raised` 图标替换为 3 个错开 0.2s 的 3pt 圆点 + `.easeInOut.repeatForever(autoreverses: true)` 动画，背景色和文字保留（"待应用"/"待批准"），与 v0.5.192/194/195 风格一致。

## 改动

- `Sources/TapgoAICoding/Views/FileChangeView.swift`:
  - `FileChangeRowView.statusBadge` 加 `@State pulse` + inFlight 分支：3 个错开 0.2s 的 3pt 圆点 + 0.6s repeatForever 动画替换原 `Image(systemName:)`。
  - 静态 icon 仅在非 inFlight 状态（已应用/失败/已拒绝）渲染。

## 测试

未跑（纯 UI 改动不影响逻辑）。
