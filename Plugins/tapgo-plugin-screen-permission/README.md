# tapgo-plugin-screen-permission

Tapgo 官方插件：macOS 屏幕录制与辅助功能权限自检。

安装后运行：

```sh
~/.tapgo/plugins/tapgo-plugin-screen-permission/scripts/check-permissions.sh
```

输出当前授权状态，缺一项时打印 `open` 命令直达 系统设置对应面板。

## 已知与 TapgoAICoding 的关系

TapgoAICoding 的电脑控制（screenshot / click / AX 读取）依赖这两项 TCC 权限；
授权后必须**完全退出并重启** TapgoAICoding 才生效。
