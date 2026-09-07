# P6 TestFlight + App Store 提审检查清单

> 点点够终端 v1.0.0 上线执行清单。完成 P5 后, 这是从「能跑」到「上架」的最后一段。
> 所有带 ☐ 的项需要人工操作或在 Apple Developer 后台执行。

## 阶段 1: Apple Developer 后台 Capability 勾选

**Account**: https://developer.apple.com/account

- ☐ 登录 Apple Developer Account, 选 Team `KF2CE24685` (Fujian Tapgo Bussiness Management Co., Ltd)
- ☐ Certificates, Identifiers & Profiles → Identifiers → 选 `com.devtools.terminalSimple` (若不存在则 App IDs → + 新建)
- ☐ Capabilities 勾选:
  - ☐ **App Groups** (勾选后 Edit → Register New Group: `group.com.devtools.terminalSimple`)
  - ☐ **Sign In with Apple**
  - ☐ **Push Notifications** (可选, 上线前再开)
  - ☐ **Associated Domains** (可选, 用于 Universal Links)
- ☐ Save + 重新生成 Provisioning Profile: Profiles → Development / Distribution → `iOS Team Provisioning Profile: *` → 选 `com.devtools.terminalSimple` + 上述 Capabilities → Generate → Download
- ☐ 双击下载的 .mobileprovision 让 Xcode 装入

## 阶段 2: 取消 Runner.entitlements 注释

本地仓库 `mobile/ios/Runner.entitlements` 当前是注释状态 (真机 build 绕开 Capability 缺失). 后台勾选后:

```bash
cd ~/TapgoAICoding/mobile/ios
python3 << 'PYEOF'
p = 'Runner.entitlements'
s = open(p).read()
# 去掉注释标记 (从 <!-- ... --> 恢复成正常 <key>...</key>)
import re
s = re.sub(r'<!--\s*', '', s)
s = re.sub(r'\s*-->', '', s)
open(p, 'w').write(s)
print('entitlements uncommented')
PYEOF
```

或者用 `git blame Runner.entitlements` 看 v0.5.9 时被注释掉的原始内容, 手工恢复.

## 阶段 3: 真机构建冒烟回归

```bash
cd ~/TapgoAICoding/mobile/ios
BUILD_TARGET=device DEVICE_UDID=A35FE5C0-C4C1-5438-8243-B8645E02AAF9 ./Scripts/build.sh
./Scripts/install-device.sh A35FE5C0-C4C1-5438-8243-B8645E02AAF9 JK14pro
```

期望: build SUCCEEDED + 真机 install + launch + DashboardView 正常.

## 阶段 4: Archive + Export + TestFlight 上传

```bash
cd ~/TapgoAICoding/mobile/ios
./Scripts/archive.sh                    # app-store 模式 (默认)
# 或 ./Scripts/archive.sh development  # TestFlight 灰度
```

Archive 流程:
1. **xcodebuild archive** → `build/TapgoTerminal.xcarchive`
2. **xcodebuild -exportArchive** → `build/Export/点点够终端.ipa`
3. **xcrun altool --upload-app** → App Store Connect (需 App Manager API Key)

App Manager API Key 准备:
- ☐ App Store Connect → Users and Access → Integrations → Team Keys → Generate (Individual Key)
- ☐ 记下 Key ID + Issuer ID, 下载 .p8 文件放到 `~/.appstoreconnect/private_keys/AuthKey_XXXX.p8` (本地, 不入仓)
- ☐ 跑 `xcrun altool --upload-app --type ios --file ./点点够终端.ipa --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>`

## 阶段 5: App Store Connect 关联 Build

- ☐ 登录 https://appstoreconnect.apple.com
- ☐ My Apps → 点点够终端 → TestFlight
- ☐ 选刚才上传的 build (1.0 / build 1) → 看到 "Processing" → 等几分钟变成 "Ready to Submit"
- ☐ 添加测试员: 内部组 (团队成员, 自动通过) 或外部组 (需审核邮箱)
- ☐ 灰度跑 2-3 天 (可选)
- ☐ 准备上架元数据:
  - ☐ 截图 (6.7", 6.5", 5.5" 三种尺寸, 每种 1-10 张)
  - ☐ 描述 (中文 + 英文)
  - ☐ 关键词
  - ☐ 隐私政策 URL (若启用 Sign In with Apple 必须)
  - ☐ App Privacy 问卷 (数据收集声明)
- ☐ 选 build → 提交审核 (一般 24-48h 通过)

## 阶段 6: 上线后

- ☐ App Store Connect → Pricing and Availability 设价格 (免费 / 付费)
- ☐ App Store Connect → App Privacy 完整填写
- ☐ App Store Connect → 准备本地化版本
- ☐ 监控 TestFlight 反馈, 修 bug 后 v1.0.1 patch

## 自动可执行 (无需手工)

- `mobile/ios/Scripts/run-tests.sh` → 488/488 通过
- `mobile/ios/Scripts/build.sh` (模拟器) → BUILD SUCCEEDED
- `mobile/ios/Scripts/build.sh` (真机) → BUILD SUCCEEDED
- `mobile/ios/Scripts/install-device.sh` → install + launch
- `mobile/ios/Scripts/archive.sh` → archive + export + altool 调用 (需 API Key)

## 检查清单进度

- [x] P0–P5 iOS 端代码 + 单元测试 488/488
- [x] iPhone 14 Pro / 15 Pro 真机 install + launch 验证
- [x] AppIcon 与 Mac 端 logo 对齐
- [x] mobile/README.md + EVOLUTION.md + mobile/CONFIG.md 同步
- [x] mobile/release-notes-1.0.0.md 写好
- [x] mobile/ios/Scripts/archive.sh 准备 (Archive + Export + Altool)
- [ ] Apple Developer 后台 Capability 勾选 (人工)
- [ ] Runner.entitlements 取消注释 (人工)
- [ ] Archive + TestFlight 上传 (脚本就绪, 等 capability 勾选后跑)
- [ ] App Store Connect 关联 build + 提审 (人工)
- [ ] 正式 AppIcon 设计优化 (可选)
- [ ] Mac 端 Bonjour 服务实现 或 iOS 端改 H5 路线 (P4 端到端联调)
