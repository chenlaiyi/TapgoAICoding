# Tapgo AICoding 0.5.232

## 修复：电脑控制 helper 签名（防止 Launch failed 复发）

- build-app.sh：`--deep` 外层签名后显式签嵌套 helper（防 ditto/copy 丢签名）。
- TapgoConfig：复制 helper 到 App Support 后用 `codesign --force --deep --sign -` 重签。
- ConversationPresentationTests：修正 workTitle 断言（已处理 → 用时 → 已处理 1 分钟 5 秒）。

## 测试

全量回归 3145 通过 + 三机安装回读。
