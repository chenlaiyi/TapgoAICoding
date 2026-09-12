#!/usr/bin/env bash
# fleet-hosts.sh — 三机部署目标的唯一真源。
#
# 由 scripts/deploy-fleet.sh 与 scripts/evolution-preflight.sh source。
# 主机名/路径只在这里维护，避免预检与实际部署漂移；source 时无副作用。

# 远端目标：<ssh-host>:<repo-path>
TAPGO_FLEET_TARGETS=(
  "jkmacmini:/Users/chanlaiyi/TapgoAICoding"
  "chenlaiyi@100.100.191.111:/Users/chenlaiyi/TapgoAICoding"
)

# 本机在 deploy-fleet.sh --only/--exclude 里的目标名
TAPGO_FLEET_LOCAL="local"
