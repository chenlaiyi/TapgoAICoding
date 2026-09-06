#!/usr/bin/env bash
# Sparkle 一键发版封装：转发到 TapgoAICoding 仓库自带脚本。
# 本脚本是 Tapgo 官方插件的一部分，路径 ~/.tapgo/plugins/tapgo-plugin-sparkle-publish/scripts/
set -euo pipefail

# TapgoAICoding 仓库根目录可通过环境变量覆盖；默认假设当前 cwd 是仓库根。
ROOT="${TAPGO_ROOT:-$(pwd)}"
exec "$ROOT/scripts/create-github-release-artifacts.sh"
