# Tapgo AICoding 0.5.68

- 检查更新弹窗改为简体中文：此前 Sparkle 更新提示（检查更新/已是最新/安装更新等）始终显示英文。
- 根因有二：应用 Info.plist 从未声明 `CFBundleLocalizations`，Sparkle 按声明语言回退英文；系统语言标记为 zh-Hans-US（现代写法），而 Sparkle 框架只带旧命名 zh_CN.lproj，两者对不上时同样回退英文。
- 修复：Info.plist 声明 zh-Hans/zh_CN/en；构建脚本在嵌入 Sparkle 框架时把 zh_CN.lproj 镜像为 zh-Hans.lproj。系统菜单栏（文件/编辑等）也随之正确显示中文。
- 真机验证：点击检查更新，弹窗显示"您使用的就是最新版！Tapgo AICoding 0.5.67 是当前的最新版本。"及"好"按钮。
