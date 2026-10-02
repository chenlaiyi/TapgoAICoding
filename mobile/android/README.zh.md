# Tapgo Android

[English](README.md) | 中文

Android 应用支持 Android 8.0 及以上版本。原生欢迎页使用桌面端的小点点形象、名称、标语和浅色／深色配色。通过 Mac 或 Windows 提供的 HTTPS 二维码、粘贴链接或 `dsh-mobile` 深链接配对。扫码在设备本地运行，无需 Google Play 服务。配对链接和自定义电脑名称使用 Android Keystore 密钥加密，保存在应用私有目录，并禁用备份。Web 登录 Cookie 另存于 WebView 存储。重新配对同一来源会保留自定义名称。移除连接只移除保存的配对记录，不删除 Host 数据或已经签发的 Host Cookie。

原生首页展示 Host 的真实会话，支持搜索、最近优先、项目分组、电脑切换、重命名与移除连接。前台每 15 秒刷新。首页确认使用与 iOS 相同的 `$events` 流：允许一次、拒绝、交给电脑处理，或回答单选／多选问题并填写其他答案。连接每 20 秒发送心跳，重连等待最多 30 秒。进入后台或完整工作区接管交互流时停止该连接。

对话采用原生消息界面，支持 Markdown、流式回复、按轮次折叠的推理与工具完成状态、发送／停止、模型选择、权限确认及可预览／移除的系统选择器照片附件。新对话可选择已登记项目，或登记／创建目录，并记住每台电脑最后选择的模型。Host 提供余额时请求展示。文件与终端仍通过限制来源的 WebView 打开完整 Host 工作区。照片使用系统选择器，尚未实现直接拍照或历史图片展示。原生设置在 Host 提供数据时显示主币种充值／赠送余额、会话令牌用量和可用上下文。同源跳转允许；跨站跳转、明文 HTTP、混合内容、本地文件加载和原生 JavaScript 桥接均禁用。TLS 错误不会被忽略。

## 构建

使用 JDK 17、Android SDK 平台 36／构建工具 36.0.0 与固定版本的 Gradle wrapper。配置 `ANDROID_HOME`，或在忽略的 `local.properties` 中填写 `sdk.dir`。运行 `./gradlew testDebugUnitTest assembleDebug lintDebug`。调试 APK 位于 `app/build/outputs/apk/debug/app-debug.apk`，属于测试构建，并非正式发布。企业提供 Android 签名配置前，`assembleRelease` 生成未签名 APK。禁止提交签名密钥或密码。应用标识为 `com.tapgo.terminal`。

## 隔离模拟器测试

使用未保存真实配对数据的专用模拟器。仅调试版的网络配置在 `localhost` 信任公开夹具证书；正式构建不包含该证书及信任配置。生成 DNS SAN 包含 `localhost`，IP SAN 包含 `10.0.2.2`、`127.0.0.1` 的自签名夹具证书及私钥，将证书放在 `app/src/debug/res/raw/fixture_ca.pem`，私钥留在 Git 之外。设置 `TAPGO_ANDROID_FIXTURE_KEY` 为私钥路径，并在本目录运行 `node tests/fixture-server.mjs`。服务自动分配主机回环端口，输出就绪状态和已分配端口，使用虚拟令牌与会话。使用 `adb -s <serial> reverse tcp:9443 tcp:<printed-port>` 转发专用模拟器端口，然后运行 `./gradlew connectedDebugAndroidTest`；独立单元测试覆盖链接校验及来源比较。测试后停止夹具和模拟器。夹具验证 Android 传输与交互回复，不等于真实账号模型执行或实体相机扫码验收。
