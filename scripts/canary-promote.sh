#!/usr/bin/env bash
# canary-promote.sh <version> <canary-host>
# Promote a canary release: publish appcast, undraft GitHub Release, then
# deploy the remaining fleet hosts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${1:-}"; CANARY_HOST="${2:-}"
[[ -n "$VERSION" && -n "$CANARY_HOST" ]] || { echo "usage: canary-promote.sh <version> <canary-host>" >&2; exit 2; }
TAG="v$VERSION"
DIST="$ROOT/AppBuilder/dist/$TAG"
[[ -f "$DIST/appcast.xml" ]] || { echo "ERROR: canary appcast missing: $DIST/appcast.xml" >&2; exit 3; }

cp "$DIST/appcast.xml" "$ROOT/appcast.xml"
git add appcast.xml
if ! git diff --cached --quiet; then
  git commit -m "chore(release): refresh appcast.xml for ${TAG}" >/dev/null
  git push origin HEAD:main >/dev/null
  echo "==> appcast.xml published for ${TAG}"
else
  echo "==> appcast.xml already up to date for ${TAG}"
fi

if command -v gh >/dev/null 2>&1; then
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release edit "$TAG" --draft=false >/dev/null
    echo "==> GitHub Release ${TAG} promoted from draft"
  fi
fi

echo "==> Deploying remaining hosts (excluding canary ${CANARY_HOST})"
./scripts/deploy-fleet.sh --exclude "$CANARY_HOST" "$VERSION"
echo "CANARY PROMOTED ${TAG} canary=${CANARY_HOST}"
