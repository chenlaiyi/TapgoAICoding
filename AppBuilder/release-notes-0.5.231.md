# Tapgo AICoding 0.5.231

## 修复：新任务态显示电脑操作 chip

- `computerControlChip` 移除 `!isWelcome` 排除——新任务（welcome）态也显示电脑操作图标 + 状态点，对齐 Codex 实机底栏在所有状态下都稳定可见的行为。

## build-app.sh 修复

- 嵌套 helper `Tapgo Computer Use.app` 显式独立签名（先 `--deep` 移除旧签名，再单独签），防止「Launch failed」。

## 测试

全量回归 3143 通过 + 三机安装回读。
