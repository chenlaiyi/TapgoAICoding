# Tapgo AICoding 0.5.101

手机端 composer 输入框旁权限按钮改为下拉菜单（3 档），按用户反馈的「请求批准 / 帮我批准 / 完全访问权限」最常用档位。

## 修复

- H5 composer-bar 输入框旁的「电脑操作」按钮改为 `权限 ▾` 下拉菜单：
  - **请求批准** — 每次写操作在手机端弹批准请求 (`approvalPolicy=on-request`)
  - **帮我批准** — 全自动批准 (`approvalPolicy=never`)
  - **完全访问权限** — 全自动 + 完全访问不限制 (`sandboxMode=danger-full-access`)
- 新增 `POST /api/permissions {profile:"request|auto|full"}` 后端端点，写入 `TapgoConfig.approvalPolicy` + `sandboxMode`（仅 full 时）。
- `PhoneRemote.StateSnapshot` 新增 `permissions: {sandbox, approval}` 字段，composer 按钮文字同步显示当前档位（如「完全访问权限」），下拉高亮当前选中档。

## 范围说明

- 完整权限抽屉（屏幕录制 / 辅助功能）仍通过原电脑控制抽屉进入，下拉菜单暂未挂载入口。
- 不影响 macOS 系统授权（屏幕录制 / 辅助功能），后者仍需 Mac 端手动确认。

## 测试

- 2801 通过 / 13 失败，13 个全是预先存在的远程 SSH 集成 + helper version tag 一次性断言，无回归。
- Core 端 `PhoneRemote.buildState` 接受 `permissions` 实参；App 端 `applyPermissionProfile` 写入后立即被下次轮询带回。