#!/usr/bin/env bash
# install-evolution-maintenance.sh — 安装/卸载自进化月度维护 launchd 任务（EVO-032）。
#
# 用法：
#   ./scripts/install-evolution-maintenance.sh              # 安装并注册（每月 1 日 10:00）
#   ./scripts/install-evolution-maintenance.sh --run-now     # 安装后立即跑一次维护
#   ./scripts/install-evolution-maintenance.sh --print       # 只渲染 plist 到 stdout，不落盘
#   ./scripts/install-evolution-maintenance.sh --uninstall   # 停止并删除 LaunchAgent
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.tapgo.aicoding.evolution-maintenance"
TEMPLATE="$REPO_ROOT/scripts/launchd/$LABEL.plist"
MAINTENANCE_SCRIPT="$REPO_ROOT/scripts/evolution-maintenance.sh"
APP_SUPPORT="$HOME/Library/Application Support/Tapgo AICoding"
STATE_DIR="$APP_SUPPORT/state"
LOG_DIR="$HOME/Library/Logs/TapgoAICoding"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS/$LABEL.plist"
PATH_VALUE="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

MODE="install"
case "${1:-}" in
  --uninstall) MODE="uninstall" ;;
  --print) MODE="print" ;;
  --run-now) MODE="run-now" ;;
  "") MODE="install" ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  *) echo "ERROR: unexpected arg: $1" >&2; exit 2 ;;
esac

[[ -f "$TEMPLATE" ]] || { echo "ERROR: plist template missing: $TEMPLATE" >&2; exit 1; }

render() {
  sed -e "s|__REPO_ROOT__|$REPO_ROOT|g" \
      -e "s|__MAINTENANCE_SCRIPT__|$MAINTENANCE_SCRIPT|g" \
      -e "s|__STATE_DIR__|$STATE_DIR|g" \
      -e "s|__LOG_DIR__|$LOG_DIR|g" \
      -e "s|__PATH__|$PATH_VALUE|g" \
      "$TEMPLATE"
}

if [[ "$MODE" == "print" ]]; then
  render
  exit 0
fi

if [[ "$MODE" == "uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  echo "已卸载：$LABEL"
  echo "  plist: $PLIST_PATH"
  exit 0
fi

[[ -x "$MAINTENANCE_SCRIPT" ]] || { echo "ERROR: 维护脚本不可执行：$MAINTENANCE_SCRIPT" >&2; exit 1; }

mkdir -p "$LAUNCH_AGENTS" "$LOG_DIR" "$STATE_DIR"
render > "$PLIST_PATH"
chmod 0644 "$PLIST_PATH"
plutil -lint "$PLIST_PATH" >/dev/null || { echo "ERROR: 渲染出的 plist 非法" >&2; exit 1; }

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true

echo "已安装：$LABEL（每月 1 日 10:00）"
echo "  plist:   $PLIST_PATH"
echo "  script:  $MAINTENANCE_SCRIPT"
echo "  history: $STATE_DIR/maintenance_history.jsonl"
echo "  logs:    $LOG_DIR/evolution-maintenance{,.err}.log"

if [[ "$MODE" == "run-now" ]]; then
  echo "立即执行一次维护..."
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  echo "已触发；查看：tail -20 $LOG_DIR/evolution-maintenance.log"
else
  echo "查看状态：launchctl print gui/\$(id -u)/$LABEL | head -20"
  echo "立即跑一次：./scripts/install-evolution-maintenance.sh --run-now"
fi
