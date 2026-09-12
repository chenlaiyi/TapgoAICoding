#!/usr/bin/env bash
# rollback-drill.sh — verify that a previous release can actually be restored.
#
# Steps: remote tag exists → obtain its release archive (local dist or gh) →
# health-check the extracted .app → detached worktree at the tag stays clean →
# optionally run a clean release build.
set -euo pipefail

ROOT="${EVOLVE_ROLLBACK_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=scripts/evolution-deps.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/evolution-deps.sh"
cd "$ROOT"
TAG=""; ARCHIVE=""; FULL_BUILD=0; NO_DOWNLOAD=0; HISTORY=""
HEALTH_SCRIPT="${EVOLVE_ROLLBACK_HEALTH_SCRIPT:-$ROOT/scripts/health-check.sh}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:-}"; shift ;;
    --archive) ARCHIVE="${2:-}"; shift ;;
    --health-script) HEALTH_SCRIPT="${2:-}"; shift ;;
    --history) HISTORY="${2:-}"; shift ;;
    --full-build) FULL_BUILD=1 ;;
    --no-download) NO_DOWNLOAD=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "ERROR: unexpected arg: $1" >&2; exit 2 ;;
  esac
  shift
done

STATE_DIR="${EVOLVE_STATE_DIR:-$HOME/Library/Application Support/Tapgo AICoding/state}"
HISTORY="${HISTORY:-$STATE_DIR/rollback_drill_history.jsonl}"
if [[ -z "$TAG" ]]; then
  TAG="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
fi
[[ -n "$TAG" ]] || { echo "ERROR: no target tag; pass --tag." >&2; exit 2; }
VERSION="${TAG#v}"

fail_record() {
  local reason="$1"
  python3 - "$HISTORY" "$TAG" "$reason" <<'PY'
import datetime, json, os, sys
path, tag, reason = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.dirname(path), exist_ok=True)
record = {"schemaVersion": 1, "tag": tag, "ranAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "passed": False, "reason": reason}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, ensure_ascii=False) + "\n")
PY
  echo "ROLLBACK DRILL FAILED: $reason" >&2
  exit 1
}

if ! git ls-remote --tags origin "$TAG" 2>/dev/null | grep -q .; then
  fail_record "remote tag $TAG not found"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-rollback-drill.XXXXXX")"
cleanup() { git worktree remove --force "$TMP/worktree" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

SOURCE="explicit"
if [[ -z "$ARCHIVE" ]]; then
  LOCAL_ZIP="$ROOT/AppBuilder/dist/$TAG/Tapgo-AICoding-$VERSION.zip"
  if [[ -f "$LOCAL_ZIP" ]]; then
    ARCHIVE="$LOCAL_ZIP"; SOURCE="local-dist"
  elif [[ "$NO_DOWNLOAD" -eq 0 ]] && command -v gh >/dev/null 2>&1; then
    (cd "$TMP" && gh release download "$TAG" --pattern '*.zip' >/dev/null)
    ARCHIVE="$(find "$TMP" -maxdepth 1 -name '*.zip' | head -1)"
    SOURCE="github-release"
  fi
fi
[[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] || fail_record "archive missing for $TAG"

mkdir -p "$TMP/extract"
unzip -q "$ARCHIVE" -d "$TMP/extract"
APP="$(find "$TMP/extract" -maxdepth 2 -name 'Tapgo AICoding.app' -type d | head -1)"
[[ -n "$APP" ]] || fail_record "archive has no Tapgo AICoding.app"
if ! "$HEALTH_SCRIPT" "$APP" "$VERSION"; then
  fail_record "health check failed"
fi

git worktree add --detach "$TMP/worktree" "$TAG" >/dev/null
[[ -z "$(git -C "$TMP/worktree" status --porcelain)" ]] || fail_record "worktree not clean"
if [[ "$FULL_BUILD" -eq 1 ]]; then
  if ! (cd "$TMP/worktree" && xcrun -sdk "${TAPGO_SDK:-$(evo_detect_sdk)}" swift build -c release --product TapgoAICoding); then
    fail_record "clean checkout build failed"
  fi
fi

python3 - "$HISTORY" "$TAG" "$SOURCE" "$FULL_BUILD" <<'PY'
import datetime, json, os, sys
path, tag, source, full_build = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
os.makedirs(os.path.dirname(path), exist_ok=True)
record = {
    "schemaVersion": 1,
    "tag": tag,
    "ranAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "passed": True,
    "archiveSource": source,
    "fullBuild": full_build,
}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, ensure_ascii=False) + "\n")
PY
echo "ROLLBACK DRILL OK tag=$TAG archive=$SOURCE fullBuild=$FULL_BUILD"
