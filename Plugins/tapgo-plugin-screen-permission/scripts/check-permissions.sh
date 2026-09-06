#!/usr/bin/env bash
# macOS 屏幕录制 + 辅助功能 授权自检（依赖 sqlite3）
set -euo pipefail

check() {
    local name="$1" bundle="$2" service="$3"
    local db="/Library/Application Support/com.apple.Tcc/Tcc-originals.db"
    local status="未知"
    if [[ -r "$db" ]]; then
        local hit
        hit=$(sqlite3 "$db" "SELECT auth_value FROM access WHERE service='$service' AND client='$bundle' LIMIT 1;" 2>/dev/null || true)
        case "${hit:-}" in
            2) status="已授权" ;;
            0) status="已拒绝" ;;
            *) status="未设置" ;;
        esac
    fi
    echo "[$name] $bundle -> $status"
}

echo "Tapgo 屏幕录制 / 辅助功能 自检"
check "屏幕录制" "com.tapgo.aicoding" "kTCCServiceScreenCapture"
check "辅助功能" "com.tapgo.aicoding" "kTCCServiceAccessibility"

cat <<'TIP'
如未授权，先在 系统设置 → 隐私与安全性 勾选 Tapgo AICoding，然后**完全退出并重启** App。
TIP
