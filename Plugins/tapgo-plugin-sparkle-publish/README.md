# tapgo-plugin-sparkle-publish

Tapgo 官方插件：Sparkle 一键发版辅助。

安装到 `~/.tapgo/plugins/tapgo-plugin-sparkle-publish/` 后，在 TapgoAICoding 仓库根目录运行：

```sh
~/.tapgo/plugins/tapgo-plugin-sparkle-publish/scripts/publish-sparkle.sh
```

等价于手动跑：

```sh
./scripts/create-github-release-artifacts.sh
```

仅做封装，不引入新逻辑；版本号由 `AppBuilder/Info.plist` / git tag 决定。
