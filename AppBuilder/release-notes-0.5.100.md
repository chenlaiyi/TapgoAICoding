# Tapgo AICoding 0.5.100

添加远程主机/项目可用性回归。SwiftUI `Form` 在 macOS 上会阻断 `@State` 与 NSTextField 的双向绑定，导致"保存"按钮永远 disabled；改成自绘字段 + 实时校验后下划线/中文等真实命名的主机也能成功添加。

## 修复

- `SettingsView.AddRemoteHostSheet`：去掉 `.formStyle(.grouped)`，改用直接 `TextField(_, text: $binding)` + 自定义 `canSave` 校验；保存按钮的 `disabled` 现在实时反映字段合法性。
- 新增 `RemoteCommandBuilder.validateAlias(_:)` 公开校验函数，alias / host / user 各自的错误信息分别精确提示（"别名只允许字母/数字/点/下划线/连字符" / "主机含非法字符" / "用户只允许…"）。
- 端口字段改用 `String` + `Int()` 解析，非法端口给红色错误（覆盖之前的 silently disabled），范围限制 1–65535。

## 测试

- 新增 14 个 v0.5.100 验证：host / user / alias 含下划线（`mac-mini_jk` / `john_doe` / `dev_box`）必须通过；空格 / 斜杠 必须拒绝。
- `RemoteCommandBuilder` 4 节测试共 47 个断言全绿。
- 总体回归 2802 通过 / 12 失败（12 个全是预先存在的远程 SSH 集成测试，与本版本无关）。

## 影响

- 之前：用户报告"不能配置主机 / 无法添加远程项目"。保存按钮永远 disabled，alias 含中文/特殊字符无法保存。
- 现在：字段填完后保存按钮即时启用；非法字段会立刻显示精确的红字错误。已在本机实测添加 `mac-mini_jk` / `chenlaiyi@192.168.1.20:22` 成功。