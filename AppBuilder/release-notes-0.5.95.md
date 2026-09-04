# Tapgo AICoding 0.5.95

- 修复干净安装的 Mac 扫描“连接手机”二维码后，因发布包缺少 SwiftPM 网页资源而触发 `Bundle.module` 断言并退出的问题。
- 主 App 与内置 Computer Use Helper 均将手机网页资源嵌入标准 `Contents/Resources` 目录，并纳入 Developer ID 签名。
- 已打包 App 不再用可能崩溃的 `Bundle.module` 查找可选资源；资源异常时安全降级，避免整个 App 退出。
- 构建及 GitHub 发布脚本新增四项网页资源的源目录、App、Helper 和最终 ZIP 清单校验，防止同类漏包再次发布。
- 在移除外部 `.build` 资源包后完成发布 App 回归：页面、CSS、JS、图标和状态 API 均为 HTTP 200，进程保持存活且无新增崩溃报告。
