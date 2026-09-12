#!/usr/bin/env bash
# canary-promote.sh <version> <canary-host>
# Promote a canary release: publish appcast, undraft GitHub Release, then
# deploy the remaining fleet hosts.
#
# 可覆盖入口（测试/自定义）：
#   EVOLVE_CANARY_REPO_ROOT / EVOLVE_CANARY_REMOTE / EVOLVE_CANARY_GH /
#   EVOLVE_CANARY_DEPLOY_SCRIPT
# 退出码：2 用法 / 3 缺 appcast / 4 推送失败 / 5 draft 提升失败 / 6 其余机器部署失败
set -euo pipefail
ROOT="${EVOLVE_CANARY_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"
# 与 evolve.sh/sync-upstream.sh 一致：远端名走 tapgo_upstream_remote（不再硬编码 origin）
# shellcheck source=scripts/tapgo-repo-slug.sh
source "$(cd "$(dirname "$0")" && pwd)/tapgo-repo-slug.sh"
UPSTREAM_REMOTE="${EVOLVE_CANARY_REMOTE:-$(tapgo_upstream_remote 2>/dev/null || echo origin)}"
GH_BIN="${EVOLVE_CANARY_GH:-gh}"
DEPLOY_SCRIPT="${EVOLVE_CANARY_DEPLOY_SCRIPT:-$ROOT/scripts/deploy-fleet.sh}"
VERSION="${1:-}"; CANARY_HOST="${2:-}"
[[ -n "$VERSION" && -n "$CANARY_HOST" ]] || { echo "usage: canary-promote.sh <version> <canary-host>" >&2; exit 2; }
TAG="v$VERSION"
DIST="$ROOT/AppBuilder/dist/$TAG"
[[ -f "$DIST/appcast.xml" ]] || { echo "ERROR: canary appcast missing: $DIST/appcast.xml" >&2; exit 3; }

cp "$DIST/appcast.xml" "$ROOT/appcast.xml"
git add appcast.xml
if ! git diff --cached --quiet; then
  git commit -m "chore(release): refresh appcast.xml for ${TAG}" >/dev/null
  if ! git push "$UPSTREAM_REMOTE" HEAD:main >/dev/null; then
    echo "ERROR: appcast.xml 推送失败（${UPSTREAM_REMOTE}），未部署其余机器" >&2
    exit 4
  fi
  echo "==> appcast.xml published for ${TAG}"
else
  echo "==> appcast.xml already up to date for ${TAG}"
fi

if [[ -x "$GH_BIN" ]] || command -v "$GH_BIN" >/dev/null 2>&1; then
  if "$GH_BIN" release view "$TAG" >/dev/null 2>&1; then
    if ! "$GH_BIN" release edit "$TAG" --draft=false >/dev/null; then
      echo "ERROR: gh release edit ${TAG} --draft=false 失败（Release 可能仍是 draft）" >&2
      exit 5
    fi
    echo "==> GitHub Release ${TAG} promoted from draft"
  else
    echo "==> NOTE: GitHub Release ${TAG} 不存在或不可见，跳过 draft 提升"
  fi
else
  echo "==> NOTE: 未找到 gh，跳过 GitHub Release 提升" >&2
fi

echo "==> Deploying remaining hosts (excluding canary ${CANARY_HOST})"
if ! "$DEPLOY_SCRIPT" --exclude "$CANARY_HOST" "$VERSION"; then
  echo "ERROR: 其余机器部署失败（canary 已提升，需人工排查或回滚）" >&2
  exit 6
fi
echo "CANARY PROMOTED ${TAG} canary=${CANARY_HOST}"
