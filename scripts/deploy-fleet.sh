#!/usr/bin/env bash
# deploy-fleet.sh — install one verified .app build on all three Macs.
#
# Targets (fixed by AGENTS.md):
#   local          = this machine (fafa's Mac mini)
#   jkmacmini      = chanlaiyi@jkmacmini
#   chenlaiyi-mbp  = chenlaiyi@100.100.191.111
#
# The script copies the already-built bundle (same bytes locally and remotely),
# re-signs ad-hoc on the target when the original signature is not portable,
# restarts the app, then reads back version + PID. It never builds or pulls.
#
# Usage:
#   ./scripts/deploy-fleet.sh                 # version from AppBuilder/Info.plist
#   ./scripts/deploy-fleet.sh 0.5.257
#   ./scripts/deploy-fleet.sh --dry-run 0.5.257
#   ./scripts/deploy-fleet.sh --restart-local # also restart the local GUI app
#   ./scripts/deploy-fleet.sh --only jkmacmini 0.5.282      # canary host only
#   ./scripts/deploy-fleet.sh --exclude jkmacmini 0.5.282   # remaining hosts
#
# NOTE: --restart-local kills the currently running Tapgo AICoding, which may
# terminate the Codex session driving this script. It is opt-in for that reason.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN=""
RESTART_LOCAL=""
ONLY_HOST=""
EXCLUDE_HOST=""
VERSION=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --restart-local) RESTART_LOCAL=1 ;;
    --only) ONLY_HOST="${2:-}"; shift ;;
    --exclude) EXCLUDE_HOST="${2:-}"; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) [[ -z "$VERSION" ]] || { echo "ERROR: unexpected arg: $1" >&2; exit 2; }; VERSION="$1" ;;
  esac
  shift
done
[[ -z "$ONLY_HOST" || -z "$EXCLUDE_HOST" ]] || { echo "ERROR: --only and --exclude are mutually exclusive." >&2; exit 2; }
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' AppBuilder/Info.plist)}"
APP="$ROOT/Tapgo AICoding.app"
BIN_REL="Contents/MacOS/TapgoAICoding"
[[ -d "$APP" ]] || { echo "ERROR: $APP missing; run scripts/build-app.sh first." >&2; exit 3; }
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$BUILT" == "$VERSION" ]] || { echo "ERROR: bundle $BUILT != requested $VERSION" >&2; exit 3; }

# 部署目标来自 scripts/fleet-hosts.sh（唯一真源，预检脚本共用）。
# shellcheck source=scripts/fleet-hosts.sh
source "$ROOT/scripts/fleet-hosts.sh"
ALL_TARGETS=("${TAPGO_FLEET_TARGETS[@]}")
TARGETS=()
for target in "${ALL_TARGETS[@]}"; do
  host="${target%%:*}"
  [[ -n "$ONLY_HOST" && "$host" != "$ONLY_HOST" ]] && continue
  [[ -n "$EXCLUDE_HOST" && "$host" == "$EXCLUDE_HOST" ]] && continue
  TARGETS+=("$target")
done

INCLUDE_LOCAL=1
[[ -n "$ONLY_HOST" && "$ONLY_HOST" != "local" ]] && INCLUDE_LOCAL=0
[[ -n "$EXCLUDE_HOST" && "$EXCLUDE_HOST" == "local" ]] && INCLUDE_LOCAL=0

install_local() {
  local dest="/Applications/Tapgo AICoding.app"
  echo "==> [local] installing v${VERSION}"
  if [[ -n "$DRY_RUN" ]]; then
    echo "    [dry-run] rm -rf $dest && ditto '$APP' $dest"
    return 0
  fi
  rm -rf "$dest"
  ditto "$APP" "$dest"
  local got
  got="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$dest/Contents/Info.plist")"
  [[ "$got" == "$VERSION" ]] || { echo "ERROR: local installed version $got != $VERSION" >&2; return 1; }
  echo "==> [local] installed version=${got} (restart deferred)"
  if [[ -n "$RESTART_LOCAL" ]]; then
    ./scripts/restart-and-resume.sh
  fi
}

install_remote() {
  local target="$1"
  local host="${target%%:*}"
  local repo="${target#*:}"
  local zip
  zip="$(mktemp -t tapgo-fleet.XXXXXX).zip"
  local remote_zip="/tmp/tapgo-fleet-${VERSION}.zip"
  local remote_unpack="/tmp/tapgo-fleet-unpack-${VERSION}"
  echo "==> [${host}] installing v${VERSION}"
  if [[ -n "$DRY_RUN" ]]; then
    echo "    [dry-run] copy bundle to ${host}${repo}, install /Applications, restart, verify"
    rm -f "$zip"
    return 0
  fi

  ditto -c -k --keepParent "$APP" "$zip"
  scp -q -o BatchMode=yes "$zip" "${host}:${remote_zip}"
  rm -f "$zip"

  ssh -o BatchMode=yes "$host" bash -s -- "$VERSION" "$remote_zip" "$remote_unpack" <<'REMOTE'
set -euo pipefail
VERSION="$1"; ZIP="$2"; UNPACK="$3"
APP="/Applications/Tapgo AICoding.app"
BIN="$APP/Contents/MacOS/TapgoAICoding"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
HELPER="$APP/Contents/Resources/computer-use-helper/Tapgo Computer Use.app/Contents/MacOS/TapgoComputerUseHelper"

pkill -f "$BIN" 2>/dev/null || true
sleep 1
rm -rf "$APP" "$UNPACK"
mkdir -p "$UNPACK"
ditto -x -k "$ZIP" "$UNPACK"
mv "$UNPACK/Tapgo AICoding.app" "$APP"
rm -rf "$UNPACK" "$ZIP"

# Portable signature: strip the build-host signature, then deep ad-hoc sign.
codesign --remove-signature "$BIN" >/dev/null 2>&1 || true
[[ -f "$SPARKLE" ]] && codesign --remove-signature "$SPARKLE" >/dev/null 2>&1 || true
[[ -f "$HELPER" ]] && codesign --remove-signature "$HELPER" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

GOT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo missing)"
[[ "$GOT" == "$VERSION" ]] || { echo "ERROR: installed version ${GOT} != ${VERSION}" >&2; exit 1; }
open "$APP" >/dev/null 2>&1 || true
sleep 3
PID="$(pgrep -f "$BIN" 2>/dev/null | head -1 || true)"
echo "VERSION=${GOT}"
echo "PID=${PID:-none}"
[[ -n "$PID" ]]
REMOTE
  echo "==> [${host}] restart + version ${VERSION} verified"
}

[[ "$INCLUDE_LOCAL" -eq 1 ]] && install_local
FAIL=0
for target in "${TARGETS[@]}"; do
  if ! install_remote "$target"; then
    echo "ERROR: deployment failed on ${target%%:*}" >&2
    FAIL=1
  fi
done
[[ "$FAIL" -eq 0 ]]
